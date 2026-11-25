/// Shared transport abstractions used by the Wi-Fi and Bluetooth clients.
library;

import 'dart:typed_data';

import '../storage/host_info.dart';

/// Closed set of user-facing connection failure reasons (Requirements 2.4, 3.4).
enum ConnectionFailureReason {
  hostUnreachable,
  timeout,
  refused,
  bluetoothOff,
  bluetoothUnavailable,
  permissionDenied,
  unknown,
}

extension ConnectionFailureReasonMessage on ConnectionFailureReason {
  String get userMessage {
    switch (this) {
      case ConnectionFailureReason.hostUnreachable:
        return 'The computer could not be reached. Check that it is on the '
            'same network and the address is correct.';
      case ConnectionFailureReason.timeout:
        return 'The connection timed out. Make sure the desktop app is '
            'running and try again.';
      case ConnectionFailureReason.refused:
        return 'The computer refused the connection. Make sure the desktop '
            'app is running.';
      case ConnectionFailureReason.bluetoothOff:
        return 'Bluetooth is turned off. Turn Bluetooth on and try again.';
      case ConnectionFailureReason.bluetoothUnavailable:
        return 'Bluetooth is not available on this device.';
      case ConnectionFailureReason.permissionDenied:
        return 'Permission was denied. Grant the required permission and '
            'try again.';
      case ConnectionFailureReason.unknown:
        return 'The connection failed for an unknown reason.';
    }
  }
}

/// Thrown by [TransportClient.connect] when a connection attempt fails.
class ConnectionFailure implements Exception {
  const ConnectionFailure(this.reason, [this.cause]);

  final ConnectionFailureReason reason;

  /// Underlying error, for logging only.
  final Object? cause;

  String get userMessage => reason.userMessage;

  @override
  String toString() =>
      'ConnectionFailure(${reason.name}'
      '${cause == null ? '' : ': $cause'})';
}

/// A byte-stream transport carrying length-prefix framed messages.
abstract class TransportClient {
  TransportKind get kind;

  /// Decoded frame payloads (length prefix removed).
  Stream<Uint8List> get frames;

  /// Connects to [host]. Throws [ConnectionFailure] on failure.
  Future<void> connect(HostInfo host);

  /// Sends [frameBody], adding the length prefix.
  Future<void> send(Uint8List frameBody);

  Future<void> close();

  /// Emits once when the connection closes (locally or by the peer).
  Stream<void> get onClosed;
}

/// Discovers advertised Desktop_Agent hosts on one transport.
abstract class HostDiscovery {
  /// Emits the cumulative list of hosts found so far, each time it changes.
  /// Completes after [timeout].
  Stream<List<HostInfo>> discover({Duration timeout});
}
