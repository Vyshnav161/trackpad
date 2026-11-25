import '../storage/host_info.dart';

/// What the host list shows for one discovered host (Requirement 1.2).
class HostDisplay {
  const HostDisplay({
    required this.name,
    required this.os,
    required this.transport,
  });

  final String name;
  final HostOS os;
  final TransportKind transport;

  @override
  bool operator ==(Object other) =>
      other is HostDisplay &&
      other.name == name &&
      other.os == os &&
      other.transport == transport;

  @override
  int get hashCode => Object.hash(name, os, transport);

  @override
  String toString() => 'HostDisplay($name, ${os.name}, ${transport.name})';
}

HostDisplay toHostDisplay(HostInfo host) =>
    HostDisplay(name: host.name, os: host.os, transport: host.transport);
