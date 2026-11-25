/// Connects gesture and keyboard recognizers to the transport.
///
/// * Applies the *current* Sensitivity to pointer deltas (PointerMove and
///   DragMove) at the moment each touch sample is processed, so changes in
///   settings take effect without reconnecting (Requirements 5.3, 5.5).
/// * Never throttles pointer movement: every touch sample is forwarded as
///   soon as the previous send finished. While a send is in flight, further
///   deltas are summed and sent as one event right after, so the send rate is
///   bounded only by the link, far above 60 events/s (Requirement 5.3).
/// * Re-reads tap-to-click and natural-scrolling from the settings before
///   every sample (Requirement 12.3).
///
/// Plain Dart: no Flutter dependencies.
library;

import '../gestures/gesture_classifier.dart';
import '../gestures/gesture_event.dart';
import '../gestures/gesture_sample.dart';
import '../protocol/input_event.dart';
import '../storage/settings_store.dart';

class InputPipeline {
  InputPipeline({required this.send, required this.settings}) {
    _classifier = _newClassifier();
  }

  final Future<bool> Function(InputEvent event) send;
  final AppSettings Function() settings;
  AppSettings _settings() => settings();

  late GestureClassifier _classifier;
  double _pendingDx = 0;
  double _pendingDy = 0;
  bool _busy = false;

  GestureClassifier _newClassifier() {
    final s = _settings();
    return GestureClassifier(
      tapToClick: s.tapToClick,
      naturalScrolling: s.naturalScrolling,
    );
  }

  /// Rebuilds the classifier if tap-to-click or natural scrolling changed.
  void _syncSettings() {
    final s = _settings();
    if (s.tapToClick != _classifier.tapToClick ||
        s.naturalScrolling != _classifier.naturalScrolling) {
      _classifier = _newClassifier();
    }
  }

  /// Drops gesture state and unsent movement (e.g. when the link goes away).
  void reset() {
    _classifier = _newClassifier();
    _pendingDx = 0;
    _pendingDy = 0;
  }

  /// A touch snapshot from the trackpad surface.
  void onSample(GestureSample sample) {
    _syncSettings();
    for (final e in _classifier.process(sample)) {
      _handleGesture(e);
    }
  }

  /// Dedicated left/right button press (down) or release (up).
  void onButton(MouseButton button, ButtonState state) {
    _syncSettings();
    final events = state == ButtonState.down
        ? _classifier.pressButton(button)
        : _classifier.releaseButton(button);
    for (final e in events) {
      _handleGesture(e);
    }
  }

  /// App-switch button tap: same event as the three-finger swipe.
  /// Not sensitivity-scaled.
  void sendAppSwitch() => _sendOrdered(const AppSwitchEvent());

  /// Key actions from the keyboard recognizer, sent in order.
  void onKeyActions(List<KeyAction> actions) {
    for (final a in actions) {
      _sendOrdered(a);
    }
  }

  void _handleGesture(GestureEvent e) {
    switch (e) {
      case DragMove(:final dx, :final dy):
        _addMove(dx, dy);
      case InputGestureEvent(event: PointerMove(:final dx, :final dy)):
        _addMove(dx, dy);
      default:
        _sendOrdered(e.toInputEvent());
    }
  }

  void _addMove(double dx, double dy) {
    final k = _settings().sensitivity;
    _pendingDx += dx * k;
    _pendingDy += dy * k;
    _pump();
  }

  void _pump() {
    if (_busy || (_pendingDx == 0 && _pendingDy == 0)) return;
    final move = PointerMove(_pendingDx, _pendingDy);
    _pendingDx = 0;
    _pendingDy = 0;
    _busy = true;
    _safeSend(move).whenComplete(() {
      _busy = false;
      _pump();
    });
  }

  /// Sends [event] after any accumulated movement, preserving order.
  void _sendOrdered(InputEvent event) {
    if (_pendingDx != 0 || _pendingDy != 0) {
      final move = PointerMove(_pendingDx, _pendingDy);
      _pendingDx = 0;
      _pendingDy = 0;
      _safeSend(move);
    }
    _safeSend(event);
  }

  Future<void> _safeSend(InputEvent e) async {
    try {
      await send(e);
    } catch (_) {
      // The transport reports link loss through its state stream.
    }
  }
}
