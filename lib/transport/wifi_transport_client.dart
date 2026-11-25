/// Wi-Fi transport: TCP + TLS with length-prefix framing
/// (Requirements 2.1, 2.2, 2.3, 2.4).
///
/// Note: the 16-byte nonce exchange and SecureChannel encryption are layered
/// above this client by the connection manager; this class only carries
/// frames.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/framing.dart';
import '../storage/host_info.dart';
import 'ip_validator.dart';
import 'transport_client.dart';

/// Default Desktop_Agent TCP port when the user enters only an IP address.
const int defaultAgentPort = 52800;

/// Requirement 2.3: connected state within 5 seconds.
const Duration connectTimeout = Duration(seconds: 5);

/// Parses `ip`, `ip:port`, `[ipv6]` or `[ipv6]:port`. Returns null if the
/// address is not a syntactically valid IP address or the port is invalid.
({String ip, int port})? parseHostAddress(String input) {
  final s = input.trim();
  String ip;
  String? portText;
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end < 0) return null;
    ip = s.substring(1, end);
    final rest = s.substring(end + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) return null;
      portText = rest.substring(1);
    }
  } else if (isValidIPv6(s)) {
    ip = s;
  } else {
    final colon = s.indexOf(':');
    if (colon < 0) {
      ip = s;
    } else {
      ip = s.substring(0, colon);
      portText = s.substring(colon + 1);
    }
  }
  if (!isValidIpAddress(ip)) return null;
  var port = defaultAgentPort;
  if (portText != null) {
    final p = int.tryParse(portText);
    if (p == null || p < 1 || p > 65535) return null;
    port = p;
  }
  return (ip: ip, port: port);
}

/// Maps a socket/timeout error to a user-facing failure reason.
ConnectionFailureReason mapSocketError(Object error) {
  if (error is TimeoutException) return ConnectionFailureReason.timeout;
  if (error is HandshakeException || error is TlsException) {
    return ConnectionFailureReason.unknown;
  }
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    switch (code) {
      case 111: // ECONNREFUSED (Linux/Android)
      case 61: // ECONNREFUSED (macOS)
      case 10061: // WSAECONNREFUSED
        return ConnectionFailureReason.refused;
      case 110: // ETIMEDOUT (Linux/Android)
      case 60: // ETIMEDOUT (macOS)
      case 10060: // WSAETIMEDOUT
        return ConnectionFailureReason.timeout;
      case 101: // ENETUNREACH
      case 113: // EHOSTUNREACH
      case 51: // ENETUNREACH (macOS)
      case 65: // EHOSTUNREACH (macOS)
      case 64: // EHOSTDOWN (macOS)
      case 10051:
      case 10065:
        return ConnectionFailureReason.hostUnreachable;
    }
    final msg = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    if (msg.contains('refused')) return ConnectionFailureReason.refused;
    if (msg.contains('timed out')) return ConnectionFailureReason.timeout;
    if (msg.contains('unreachable') ||
        msg.contains('no route') ||
        msg.contains('failed host lookup')) {
      return ConnectionFailureReason.hostUnreachable;
    }
  }
  return ConnectionFailureReason.unknown;
}

class WifiTransportClient implements TransportClient {
  WifiTransportClient({this.timeout = connectTimeout});

  final Duration timeout;

  Socket? _socket;
  final FrameDecoder _decoder = FrameDecoder();
  final StreamController<Uint8List> _frames = StreamController.broadcast();
  final StreamController<void> _closed = StreamController.broadcast();
  bool _closeNotified = false;

  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  /// Connects to a manually entered address (`ip` or `ip:port`).
  Future<void> connectToAddress(String address) {
    return connect(
      HostInfo(
        id: address,
        name: address,
        os: HostOS.macOS,
        transport: TransportKind.wifi,
        address: address,
      ),
    );
  }

  @override
  Future<void> connect(HostInfo host) async {
    if (_socket != null) {
      throw StateError('Already connected');
    }
    final target = parseHostAddress(host.address);
    if (target == null) {
      throw const ConnectionFailure(ConnectionFailureReason.hostUnreachable);
    }
    SecureSocket socket;
    try {
      // The agent uses a self-signed certificate; trust is established by
      // pairing (shared secret + SecureChannel), not by the CA chain.
      socket = await SecureSocket.connect(
        target.ip,
        target.port,
        timeout: timeout,
        onBadCertificate: (_) => true,
      ).timeout(timeout);
    } catch (e) {
      throw ConnectionFailure(mapSocketError(e), e);
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    socket.listen(
      (chunk) {
        for (final f in _decoder.add(chunk)) {
          if (!_frames.isClosed) _frames.add(f);
        }
        if (_decoder.corrupted) {
          close();
        }
      },
      onError: (Object _) => _handleClosed(),
      onDone: _handleClosed,
      cancelOnError: true,
    );
  }

  @override
  Future<void> send(Uint8List frameBody) async {
    final s = _socket;
    if (s == null) throw StateError('Not connected');
    s.add(encodeFrame(frameBody));
    await s.flush();
  }

  @override
  Future<void> close() async {
    final s = _socket;
    _socket = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {
        s.destroy();
      }
    }
    _notifyClosed();
  }

  void _handleClosed() {
    final s = _socket;
    _socket = null;
    s?.destroy();
    _notifyClosed();
  }

  void _notifyClosed() {
    if (_closeNotified) return;
    _closeNotified = true;
    if (!_closed.isClosed) _closed.add(null);
  }
}
