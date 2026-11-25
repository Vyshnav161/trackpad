/// mDNS discovery of Desktop_Agent services on the local Wi-Fi network
/// (Requirements 1.1, 1.3, 1.4).
///
/// The Desktop_Agent advertises `_trackpad._tcp` with TXT records:
///   * `id` - stable host identifier (optional; defaults to the service name)
///   * `os` - `macOS` or `windows`
/// The service name is the Host name.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../storage/host_info.dart';
import 'transport_client.dart';

const String trackpadServiceType = '_trackpad._tcp';

/// Time after which the UI should offer manual IP entry when nothing was
/// found (Requirement 1.4).
const Duration defaultDiscoveryTimeout = Duration(seconds: 10);

String? _txtString(Map<String, Uint8List?>? txt, String key) {
  final v = txt?[key];
  return v == null ? null : utf8.decode(v, allowMalformed: true);
}

/// Converts a resolved mDNS service to a [HostInfo], or null if it lacks a
/// usable address or port.
HostInfo? hostInfoFromService(nsd.Service service) {
  final port = service.port;
  if (port == null) return null;
  final addresses = service.addresses;
  String? ip;
  if (addresses != null && addresses.isNotEmpty) {
    // Prefer IPv4 for simplicity; fall back to the first address.
    final v4 = addresses.where((a) => a.type.name == 'IPv4');
    ip = (v4.isNotEmpty ? v4.first : addresses.first).address;
  } else {
    ip = service.host;
  }
  if (ip == null || ip.isEmpty) return null;
  final name = service.name ?? ip;
  final osText = _txtString(service.txt, 'os')?.toLowerCase();
  final os = (osText != null && osText.startsWith('win'))
      ? HostOS.windows
      : HostOS.macOS;
  final host = ip.contains(':') ? '[$ip]' : ip;
  return HostInfo(
    id: _txtString(service.txt, 'id') ?? name,
    name: name,
    os: os,
    transport: TransportKind.wifi,
    address: '$host:$port',
  );
}

class WifiDiscovery implements HostDiscovery {
  const WifiDiscovery();

  @override
  Stream<List<HostInfo>> discover({
    Duration timeout = defaultDiscoveryTimeout,
  }) {
    late StreamController<List<HostInfo>> controller;
    nsd.Discovery? discovery;
    Timer? timer;
    var stopped = false;

    Future<void> stop() async {
      if (stopped) return;
      stopped = true;
      timer?.cancel();
      final d = discovery;
      if (d != null) {
        try {
          await nsd.stopDiscovery(d);
        } catch (_) {}
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<List<HostInfo>>(
      onListen: () async {
        timer = Timer(timeout, stop);
        try {
          final d = await nsd.startDiscovery(
            trackpadServiceType,
            ipLookupType: nsd.IpLookupType.any,
          );
          if (stopped) {
            await nsd.stopDiscovery(d);
            return;
          }
          discovery = d;
          void emit() {
            if (controller.isClosed) return;
            final hosts = <String, HostInfo>{};
            for (final s in d.services) {
              final h = hostInfoFromService(s);
              if (h != null) hosts[h.id] = h;
            }
            controller.add(hosts.values.toList(growable: false));
          }

          d.addListener(emit);
          emit();
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
          await stop();
        }
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
