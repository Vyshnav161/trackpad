/// Host list screen: discovery, refresh, no-host message with manual IP entry,
/// permission requests and the Bluetooth-off prompt (Requirements 1.1-1.5, 3.3).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../storage/host_info.dart';
import '../transport/host_display.dart';
import '../transport/ip_validator.dart';
import '../transport/transport_client.dart';

/// Permissions needed for discovery (Requirement 1.5).
enum DiscoveryPermission {
  bluetoothScan,
  bluetoothConnect,
  nearbyWifiOrLocation,
}

extension DiscoveryPermissionExplanation on DiscoveryPermission {
  String get title => switch (this) {
    DiscoveryPermission.bluetoothScan => 'Bluetooth scan',
    DiscoveryPermission.bluetoothConnect => 'Bluetooth connect',
    DiscoveryPermission.nearbyWifiOrLocation => 'Nearby devices',
  };

  /// Why the permission is needed, shown to the user.
  String get explanation => switch (this) {
    DiscoveryPermission.bluetoothScan =>
      'Needed to find computers running the desktop app over Bluetooth.',
    DiscoveryPermission.bluetoothConnect =>
      'Needed to connect to a computer over Bluetooth.',
    DiscoveryPermission.nearbyWifiOrLocation =>
      'Needed to find computers running the desktop app on your Wi-Fi '
          'network.',
  };
}

/// Checks and requests the permissions required for discovery.
abstract class PermissionRequester {
  /// Permissions not currently granted.
  Future<Set<DiscoveryPermission>> missing();

  /// Requests [permissions]; returns those still not granted.
  Future<Set<DiscoveryPermission>> request(
    Set<DiscoveryPermission> permissions,
  );
}

/// [PermissionRequester] backed by the permission_handler plugin.
class PermissionHandlerRequester implements PermissionRequester {
  const PermissionHandlerRequester();

  Permission _map(DiscoveryPermission p) => switch (p) {
    DiscoveryPermission.bluetoothScan => Permission.bluetoothScan,
    DiscoveryPermission.bluetoothConnect => Permission.bluetoothConnect,
    DiscoveryPermission.nearbyWifiOrLocation => Permission.nearbyWifiDevices,
  };

  bool _ok(PermissionStatus s) => s.isGranted || s.isLimited;

  @override
  Future<Set<DiscoveryPermission>> missing() async {
    final result = <DiscoveryPermission>{};
    for (final p in DiscoveryPermission.values) {
      if (!_ok(await _map(p).status)) result.add(p);
    }
    return result;
  }

  @override
  Future<Set<DiscoveryPermission>> request(
    Set<DiscoveryPermission> permissions,
  ) async {
    final statuses = await permissions.map(_map).toList().request();
    return {
      for (final p in permissions)
        if (!_ok(statuses[_map(p)] ?? PermissionStatus.denied)) p,
    };
  }
}

class HostListScreen extends StatefulWidget {
  const HostListScreen({
    super.key,
    required this.discoveries,
    required this.onHostSelected,
    required this.onManualIp,
    required this.permissionRequester,
    this.onTurnOnBluetooth,
    this.onOpenSettings,
    this.noHostTimeout = const Duration(seconds: 10),
  });

  /// Opens the settings screen; the action is hidden when null.
  final VoidCallback? onOpenSettings;

  /// Discovery sources (Wi-Fi and Bluetooth).
  final List<HostDiscovery> discoveries;

  /// Called when the user taps a discovered Host.
  final void Function(HostInfo host) onHostSelected;

  /// Called with a validated IP address typed by the user.
  final void Function(String ipAddress) onManualIp;

  final PermissionRequester permissionRequester;

  /// Asks the system to enable Bluetooth. When null the prompt only tells the
  /// user to turn it on in system settings.
  final Future<void> Function()? onTurnOnBluetooth;

  /// How long to wait before showing the no-host message (Requirement 1.4).
  final Duration noHostTimeout;

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  final List<StreamSubscription<List<HostInfo>>> _subs = [];
  final Map<int, List<HostInfo>> _bySource = {};
  Timer? _noHostTimer;
  int _runId = 0;

  Set<DiscoveryPermission> _missing = {};
  bool _bluetoothOff = false;
  bool _scanning = false;
  bool _timedOut = false;

