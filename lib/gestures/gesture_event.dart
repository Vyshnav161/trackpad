/// Output events of the Gesture Recognizer.
library;

import '../protocol/input_event.dart';

/// Sealed set of events emitted by `GestureClassifier`.
sealed class GestureEvent {
  const GestureEvent();

  /// The protocol event to send for this gesture event.
  InputEvent toInputEvent();
}

/// A gesture event that is directly a protocol [InputEvent]
/// (PointerMove, ClickAction, ButtonAction, ScrollEvent, ZoomEvent, ...).
final class InputGestureEvent extends GestureEvent {
  final InputEvent event;
  const InputGestureEvent(this.event);

  @override
  InputEvent toInputEvent() => event;

  @override
  bool operator ==(Object other) =>
      other is InputGestureEvent && other.event == event;
  @override
  int get hashCode => event.hashCode;
  @override
  String toString() => 'InputGestureEvent($event)';
}

/// Tap-then-hold-and-slide began: left button goes down.
final class DragStart extends GestureEvent {
  const DragStart();
  @override
  InputEvent toInputEvent() =>
      const ButtonAction(MouseButton.left, ButtonState.down);
  @override
  bool operator ==(Object other) => other is DragStart;
  @override
  int get hashCode => 'DragStart'.hashCode;
  @override
  String toString() => 'DragStart';
}

/// Finger moved while dragging (raw touch delta).
final class DragMove extends GestureEvent {
  final double dx;
  final double dy;
  const DragMove(this.dx, this.dy);
  @override
  InputEvent toInputEvent() => PointerMove(dx, dy);
  @override
  bool operator ==(Object other) =>
      other is DragMove && other.dx == dx && other.dy == dy;
  @override
  int get hashCode => Object.hash('DragMove', dx, dy);
  @override
  String toString() => 'DragMove($dx, $dy)';
}

/// Finger lifted during a drag: left button goes up.
final class DragEnd extends GestureEvent {
  const DragEnd();
  @override
  InputEvent toInputEvent() =>
      const ButtonAction(MouseButton.left, ButtonState.up);
  @override
  bool operator ==(Object other) => other is DragEnd;
  @override
  int get hashCode => 'DragEnd'.hashCode;
  @override
  String toString() => 'DragEnd';
}
