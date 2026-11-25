import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'host_info.dart';

/// Persists [PairedHost]s in secure storage, one entry per host id.
class PairedHostStore {
  PairedHostStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'paired_host.';

  final FlutterSecureStorage _storage;

  String _key(String hostId) => '$_prefix$hostId';

  /// Adds or replaces the entry for [host.hostInfo.id].
  Future<void> add(PairedHost host) => _storage.write(
    key: _key(host.hostInfo.id),
    value: jsonEncode(host.toJson()),
  );

  /// Returns the paired host with [hostId], or null if not found.
  Future<PairedHost?> lookup(String hostId) async {
    final raw = await _storage.read(key: _key(hostId));
    return raw == null ? null : _decode(raw);
  }

  /// All paired hosts, ordered by pairing time.
  Future<List<PairedHost>> list() async {
    final all = await _storage.readAll();
    final hosts = <PairedHost>[];
    for (final e in all.entries) {
      if (!e.key.startsWith(_prefix)) continue;
      final host = _decode(e.value);
      if (host != null) hosts.add(host);
    }
    hosts.sort((a, b) => a.pairedAt.compareTo(b.pairedAt));
    return hosts;
  }

  /// Removes only the entry for [hostId]; other hosts are untouched.
  Future<void> remove(String hostId) => _storage.delete(key: _key(hostId));

  PairedHost? _decode(String raw) {
    try {
      return PairedHost.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null; // corrupt entry is treated as absent
    }
  }
}
