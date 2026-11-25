import 'package:flutter/material.dart';

import '../gestures/gesture_sample.dart';
import '../protocol/input_event.dart';
import '../storage/host_info.dart';
import '../transport/transport_manager.dart';

/// Trackpad_Surface screen (Requirements 5.1, 6.5, 6.6, 7.1, 11.1, 11.2).
///
/// Dependencies are injected so the screen is testable without a live
/// connection. Raw pointer events become [GestureSample]s for the gesture
/// classifier; the dedicated left/right buttons emit press/release.
class TrackpadScreen extends StatefulWidget {
  const TrackpadScreen({
    super.key,
    required this.status,
    required this.onGestureSample,
    required this.onButton,
    required this.onDisconnect,
    this.keyboardPanel,
    this.onAppSwitch,
    this.onOpenSettings,
    this.clock = DateTime.now,
  });

  /// Opens the settings screen; the action is hidden when null.
  final VoidCallback? onOpenSettings;

  /// Connected host name and Transport (Requirement 11.1).
  final ConnectionStatus status;

  /// Receives every touch snapshot from the surface.
  final void Function(GestureSample sample) onGestureSample;

  /// Dedicated button press (down) / release (up) (Requirement 6.6).
  final void Function(MouseButton button, ButtonState state) onButton;

  /// User-requested disconnect (Requirement 11.2).
  final VoidCallback onDisconnect;

  /// Tap on the app-switch button (same as the three-finger swipe).
  final VoidCallback? onAppSwitch;

  /// Optional slot for the keyboard panel.
  final Widget? keyboardPanel;

  /// Timestamp source for samples (injectable for tests).
  final DateTime Function() clock;

  @override
  State<TrackpadScreen> createState() => _TrackpadScreenState();
}

class _TrackpadScreenState extends State<TrackpadScreen> {
  final Map<int, Offset> _active = <int, Offset>{};

  void _emit() {
    final fingers = <Finger>[
      for (final e in _active.entries) Finger(e.key, e.value.dx, e.value.dy),
    ];
    widget.onGestureSample(GestureSample(fingers, widget.clock()));
  }

  void _down(PointerDownEvent e) {
    _active[e.pointer] = e.localPosition;
    _emit();
  }

  void _move(PointerMoveEvent e) {
    if (!_active.containsKey(e.pointer)) return;
    _active[e.pointer] = e.localPosition;
    _emit();
  }

  void _end(PointerEvent e) {
    if (_active.remove(e.pointer) == null) return;
    _emit();
  }

  static String _transportLabel(TransportKind? t) => switch (t) {
    TransportKind.wifi => 'Wi-Fi',
    TransportKind.bluetooth => 'Bluetooth',
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final banner = status.connected
        ? 'Connected to ${status.hostName} via ${_transportLabel(status.transport)}'
        : 'Disconnected';

    return Scaffold(
      appBar: AppBar(
        title: Text(banner, key: const Key('connectionBanner')),
        actions: [
          if (widget.onOpenSettings != null)
            IconButton(
              key: const Key('settingsButton'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: widget.onOpenSettings,
            ),
          IconButton(
            key: const Key('disconnectButton'),
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
            onPressed: widget.onDisconnect,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Listener(
                key: const Key('touchSurface'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _end,
                onPointerCancel: _end,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  Expanded(
                    child: _ButtonControl(
                      key: const Key('leftButton'),
                      label: 'Left',
                      onChanged: (s) => widget.onButton(MouseButton.left, s),
                    ),
                  ),
                  if (widget.onAppSwitch != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: FilledButton.tonal(
                          key: const Key('appSwitchButton'),
                          onPressed: widget.onAppSwitch,
                          child: const Icon(Icons.swap_horiz),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _ButtonControl(
                      key: const Key('rightButton'),
                      label: 'Right',
                      onChanged: (s) => widget.onButton(MouseButton.right, s),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.keyboardPanel != null) widget.keyboardPanel!,
          ],
        ),
      ),
    );
  }
}

/// A button that reports down on press and up on release/cancel.
class _ButtonControl extends StatefulWidget {
  const _ButtonControl({
    super.key,
    required this.label,
    required this.onChanged,
  });

  final String label;
  final void Function(ButtonState state) onChanged;

  @override
  State<_ButtonControl> createState() => _ButtonControlState();
}

class _ButtonControlState extends State<_ButtonControl> {
  int? _pointer;

  void _release() {
    if (_pointer == null) return;
    setState(() => _pointer = null);
    widget.onChanged(ButtonState.up);
  }

  @override
  void dispose() {
    // Never leave a button held if the control goes away mid-press.
    if (_pointer != null) widget.onChanged(ButtonState.up);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pressed = _pointer != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        setState(() => _pointer = e.pointer);
        widget.onChanged(ButtonState.down);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _release();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _release();
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? scheme.primary : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: pressed ? scheme.onPrimary : scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
