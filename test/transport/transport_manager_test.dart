import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackpad/protocol/input_event.dart';
import 'package:trackpad/protocol/protocol_codec.dart';
import 'package:trackpad/storage/host_info.dart';
import 'package:trackpad/storage/paired_host_store.dart';
import 'package:trackpad/transport/handshake.dart';
import 'package:trackpad/transport/secure_channel.dart';
import 'package:trackpad/transport/transport_client.dart';
import 'package:trackpad/transport/transport_manager.dart';

/// Minimal in-memory agent implementing the handshake in handshake.dart.
class FakeAgent {
  FakeAgent({this.os = HostOS.windows, this.code = '123456', this.secret});

  final HostOS os;
  final String code;
  Uint8List? secret;
  final Uint8List serverNonce =
      Uint8List.fromList(List.generate(16, (i) => i + 100));
  late Uint8List clientNonce;
  SecureChannel? channel;
  bool pairing = false;
  int failed = 0;
  final List<InputEvent> received = [];
  late void Function(Uint8List) reply;

  Future<void> onFrame(Uint8List f) async {
    if (f.length > 1 && f[0] == controlMarker && f[1] == msgClientHello) {
      final hello = ClientHello.decode(f)!;
      clientNonce = hello.clientNonce;
      channel = null;
      final known = secret != null &&
          hello.hasSecret &&
          _eq(hello.fingerprint, await secretFingerprint(secret!));
      pairing = !known;
      reply(ServerHello(
              serverNonce: serverNonce, hostOs: os, pairingRequired: pairing)
          .encode());
      return;
    }
    if (channel != null) {
      final p = await channel!.decrypt(f);
      if (p != null) {
        final r = ProtocolCodec.decode(p);
        if (r is DecodeOk) received.add(r.event);
      }
      return;
    }
    if (!pairing) {
      final ch = await SecureChannel.create(
          sharedSecret: secret!,
          clientNonce: clientNonce,
          serverNonce: serverNonce,
          role: ChannelRole.server);
      final ok = await ch.decrypt(f) != null;
      if (ok) channel = ch;
      reply(PairingResultMessage(
              status: ok ? PairingStatus.accepted : PairingStatus.rejected)
          .encode());
      return;
    }
    final ch = await SecureChannel.create(
        sharedSecret: await pairingSecretFromCode(code),
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        role: ChannelRole.server);
    final plain = await ch.decrypt(f);
    final newSecret = plain == null ? null : decodePairingSubmitPlaintext(plain);
    if (newSecret != null) {
      secret = newSecret;
      channel = await SecureChannel.create(
          sharedSecret: newSecret,
          clientNonce: clientNonce,
          serverNonce: serverNonce,
          role: ChannelRole.server);
      reply(const PairingResultMessage(status: PairingStatus.accepted)
          .encode());
    } else {
      failed++;
      reply(PairingResultMessage(
        status: failed >= 3 ? PairingStatus.lockedOut : PairingStatus.incorrectCode,
        failedAttempts: failed,
        lockoutSeconds: failed >= 3 ? 60 : 0,
      ).encode());
    }
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class FakeClient implements TransportClient {
  FakeClient(this.agent, this.kind) {
    agent.reply = (b) => _frames.add(b);
  }
  final FakeAgent agent;
  @override
  final TransportKind kind;
  final _frames = StreamController<Uint8List>.broadcast();
  final _closed = StreamController<void>.broadcast();
  bool closedLocally = false;

  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  Stream<void> get onClosed => _closed.stream;
  @override
  Future<void> connect(HostInfo host) async {}
  @override
  Future<void> send(Uint8List frameBody) async {
    unawaited(agent.onFrame(frameBody));
  }

  @override
  Future<void> close() async {
    closedLocally = true;
    _closed.add(null);
  }

  void dropLink() => _closed.add(null);
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

const host = HostInfo(
  id: 'h1',
  name: 'Desk',
  os: HostOS.macOS,
  transport: TransportKind.wifi,
  address: '10.0.0.2:52800',
);

Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

void main() {
  group('timing functions', () {
    test('reconnect retries every 3s and stops after 30s', () {
      expect(nextReconnectDelay(Duration.zero), const Duration(seconds: 3));
      expect(nextReconnectDelay(const Duration(seconds: 3)),
          const Duration(seconds: 3));
      expect(nextReconnectDelay(const Duration(seconds: 27)),
          const Duration(seconds: 3));
      expect(nextReconnectDelay(const Duration(seconds: 28)), isNull);
      expect(nextReconnectDelay(const Duration(seconds: 30)), isNull);
    });

    test('background closes at exactly 60s', () {
      expect(shouldCloseAfterBackground(const Duration(seconds: 59)), isFalse);
      expect(shouldCloseAfterBackground(const Duration(seconds: 60)), isTrue);
    });

    test('platform key label and status mapping', () {
      expect(platformKeyLabelFor(HostOS.macOS), 'Command');
      expect(platformKeyLabelFor(HostOS.windows), 'Windows');
      expect(connectionStatusFor(Authenticated(host, DateTime(2024))),
          const ConnectionStatus(
              connected: true, hostName: 'Desk', transport: TransportKind.wifi));
      expect(connectionStatusFor(const Discovering()).connected, isFalse);
    });
  });

  group('handshake messages', () {
    test('round-trip and lengths', () {
      final ch = ClientHello(
          protocolVersion: 1,
          clientNonce: List.filled(16, 7),
          hasSecret: true,
          fingerprint: List.filled(8, 9));
      expect(ch.encode().length, clientHelloLength);
      expect(ClientHello.decode(ch.encode())!.fingerprint, ch.fingerprint);
      final sh = ServerHello(
          serverNonce: List.filled(16, 1),
          hostOs: HostOS.windows,
          pairingRequired: true);
      expect(sh.encode().length, serverHelloLength);
      expect(ServerHello.decode(sh.encode())!.hostOs, HostOS.windows);
      const pr = PairingResultMessage(
          status: PairingStatus.lockedOut, failedAttempts: 3, lockoutSeconds: 60);
      final d = PairingResultMessage.decode(pr.encode())!;
      expect((d.status, d.failedAttempts, d.lockoutSeconds),
          (PairingStatus.lockedOut, 3, 60));
      expect(ServerHello.decode([1, 2, 3]), isNull);
    });
  });

  group('TransportManager', () {
    late FakeAgent agent;
    late FakeClient client;
    late PairedHostStore store;
    late DateTime now;
    late List<FakeTimer> timers;
    late TransportManager manager;
    var clients = 0;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      store = PairedHostStore();
      now = DateTime.utc(2024, 1, 1);
      timers = [];
      clients = 0;
    });

    TransportManager build() => TransportManager(
          clientFactory: (kind) {
            clients++;
            return client = FakeClient(agent, kind);
          },
          pairedHosts: store,
          now: () => now,
          timerFactory: (d, cb) {
            final t = FakeTimer(d, cb);
            timers.add(t);
            return t;
          },
        );

    test('new host: pairing flow, OS label, stored as paired', () async {
      agent = FakeAgent();
      manager = build();
      await manager.connect(host);
      expect(manager.state, isA<AwaitingPairing>());
      expect(manager.hostOs, HostOS.windows);

      expect(await manager.submitPairingCode('000000'),
          PairingOutcome.incorrect);
      expect((manager.state as AwaitingPairing).failedAttempts, 1);
      expect(await manager.submitPairingCode('12ab'),
          PairingOutcome.invalidFormat);

      expect(
          await manager.submitPairingCode('123456'), PairingOutcome.accepted);
      expect(manager.state, isA<Authenticated>());
      expect(manager.platformKeyLabel, 'Windows');
      expect(manager.status.hostName, 'Desk');
      expect(await store.lookup('h1'), isNotNull);

      expect(await manager.send(const AppSwitchEvent()), isTrue);
      await pump();
      expect(agent.received, [const AppSwitchEvent()]);
    });

    test('three wrong codes lock out for 60s', () async {
      agent = FakeAgent();
      manager = build();
      await manager.connect(host);
      await manager.submitPairingCode('000001');
      await manager.submitPairingCode('000002');
      expect(await manager.submitPairingCode('000003'),
          PairingOutcome.lockedOut);
      expect((manager.state as AwaitingPairing).lockedUntil,
          now.add(const Duration(seconds: 60)));
      expect(await manager.submitPairingCode('123456'),
          PairingOutcome.lockedOut);
      expect(agent.received, isEmpty);
    });

    test('paired host skips the pairing code', () async {
      agent = FakeAgent(os: HostOS.macOS);
      manager = build();
      await manager.connect(host);
      await manager.submitPairingCode('123456');
      await manager.disconnect();
      expect(manager.state, isA<Disconnected>());

      await manager.connect(host);
      expect(manager.state, isA<Authenticated>());
      expect(manager.platformKeyLabel, 'Command');
    });

    test('link loss reconnects every 3s, then gives up after 30s', () async {
      agent = FakeAgent();
      manager = build();
      await manager.connect(host);
      await manager.submitPairingCode('123456');

      client.dropLink();
      await pump();
      var s = manager.state as Disconnected;
      expect(s.reason, DisconnectReason.linkLost);
      expect(s.reconnecting, isTrue);
      expect(timers.last.delay, reconnectInterval);

      timers.last.callback();
      await pump();
      expect(manager.state, isA<Authenticated>());
      expect(clients, 2);

      // Second loss with the agent unreachable: advance clock past window.
      client.dropLink();
      await pump();
      now = now.add(const Duration(seconds: 28));
      agent = FakeAgent(); // forgets the phone -> pairing required
      timers.last.callback();
      await pump();
      s = manager.state as Disconnected;
      expect(s.reconnecting, isFalse);
    });

    test('background timeout closes connection, foreground within 60s keeps',
        () async {
      agent = FakeAgent();
      manager = build();
      await manager.connect(host);
      await manager.submitPairingCode('123456');

      manager.appBackgrounded();
      now = now.add(const Duration(seconds: 59));
      await manager.appForegrounded();
      expect(manager.state, isA<Authenticated>());

      manager.appBackgrounded();
      expect(timers.last.delay, backgroundTimeout);
      timers.last.callback();
      await pump();
      expect((manager.state as Disconnected).reason,
          DisconnectReason.backgroundTimeout);
      expect(client.closedLocally, isTrue);
    });

    test('user disconnect closes the link', () async {
      agent = FakeAgent();
      manager = build();
      await manager.connect(host);
      await manager.submitPairingCode('123456');
      await manager.disconnect();
      expect((manager.state as Disconnected).reason,
          DisconnectReason.userRequested);
      expect(client.closedLocally, isTrue);
    });
  });
}
