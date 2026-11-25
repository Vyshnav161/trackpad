/// Transport Manager: owns the Connection state machine, the handshake
/// (see handshake.dart for the wire layout), heartbeat, auto-reconnect and
/// background timeout (Requirements 4.2, 4.3, 4.5, 9.1, 9.2, 9.3, 11.1,
/// 11.2, 11.3, 11.6).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/input_event.dart';
import '../protocol/protocol_codec.dart';
import '../storage/host_info.dart';
import '../storage/paired_host_store.dart';
import 'handshake.dart';
import 'secure_channel.dart';
import 'transport_client.dart';

// ---------------------------------------------------------------------------
// Timing constants and pure timing functions (testable without timers).
// ---------------------------------------------------------------------------

/// The agent closes after 10 s of silence (Requirement 11.4); send well within.
const Duration heartbeatInterval = Duration(seconds: 3);

/// Requirement 11.2.
const Duration disconnectTimeout = Duration(seconds: 2);

/// Requirement 11.3.
const Duration reconnectInterval = Duration(seconds: 3);
const Duration reconnectWindow = Duration(seconds: 30);

/// Requirement 11.6.
const Duration backgroundTimeout = Duration(seconds: 60);

/// Maximum wait for each handshake reply.
const Duration handshakeTimeout = Duration(seconds: 10);

/// Delay before the next reconnect attempt, given the time elapsed since the
/// connection was lost (measured when the previous attempt failed). Returns
/// null once the next attempt would fall after the 30-second window.
Duration? nextReconnectDelay(Duration sinceLoss) {
  final elapsed = sinceLoss.isNegative ? Duration.zero : sinceLoss;
  return elapsed + reconnectInterval <= reconnectWindow
      ? reconnectInterval
      : null;
}

/// True when a connection that spent [inBackground] in the background must
/// be closed (open below 60 s, closed at 60 s and beyond).
bool shouldCloseAfterBackground(Duration inBackground) =>
    inBackground >= backgroundTimeout;

typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

// ---------------------------------------------------------------------------
// Platform key label and status mapping.
// ---------------------------------------------------------------------------

/// Requirements 9.2 and 9.3.
String platformKeyLabelFor(HostOS os) =>
    os == HostOS.macOS ? 'Command' : 'Windows';

/// What the connection indicator shows (Requirement 11.1).
class ConnectionStatus {
  const ConnectionStatus({
    required this.connected,
    this.hostName,
    this.transport,
  });

  final bool connected;
  final String? hostName;
  final TransportKind? transport;

  @override
  bool operator ==(Object other) =>
      other is ConnectionStatus &&
      other.connected == connected &&
      other.hostName == hostName &&
      other.transport == transport;

  @override
  int get hashCode => Object.hash(connected, hostName, transport);

  @override
  String toString() => 'ConnectionStatus($connected, $hostName, $transport)';
}

ConnectionStatus connectionStatusFor(ConnectionState state) =>
    state is Authenticated
    ? ConnectionStatus(
        connected: true,
        hostName: state.host.name,
        transport: state.host.transport,
      )
    : const ConnectionStatus(connected: false);

// ---------------------------------------------------------------------------
// States.
// ---------------------------------------------------------------------------

enum DisconnectReason {
  userRequested,
  connectionFailed,
  linkLost,
  backgroundTimeout,
  pairingRejected,
  protocolError,
}

sealed class ConnectionState {
  const ConnectionState();
}

final class Discovering extends ConnectionState {
  const Discovering();
}

final class Connecting extends ConnectionState {
  const Connecting(this.host);
  final HostInfo host;
}

/// The host requires a Pairing_Code (shown on the desktop). [lockedUntil] is
/// set after the third consecutive incorrect code (Requirement 4.4).
final class AwaitingPairing extends ConnectionState {
  const AwaitingPairing(this.host, {this.failedAttempts = 0, this.lockedUntil});
  final HostInfo host;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

final class Authenticated extends ConnectionState {
  const Authenticated(this.host, this.since);
  final HostInfo host;
  final DateTime since;
}

final class Disconnected extends ConnectionState {
  const Disconnected(
    this.reason, {
    this.host,
    this.failure,
    this.reconnecting = false,
  });
  final DisconnectReason reason;
  final HostInfo? host;

  /// Set when [reason] is [DisconnectReason.connectionFailed].
  final ConnectionFailureReason? failure;