  List<HostInfo> get _hosts {
    final byId = <String, HostInfo>{};
    for (final list in _bySource.values) {
      for (final h in list) {
        byId['${h.transport.name}:${h.id}'] = h;
      }
    }
    return byId.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _runId++;
    _noHostTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Checks permissions, then starts discovery (also used for refresh).
  Future<void> _start() async {
    _stop();
    final run = _runId;
    setState(() {
      _bySource.clear();
      _bluetoothOff = false;
      _timedOut = false;
      _scanning = true;
    });

    final missing = await widget.permissionRequester.missing();
    if (!mounted || run != _runId) return;
    setState(() => _missing = missing);
    if (missing.isNotEmpty) {
      // Wait for the user to read the explanation and grant (Requirement 1.5).
      setState(() => _scanning = false);
      return;
    }

    _noHostTimer = Timer(widget.noHostTimeout, () {
      if (!mounted || run != _runId) return;
      setState(() {
        _timedOut = true;
        _scanning = false;
      });
    });

    var active = widget.discoveries.length;
    void sourceDone() {
      if (--active <= 0 && mounted && run == _runId) {
        setState(() => _scanning = false);
      }
    }

    for (var i = 0; i < widget.discoveries.length; i++) {
      final index = i;
      _subs.add(
        widget.discoveries[i]
            .discover(timeout: widget.noHostTimeout)
            .listen(
              (hosts) {
                if (!mounted || run != _runId) return;
                setState(() => _bySource[index] = hosts);
              },
              onError: (Object e) {
                if (!mounted || run != _runId) return;
                _handleDiscoveryError(e);
              },
              onDone: sourceDone,
            ),
      );
    }
    if (widget.discoveries.isEmpty) sourceDone();
  }

  void _handleDiscoveryError(Object error) {
    if (error is! ConnectionFailure) return;
    switch (error.reason) {
      case ConnectionFailureReason.bluetoothOff:
        setState(() => _bluetoothOff = true); // Requirement 3.3.
      case ConnectionFailureReason.permissionDenied:
        widget.permissionRequester.missing().then((m) {
          if (mounted) setState(() => _missing = m);
        });
      default:
        break;
    }
  }

  Future<void> _grantPermissions() async {
    final remaining = await widget.permissionRequester.request(_missing);
    if (!mounted) return;
    setState(() => _missing = remaining);
    if (remaining.isEmpty) _start();
  }

  Future<void> _turnOnBluetooth() async {
    await widget.onTurnOnBluetooth?.call();
    if (mounted) _start();
  }

  Future<void> _showManualEntry() async {
    final ip = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualIpDialog(),
    );
    if (ip != null) widget.onManualIp(ip);
  }

  @override
  Widget build(BuildContext context) {
    final hosts = _hosts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a computer'),
        actions: [
          if (widget.onOpenSettings != null)
            IconButton(
              key: const Key('settingsButton'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: widget.onOpenSettings,
            ),
          IconButton(
            tooltip: 'Enter IP address',
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: _showManualEntry,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _start,
          ),
        ],
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _start,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_missing.isNotEmpty) _permissionCard(),
            if (_bluetoothOff) _bluetoothCard(),
            for (final h in hosts) _hostTile(h),
            if (hosts.isEmpty && _timedOut && _missing.isEmpty)
              _noHostMessage(),
          ],
        ),
      ),
    );
  }

  Widget _hostTile(HostInfo host) {
    final d = toHostDisplay(host);
    final os = d.os == HostOS.macOS ? 'macOS' : 'Windows';
    final transport = d.transport == TransportKind.wifi ? 'Wi-Fi' : 'Bluetooth';
    return ListTile(
      key: ValueKey('host-${host.transport.name}-${host.id}'),
      leading: Icon(
        d.transport == TransportKind.wifi ? Icons.wifi : Icons.bluetooth,
      ),
      title: Text(d.name),
      subtitle: Text('$os \u00b7 $transport'),
      onTap: () => widget.onHostSelected(host),
    );
  }

  Widget _permissionCard() {
    return Card(
      key: const Key('permission-card'),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permissions needed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final p in DiscoveryPermission.values)
              if (_missing.contains(p))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${p.title}: ${p.explanation}'),
                ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _grantPermissions,
                child: const Text('Grant permissions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bluetoothCard() {
    return Card(
      key: const Key('bluetooth-off-card'),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bluetooth is turned off. Turn it on to find '
              'computers over Bluetooth.',
            ),
            if (widget.onTurnOnBluetooth != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _turnOnBluetooth,
                  child: const Text('Turn on Bluetooth'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noHostMessage() {
    return Padding(
      key: const Key('no-host-message'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'No computers found. Make sure the desktop app is running, or '
            'enter the computer\u2019s IP address.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _showManualEntry,
            child: const Text('Enter IP address'),
          ),
        ],
      ),
    );
  }
}

class _ManualIpDialog extends StatefulWidget {
  const _ManualIpDialog();

  @override
  State<_ManualIpDialog> createState() => _ManualIpDialogState();
}

class _ManualIpDialogState extends State<_ManualIpDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (!isValidIpAddress(text)) {
      setState(() => _error = 'Enter a valid IPv4 or IPv6 address.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter IP address'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: '192.168.1.20',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}
