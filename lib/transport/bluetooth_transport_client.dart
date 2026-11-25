/// Bluetooth Classic (RFCOMM) transport client (Requirements 3.1-3.4).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import '../protocol/framing.dart';
import '../storage/host_info.dart';
import 'bluetooth_discovery.dart';
import 'transport_client.dart';

class BluetoothTransportClient implements TransportClient {
  BluetoothTransportClient({
    FlutterBlueClassic? bluetooth,
    this._requestPermissions,
    this.connectTimeout = const Duration(seconds: 10),
  }) : _bluetooth = bluetooth ?? FlutterBlueClassic();

  final FlutterBlueClassic _bluetooth;
  final Future<bool> Function()? _requestPermissions;

  /// Requirement 3.2: connected state within 10 seconds.
  final Duration connectTimeout;

  final StreamController<Uint8List> _frames = StreamController.broadcast();
  final StreamController<void> _closed = StreamController.broadcast();
  FrameDecoder _decoder = FrameDecoder();
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSub;
  bool _closeEmitted = false;

  @override
  TransportKind get kind => TransportKind.bluetooth;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get onClosed => _closed.stream;

  @override
  Future<void> connect(HostInfo host) async {
    await close();
    _closeEmitted = false;
    _decoder = FrameDecoder();

    await ensureBluetoothReady(
      _bluetooth,
      requestPermissions: _requestPermissions,
    );

    final BluetoothConnection? conn;
    try {
      conn = await _bluetooth
          .connect(host.address, uuid: agentRfcommServiceUuid)
          .timeout(connectTimeout);
    } catch (e) {
      // Adapter may have been switched off during the attempt.
      if (!await _safeIsEnabled()) {
        throw ConnectionFailure(ConnectionFailureReason.bluetoothOff, e);
      }
      throw ConnectionFailure(mapBluetoothError(e), e);
    }
    if (conn == null) {
      throw const ConnectionFailure(ConnectionFailureReason.hostUnreachable);
    }

    _connection = conn;
    _inputSub = conn.input?.listen(
      _onData,
      onError: (Object _) => _emitClosed(),
      onDone: _emitClosed,
      cancelOnError: true,
    );
    if (_inputSub == null) {
      _connection = null;
      conn.dispose();
      throw const ConnectionFailure(ConnectionFailureReason.unknown);
    }
  }

  Future<bool> _safeIsEnabled() async {
    try {
      return await _bluetooth.isEnabled;
    } catch (_) {
      return true;
    }
  }

  void _onData(Uint8List chunk) {
    for (final frame in _decoder.add(chunk)) {
      if (!_frames.isClosed) _frames.add(frame);
    }
    if (_decoder.corrupted) {
      close();
    }
  }

  @override
  Future<void> send(Uint8List frameBody) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Bluetooth connection is not open');
    }
    conn.output.add(encodeFrame(frameBody));
    await conn.output.allSent;
  }

  @override
  Future<void> close() async {
    final conn = _connection;
    _connection = null;
    final sub = _inputSub;
    _inputSub = null;
    await sub?.cancel();
    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
      _emitClosed();
    }
  }

  void _emitClosed() {
    if (_closeEmitted) return;
    _closeEmitted = true;
    _connection = null;
    if (!_closed.isClosed) _closed.add(null);
  }
}