  /// True while automatic reconnect attempts are still being made.
  final bool reconnecting;
}

enum PairingOutcome { accepted, incorrect, lockedOut, invalidFormat, failed }

// ---------------------------------------------------------------------------
// Manager.
// ---------------------------------------------------------------------------

class TransportManager {
  TransportManager({
    required this._clientFactory,
    required this._pairedHosts,
    DateTime Function()? now,
    TimerFactory? timerFactory,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _timer = timerFactory ?? Timer.new,
       _random = random ?? Random.secure();

  final TransportClient Function(TransportKind) _clientFactory;
  final PairedHostStore _pairedHosts;
  final DateTime Function() _now;
  final TimerFactory _timer;
  final Random _random;

  final StreamController<ConnectionState> _states =
      StreamController.broadcast();
  ConnectionState _state = const Discovering();

  _Session? _session;
  int _generation = 0;
  DateTime? _lossAt;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _backgroundTimer;
  DateTime? _backgroundedAt;
  Future<void> _sendChain = Future.value();

  ConnectionState get state => _state;
  Stream<ConnectionState> get states => _states.stream;

  ConnectionStatus get status => connectionStatusFor(_state);

  /// Platform-key label of the connected host, or null when not connected
  /// (Requirements 9.2, 9.3).
  String? get platformKeyLabel {
    final s = _state;
    return s is Authenticated ? platformKeyLabelFor(s.host.os) : null;
  }

  /// Host OS reported by the agent for the current/pending connection.
  HostOS? get hostOs => _session?.host.os;

  void _setState(ConnectionState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Returns to the Discovering state (e.g. when the host list opens).
  Future<void> startDiscovery() async {
    await _close(null);
    _setState(const Discovering());
  }

  /// Connects to [host]. Resulting state is Authenticated (paired host,
  /// Requirement 4.5), AwaitingPairing (new host) or Disconnected.
  Future<void> connect(HostInfo host) async {
    await _close(null);
    final gen = ++_generation;
    _setState(Connecting(host));
    final result = await _establish(host, gen);
    if (result != null && gen == _generation) _apply(result);
  }

  /// Submits the 6-digit code shown by the agent (Requirements 4.2, 4.3, 4.4).
  Future<PairingOutcome> submitPairingCode(String code) async {
    final st = _state;
    final s = _session;
    if (st is! AwaitingPairing || s == null) return PairingOutcome.failed;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return PairingOutcome.invalidFormat;
    final lock = st.lockedUntil;
    if (lock != null && _now().isBefore(lock)) return PairingOutcome.lockedOut;
    final gen = _generation;

    PairingResultMessage? result;
    final newSecret = _randomBytes(pairingSecretLength);
    try {
      final pairingChannel = await SecureChannel.create(
        sharedSecret: await pairingSecretFromCode(code),
        clientNonce: s.clientNonce,
        serverNonce: s.serverNonce,
        role: ChannelRole.client,
      );
      await s.client.send(
        await pairingChannel.encrypt(encodePairingSubmitPlaintext(newSecret)),
      );
      result = PairingResultMessage.decode(
        await s.queue.next(handshakeTimeout),
      );
    } catch (_) {
      result = null;
    }
    if (gen != _generation || _session != s) return PairingOutcome.failed;
    if (result == null) {
      await _failSession(s, DisconnectReason.protocolError);
      return PairingOutcome.failed;
    }

    switch (result.status) {
      case PairingStatus.accepted:
        await _pairedHosts.add(
          PairedHost(
            hostInfo: s.host,
            sharedSecret: newSecret,
            pairedAt: _now().toUtc(),
          ),
        );
        s.channel = await SecureChannel.create(
          sharedSecret: newSecret,
          clientNonce: s.clientNonce,
          serverNonce: s.serverNonce,
          role: ChannelRole.client,
        );
        if (gen != _generation || _session != s) return PairingOutcome.failed;
        _apply(Authenticated(s.host, _now()));
        return PairingOutcome.accepted;
      case PairingStatus.incorrectCode:
        _setState(
          AwaitingPairing(s.host, failedAttempts: result.failedAttempts),
        );
        return PairingOutcome.incorrect;
      case PairingStatus.lockedOut:
        _setState(
          AwaitingPairing(
            s.host,
            failedAttempts: result.failedAttempts,
            lockedUntil: _now().add(Duration(seconds: result.lockoutSeconds)),
          ),
        );
        return PairingOutcome.lockedOut;
      case PairingStatus.rejected:
        await _failSession(s, DisconnectReason.pairingRejected);
        return PairingOutcome.failed;
    }
  }

  /// Encrypts and sends [event]. Returns false if not authenticated.
  Future<bool> send(InputEvent event) async {
    final s = _session;
    if (_state is! Authenticated || s == null || s.channel == null) {
      return false;
    }
    final channel = s.channel!;
    final bytes = ProtocolCodec.encode(event);
    // Serialize so counters reach the wire in order.
    final done = _sendChain.then((_) async {
      await s.client.send(await channel.encrypt(bytes));
    });
    _sendChain = done.then((_) {}, onError: (_) {});
    try {
      await done;
      return true;
    } catch (_) {
      _onLinkClosed(s.client);
      return false;
    }
  }

  /// User-requested disconnect; closes within 2 seconds (Requirement 11.2).
  Future<void> disconnect() async {
    final host = _session?.host ?? _hostOf(_state);
    await _close(DisconnectReason.userRequested, host: host);
  }

  /// Call when the app moves to the background (Requirement 11.6).
  void appBackgrounded() {
    if (_state is! Authenticated) return;
    _backgroundTimer?.cancel();
    _backgroundedAt = _now();
    _backgroundTimer = _timer(backgroundTimeout, _onBackgroundTimeout);
  }

  /// Call when the app returns to the foreground. Also closes the connection
  /// if the timer was delayed (e.g. the process was suspended) past 60 s.
  Future<void> appForegrounded() async {
    final at = _backgroundedAt;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _backgroundedAt = null;
    if (at != null &&
        _state is Authenticated &&
        shouldCloseAfterBackground(_now().difference(at))) {
      await _closeForBackground();
    }
  }

  Future<void> dispose() async {
    await _close(null);
    await _states.close();
  }

  // -- internals ------------------------------------------------------------

  HostInfo? _hostOf(ConnectionState s) => switch (s) {
    Connecting(:final host) => host,
    AwaitingPairing(:final host) => host,
    Authenticated(:final host) => host,
    Disconnected(:final host) => host,
    Discovering() => null,
  };

  void _onBackgroundTimeout() {
    if (_state is Authenticated) _closeForBackground();
  }

  Future<void> _closeForBackground() =>
      _close(DisconnectReason.backgroundTimeout, host: _hostOf(_state));

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  /// Applies a result of [_establish].
  void _apply(ConnectionState result) {
    _setState(result);
    if (result is Authenticated) {
      _lossAt = null;
      _scheduleHeartbeat();
    }
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = _timer(heartbeatInterval, () async {
      if (_state is! Authenticated) return;
      await send(const Heartbeat());
      if (_state is Authenticated) _scheduleHeartbeat();
    });
  }

  /// Runs connect + handshake. Returns the resulting state (not yet applied),
  /// or null if superseded. On Disconnected results the session is already
  /// torn down; on AwaitingPairing/Authenticated it is kept in [_session].
  Future<ConnectionState?> _establish(HostInfo host, int gen) async {
    final client = _clientFactory(host.transport);
    try {
      await client.connect(host);
    } on ConnectionFailure catch (e) {
      return Disconnected(
        DisconnectReason.connectionFailed,
        host: host,
        failure: e.reason,
      );
    } catch (_) {
      return Disconnected(
        DisconnectReason.connectionFailed,
        host: host,
        failure: ConnectionFailureReason.unknown,
      );
    }
    if (gen != _generation) {
      await _safeClose(client);
      return null;
    }

    final queue = _FrameQueue(client.frames);
    final session = _Session(client, queue, host);
    session.closedSub = client.onClosed.listen((_) => _onLinkClosed(client));
    _session = session;

    try {
      final paired = await _pairedHosts.lookup(host.id);
      final clientNonce = _randomBytes(SecureChannel.nonceLength);
      session.clientNonce = clientNonce;
      await client.send(
        ClientHello(
          protocolVersion: ProtocolCodec.version,
          clientNonce: clientNonce,
          hasSecret: paired != null,
          fingerprint: paired == null
              ? Uint8List(fingerprintLength)
              : await secretFingerprint(paired.sharedSecret),
        ).encode(),
      );

      final hello = ServerHello.decode(await queue.next(handshakeTimeout));
      if (hello == null) throw const _HandshakeError();
      session.serverNonce = hello.serverNonce;
      // Requirement 9.1: the agent-reported OS replaces any discovered value.
      session.host = HostInfo(
        id: host.id,
        name: host.name,
        os: hello.hostOs,
        transport: host.transport,
        address: host.address,
      );

      if (hello.pairingRequired) {
        return AwaitingPairing(session.host);
      }
      if (paired == null) throw const _HandshakeError();

      // Paired host: prove key possession, no Pairing_Code (Requirement 4.5).
      final channel = await SecureChannel.create(
        sharedSecret: paired.sharedSecret,
        clientNonce: clientNonce,
        serverNonce: hello.serverNonce,
        role: ChannelRole.client,
      );
      await client.send(
        await channel.encrypt(ProtocolCodec.encode(const Heartbeat())),
      );
      final result = PairingResultMessage.decode(
        await queue.next(handshakeTimeout),
      );
      if (gen != _generation) return null;
      if (result == null) throw const _HandshakeError();
      if (result.status != PairingStatus.accepted) {
        await _failSession(
          session,
          DisconnectReason.pairingRejected,
          announce: false,
        );
        return Disconnected(
          DisconnectReason.pairingRejected,
          host: session.host,
        );
      }
      session.channel = channel;
      queue.stopBuffering();
      return Authenticated(session.host, _now());
    } on ConnectionFailure catch (e) {
      await _failSession(
        session,
        DisconnectReason.connectionFailed,
        announce: false,
      );
      return Disconnected(
        DisconnectReason.connectionFailed,
        host: host,
        failure: e.reason,
      );
    } catch (_) {
      if (gen != _generation) return null;
      await _failSession(
        session,
        DisconnectReason.protocolError,
        announce: false,
      );
      return Disconnected(DisconnectReason.protocolError, host: host);
    }
  }

  /// Tears down [s] and moves to Disconnected(reason).
  Future<void> _failSession(
    _Session s,
    DisconnectReason reason, {
    bool announce = true,
  }) async {
    if (_session == s) {
      _heartbeatTimer?.cancel();
      _session = null;
    }
    await s.dispose();
    if (announce) _setState(Disconnected(reason, host: s.host));
  }

  void _onLinkClosed(TransportClient client) {
    final s = _session;
    if (s == null || s.client != client) return;
    final st = _state;
    if (st is Authenticated) {
      _heartbeatTimer?.cancel();
      _backgroundTimer?.cancel();
      _session = null;
      s.dispose();
      _lossAt = _now();
      final gen = ++_generation;
      _setState(
        Disconnected(
          DisconnectReason.linkLost,
          host: s.host,
          reconnecting: true,
        ),
      );
      _scheduleReconnect(s.host, gen);
    } else if (st is AwaitingPairing) {
      _failSession(s, DisconnectReason.linkLost);
    } else {
      s.queue.fail(); // Connecting: the handshake in progress will fail.
    }
  }

  void _scheduleReconnect(HostInfo host, int gen) {
    final loss = _lossAt;
    final delay = loss == null
        ? null
        : nextReconnectDelay(_now().difference(loss));
    if (delay == null) {
      _setState(Disconnected(DisconnectReason.linkLost, host: host));
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = _timer(delay, () => _reconnectAttempt(host, gen));
  }

  Future<void> _reconnectAttempt(HostInfo host, int gen) async {
    if (gen != _generation) return;
    final result = await _establish(host, gen);
    if (result == null || gen != _generation) return;
    switch (result) {
      case Authenticated():
        _apply(result);
      case AwaitingPairing():
        // The agent no longer knows this phone; user action is required.
        final s = _session;
        if (s != null) await _failSession(s, DisconnectReason.pairingRejected);
      case Disconnected(reason: DisconnectReason.pairingRejected):
        _setState(result);
      case _:
        _scheduleReconnect(host, gen);
    }
  }

  /// Stops all activity and closes the link. When [reason] is non-null the
  /// state becomes Disconnected immediately, before the close completes.
  Future<void> _close(DisconnectReason? reason, {HostInfo? host}) async {
    _generation++;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _backgroundTimer?.cancel();
    _backgroundedAt = null;
    _lossAt = null;
    final s = _session;
    _session = null;
    if (reason != null) _setState(Disconnected(reason, host: host ?? s?.host));
    if (s != null) {
      await s.dispose(close: true).timeout(disconnectTimeout, onTimeout: () {});
    }
  }

  Future<void> _safeClose(TransportClient c) async {
    try {
      await c.close();
    } catch (_) {}
  }
}

class _HandshakeError implements Exception {
  const _HandshakeError();
}

class _Session {
  _Session(this.client, this.queue, this.host);

  final TransportClient client;
  final _FrameQueue queue;
  HostInfo host;
  Uint8List clientNonce = Uint8List(0);
  Uint8List serverNonce = Uint8List(0);
  SecureChannel? channel;
  StreamSubscription<void>? closedSub;

  Future<void> dispose({bool close = true}) async {
    await closedSub?.cancel();
    queue.fail();
    if (close) {
      try {
        await client.close();
      } catch (_) {}
    }
  }
}

/// Buffers frames so the handshake can await them one at a time.
class _FrameQueue {
  _FrameQueue(Stream<Uint8List> frames) {
    _sub = frames.listen((f) {
      if (_discard) return;
      if (_waiter != null) {
        final w = _waiter!;
        _waiter = null;
        w.complete(f);
      } else {
        _buffer.add(f);
      }
    });
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<Uint8List> _buffer = [];
  Completer<Uint8List>? _waiter;
  bool _discard = false;
  bool _failed = false;

  Future<Uint8List> next(Duration timeout) {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    if (_failed) return Future.error(StateError('connection closed'));
    final w = _waiter = Completer<Uint8List>();
    return w.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiter, w)) _waiter = null;
        throw TimeoutException('handshake reply timed out');
      },
    );
  }

  /// After authentication, incoming frames are not consumed by the manager.
  void stopBuffering() {
    _discard = true;
    _buffer.clear();
  }

  void fail() {
    _failed = true;
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.completeError(StateError('closed'));
    _sub.cancel();
  }
}
