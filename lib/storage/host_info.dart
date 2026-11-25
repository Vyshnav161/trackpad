import 'dart:convert';
import 'dart:typed_data';

enum HostOS { macOS, windows }

enum TransportKind { wifi, bluetooth }

/// Identity and contact details of a Desktop_Agent host.
class HostInfo {
  const HostInfo({
    required this.id,
    required this.name,
    required this.os,
    required this.transport,
    required this.address,
  });

  /// Stable identifier (MAC / service UUID).
  final String id;
  final String name;
  final HostOS os;
  final TransportKind transport;

  /// IP:port or Bluetooth MAC.
  final String address;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'os': os.name,
    'transport': transport.name,
    'address': address,
  };

  factory HostInfo.fromJson(Map<String, Object?> json) => HostInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    os: HostOS.values.byName(json['os']! as String),
    transport: TransportKind.values.byName(json['transport']! as String),
    address: json['address']! as String,
  );

  @override
  bool operator ==(Object other) =>
      other is HostInfo &&
      other.id == id &&
      other.name == name &&
      other.os == os &&
      other.transport == transport &&
      other.address == address;

  @override
  int get hashCode => Object.hash(id, name, os, transport, address);

  @override
  String toString() =>
      'HostInfo($id, $name, ${os.name}, ${transport.name}, $address)';
}

/// A host that completed pairing, with the secret established during pairing.
class PairedHost {
  PairedHost({
    required this.hostInfo,
    required Uint8List sharedSecret,
    required this.pairedAt,
  }) : sharedSecret = Uint8List.fromList(sharedSecret);

  final HostInfo hostInfo;
  final Uint8List sharedSecret;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
    'hostInfo': hostInfo.toJson(),
    'sharedSecret': base64Encode(sharedSecret),
    'pairedAt': pairedAt.toUtc().microsecondsSinceEpoch,
  };

  factory PairedHost.fromJson(Map<String, Object?> json) => PairedHost(
    hostInfo: HostInfo.fromJson(
      Map<String, Object?>.from(json['hostInfo']! as Map),
    ),
    sharedSecret: base64Decode(json['sharedSecret']! as String),
    pairedAt: DateTime.fromMicrosecondsSinceEpoch(
      json['pairedAt']! as int,
      isUtc: true,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is PairedHost &&
      other.hostInfo == hostInfo &&
      other.pairedAt.isAtSameMomentAs(pairedAt) &&
      _bytesEqual(other.sharedSecret, sharedSecret);

  @override
  int get hashCode => Object.hash(
    hostInfo,
    pairedAt.microsecondsSinceEpoch,
    Object.hashAll(sharedSecret),
  );

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
