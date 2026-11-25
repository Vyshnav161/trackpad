/// Bluetooth Classic discovery of Desktop_Agent hosts (Requirements 1.1, 1.5).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import '../storage/host_info.dart';
import 'transport_client.dart';

/// RFCOMM service UUID published by the Desktop_Agent's SDP record.
const String agentRfcommServiceUuid = '6f1b5a3e-7c2d-4e8a-9b41-3d5e2a7c9f10';

/// Maps a platform error raised while using Bluetooth to a failure reason.
ConnectionFailureReason mapBluetoothError(Object error) {
  if (error is ConnectionFailure) return error.reason;
  if (error is TimeoutException) return ConnectionFailureReason.timeout;
  final text =
      (error is PlatformException
              ? '${error.code} ${error.message ?? ''}'
              : error.toString())
          .toLowerCase();
  if (text.contains('permission') || text.contains('security')) {
    return ConnectionFailureReason.permissionDenied;
  }
  if (text.contains('adapter') &&
          (text.contains('off') || text.contains('disabled')) ||
      text.contains('bluetooth is off') ||
      text.contains('turned off') ||
      text.contains('not enabled')) {
    return ConnectionFailureReason.bluetoothOff;
  }
  if (text.contains('not supported') || text.contains('unavailable')) {
    return ConnectionFailureReason.bluetoothUnavailable;
  }
  if (text.contains('timed out') || text.contains('timeout')) {
    return ConnectionFailureReason.timeout;
  }
  if (text.contains('refused')) return ConnectionFailureReason.refused;
  if (text.contains('unreachable') ||
      text.contains('read failed') ||
      text.contains('socket might closed') ||
      text.contains('connect')) {
    return ConnectionFailureReason.hostUnreachable;
  }
  return ConnectionFailureReason.unknown;
}

/// Verifies the adapter is supported and on, and that runtime permissions are
/// granted. Throws [ConnectionFailure] otherwise.
Future<void> ensureBluetoothReady(
  FlutterBlueClassic bluetooth, {
  Future<bool> Function()? requestPermissions,
}) async {
  if (!await bluetooth.isSupported) {
    throw const ConnectionFailure(ConnectionFailureReason.bluetoothUnavailable);
  }
  final granted = await (requestPermissions ?? _requestBluetoothPermissions)();
  if (!granted) {
    throw const ConnectionFailure(ConnectionFailureReason.permissionDenied);
  }
  if (!await bluetooth.isEnabled) {
    throw const ConnectionFailure(ConnectionFailureReason.bluetoothOff);
  }
}

Future<bool> _requestBluetoothPermissions() async {
  final results = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();
  return results.values.every((s) => s.isGranted || s.isLimited);
}

/// Infers the host OS from the advertised device name (the agent includes the
/// OS in its Bluetooth name); defaults to Windows when not indicated.
HostOS inferHostOs(String name) {
  final n = name.toLowerCase();
  if (n.contains('mac') || n.contains('apple')) return HostOS.macOS;
  return HostOS.windows;
}

bool _exposesAgentService(BluetoothDevice d) => d.uuids
    .map((u) => u.toLowerCase())
    .contains(agentRfcommServiceUuid.toLowerCase());

/// Discovers paired and nearby devices that expose the agent's RFCOMM service.
class BluetoothDiscovery implements HostDiscovery {
  BluetoothDiscovery({FlutterBlueClassic? bluetooth, this._requestPermissions})
    : _bluetooth = bluetooth ?? FlutterBlueClassic();

  final FlutterBlueClassic _bluetooth;
  final Future<bool> Function()? _requestPermissions;

  /// Errors ([ConnectionFailure] with bluetoothOff / permissionDenied /
  /// bluetoothUnavailable) are delivered through the stream so the UI can
  /// prompt the user (Requirements 1.5, 3.3).
  @override
  Stream<List<HostInfo>> discover({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final controller = StreamController<List<HostInfo>>();
    StreamSubscription<BluetoothDevice>? scanSub;
    Timer? timer;
    var closed = false;

    Future<void> finish() async {
      if (closed) return;
      closed = true;
      timer?.cancel();
      await scanSub?.cancel();
      try {
        _bluetooth.stopScan();
      } catch (_) {}
      await controller.close();
    }

    controller.onListen = () async {
      final found = <String, HostInfo>{};
      void add(BluetoothDevice d) {
        if (closed || !_exposesAgentService(d)) return;
        final name = d.alias ?? d.name ?? d.address;
        final host = HostInfo(
          id: d.address,
          name: name.isEmpty ? d.address : name,
          os: inferHostOs(name),
          transport: TransportKind.bluetooth,
          address: d.address,
        );
        if (found[host.id] == host) return;
        found[host.id] = host;
        controller.add(List.unmodifiable(found.values));
      }

      try {
        await ensureBluetoothReady(
          _bluetooth,
          requestPermissions: _requestPermissions,
        );
        timer = Timer(timeout, finish);
        for (final d in await _bluetooth.bondedDevices ?? const []) {
          add(d);
        }
        scanSub = _bluetooth.scanResults.listen(
          add,
          onError: (Object e) {
            if (!closed) {
              controller.addError(ConnectionFailure(mapBluetoothError(e), e));
            }
          },
        );
        _bluetooth.startScan();
      } catch (e) {
        if (!closed) {
          controller.addError(
            e is ConnectionFailure
                ? e
                : ConnectionFailure(mapBluetoothError(e), e),
          );
        }
        await finish();
      }
    };
    controller.onCancel = finish;
    return controller.stream;
  }
}
