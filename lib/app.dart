/// App wiring: navigation (host list -> pairing -> trackpad, settings), the
/// connected-state display, input pipeline and the background lifecycle hook
/// (Requirements 5.3, 5.5, 8.1, 8.2, 11.6, 12.3).
library;

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import 'input/input_pipeline.dart';
import 'keyboard/keyboard_recognizer.dart';
import 'storage/host_info.dart';
import 'storage/settings_store.dart';
import 'transport/transport_client.dart';
import 'transport/transport_manager.dart';
import 'transport/wifi_transport_client.dart' show defaultAgentPort;
import 'ui/host_list_screen.dart';
import 'ui/keyboard_panel.dart';
import 'ui/pairing_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/trackpad_screen.dart';

/// Everything the app needs from the outside world (injectable for tests).
class AppDependencies {
  AppDependencies({
    required this.manager,
    required this.settings,
    required this.discoveries,
    required this.permissionRequester,
    this.onTurnOnBluetooth,
  });

  final TransportManager manager;
  final SettingsStore settings;
  final List<HostDiscovery> discoveries;
  final PermissionRequester permissionRequester;

  /// Asks the system to enable Bluetooth; null hides the button.
  final Future<void> Function()? onTurnOnBluetooth;
}

/// Builds the host for a manually entered IP address, using the default
/// agent port. The agent-reported OS replaces [HostOS.macOS] after the
/// handshake (Requirement 9.1).
HostInfo hostForManualIp(String ip) {
  final text = ip.trim();
  final address = text.contains(':')
      ? '[$text]:$defaultAgentPort'
      : '$text:$defaultAgentPort';
  return HostInfo(
    id: text,
    name: text,
    os: HostOS.macOS,
    transport: TransportKind.wifi,
    address: address,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return _AppRoot(dependencies: dependencies);
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  final KeyboardRecognizer _keyboard = KeyboardRecognizer();

  late final TransportManager _manager = widget.dependencies.manager;
  late final SettingsStore _settings = widget.dependencies.settings;
  late final ValueNotifier<ConnectionState> _state =
      ValueNotifier<ConnectionState>(_manager.state);
  late final InputPipeline _pipeline = InputPipeline(
    send: _manager.send,
    settings: () => _settings.settings,
  );
  StreamSubscription<ConnectionState>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _manager.states.listen(_onState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _state.dispose();
    super.dispose();
  }

  void _onState(ConnectionState s) {
    final previous = _state.value;
    _state.value = s;
    if (s is! Authenticated) {
      // Drop partial gestures and toggled modifiers when the link goes away.
      _pipeline.reset();
      _keyboard.clearModifiers();
    }
    if (s is Disconnected && previous is! Disconnected) _announce(s);
  }

  void _announce(Disconnected s) {
    final message = switch (s.reason) {
      DisconnectReason.userRequested => null,
      DisconnectReason.connectionFailed =>
        (s.failure ?? ConnectionFailureReason.unknown).userMessage,
      DisconnectReason.linkLost => 'The connection to the computer was lost.',
      DisconnectReason.backgroundTimeout =>
        'Disconnected after the app was in the background for 60 seconds.',
      DisconnectReason.pairingRejected =>
        'Pairing was rejected by the computer.',
      DisconnectReason.protocolError =>
        'The computer sent an unexpected response.',
    };
    if (message == null) return;
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Requirement 11.6: report background/foreground to the manager, which
  /// closes the connection after 60 seconds in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _manager.appBackgrounded();
      case AppLifecycleState.resumed:
        _manager.appForegrounded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _openSettings() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(store: _settings)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trackpad',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ValueListenableBuilder<ConnectionState>(
        valueListenable: _state,
        builder: (context, state, _) => _page(state),
      ),
    );
  }

  Widget _page(ConnectionState state) {
    final deps = widget.dependencies;
    switch (state) {
      case Authenticated():
        return TrackpadScreen(
          key: const ValueKey('trackpad'),
          status: connectionStatusFor(state),
          onGestureSample: _pipeline.onSample,
          onButton: _pipeline.onButton,
          onAppSwitch: _pipeline.sendAppSwitch,
          onDisconnect: _manager.disconnect,
          onOpenSettings: _openSettings,
          keyboardPanel: KeyboardPanel(
            recognizer: _keyboard,
            platformKeyLabel: platformKeyLabelFor(state.host.os),
            onKeyActions: _pipeline.onKeyActions,
          ),
        );
      case AwaitingPairing():
        return PairingScreen(
          key: const ValueKey('pairing'),
          state: _state,
          onSubmit: _manager.submitPairingCode,
          onCancel: _manager.startDiscovery,
        );
      case Connecting(:final host):
        return _BusyScreen(
          key: const ValueKey('connecting'),
          message: 'Connecting to ${host.name}\u2026',
          onCancel: _manager.startDiscovery,
        );
      case Disconnected(reconnecting: true, :final host):
        return _BusyScreen(
          key: const ValueKey('reconnecting'),
          message:
              'Connection lost. Reconnecting to ${host?.name ?? 'computer'}\u2026',
          onCancel: _manager.startDiscovery,
        );
      case Discovering():
      case Disconnected():
        return HostListScreen(
          key: const ValueKey('hostList'),
          discoveries: deps.discoveries,
          permissionRequester: deps.permissionRequester,
          onTurnOnBluetooth: deps.onTurnOnBluetooth,
          onHostSelected: _manager.connect,
          onManualIp: (ip) => _manager.connect(hostForManualIp(ip)),
          onOpenSettings: _openSettings,
        );
    }
  }
}

class _BusyScreen extends StatelessWidget {
  const _BusyScreen({super.key, required this.message, required this.onCancel});

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, key: const Key('busyMessage')),
            const SizedBox(height: 16),
            TextButton(
              key: const Key('cancelButton'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
