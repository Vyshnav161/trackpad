import 'package:flutter_test/flutter_test.dart';
import 'package:trackpad/gestures/gesture_classifier.dart';
import 'package:trackpad/gestures/gesture_event.dart';
import 'package:trackpad/gestures/gesture_sample.dart';
import 'package:trackpad/protocol/input_event.dart';

final _t0 = DateTime.utc(2024);
GestureSample s(int ms, [List<Finger> f = const []]) =>
    GestureSample(f, _t0.add(Duration(milliseconds: ms)));
Finger f(double x, double y, [int id = 0]) => Finger(id, x, y);
InputGestureEvent click(MouseButton b, int n) =>
    InputGestureEvent(ClickAction(b, n));

void main() {
  test('single-finger moves emit raw deltas as PointerMove', () {
    final out = GestureClassifier.classify([
      s(0, [f(0, 0)]),
      s(10, [f(3, 4)]),
      s(20, [f(2, 6)]),
      s(30),
    ]);
    expect(out.take(2), [
      const InputGestureEvent(PointerMove(3, 4)),
      const InputGestureEvent(PointerMove(-1, 2)),
    ]);
  });

  test('one-finger tap is a left click; disabled suppresses it', () {
    final seq = [s(0, [f(5, 5)]), s(100, [f(5, 5)]), s(100)];
    expect(GestureClassifier.classify(seq), [click(MouseButton.left, 1)]);
    expect(GestureClassifier.classify(seq, tapToClick: false), isEmpty);
  });

  test('long press is not a tap', () {
    expect(
        GestureClassifier.classify([s(0, [f(0, 0)]), s(600)]), isEmpty);
  });

  test('two-finger tap is a right click', () {
    final seq = [
      s(0, [f(0, 0, 0), f(20, 0, 1)]),
      s(80),
    ];
    expect(GestureClassifier.classify(seq), [click(MouseButton.right, 1)]);
    expect(GestureClassifier.classify(seq, tapToClick: false), isEmpty);
  });

  test('two quick taps give click then double click', () {
    final out = GestureClassifier.classify([
      s(0, [f(0, 0)]),
      s(50),
      s(150, [f(2, 2)]),
      s(200),
    ]);
    expect(out, [click(MouseButton.left, 1), click(MouseButton.left, 2)]);
  });

  test('taps too far apart or too late are two single clicks', () {
    final far = GestureClassifier.classify([
      s(0, [f(0, 0)]), s(50),
      s(150, [f(200, 0)]), s(200),
    ]);
    expect(far, [click(MouseButton.left, 1), click(MouseButton.left, 1)]);
    final late = GestureClassifier.classify([
      s(0, [f(0, 0)]), s(50),
      s(800, [f(0, 0)]), s(850),
    ]);
    expect(late, [click(MouseButton.left, 1), click(MouseButton.left, 1)]);
  });

  test('tap then hold and slide is a drag until lift', () {
    final out = GestureClassifier.classify([
      s(0, [f(0, 0)]),
      s(50),
      s(100, [f(0, 0)]),
      s(200, [f(30, 0)]),
      s(250, [f(40, 5)]),
      s(300),
    ]);
    expect(out, [
      click(MouseButton.left, 1),
      const DragStart(),
      const DragMove(30, 0),
      const DragMove(10, 5),
      const DragEnd(),
    ]);
    expect(out.whereType<DragStart>().single.toInputEvent(),
        const ButtonAction(MouseButton.left, ButtonState.down));
  });

  test('tap-to-click disabled: no drag from tap-hold-slide', () {
    final out = GestureClassifier.classify([
      s(0, [f(0, 0)]), s(50),
      s(100, [f(0, 0)]), s(200, [f(30, 0)]), s(300),
    ], tapToClick: false);
    expect(out, [const InputGestureEvent(PointerMove(30, 0))]);
  });

  test('three-finger swipe with fingers landing one at a time app-switches',
      () {
    // Fingers land staggered vertically (first at y=0, others lower), so the
    // centroid sits far below the first touch point.
    final out = GestureClassifier.classify([
      s(0, [f(0, 0, 0)]),
      s(20, [f(0, 0, 0), f(40, 150, 1)]),
      s(40, [f(0, 0, 0), f(40, 150, 1), f(80, 200, 2)]),
      for (var i = 1; i <= 5; i++)
        s(40 + i * 10, [
          f(0.0 + i * 20, 0, 0),
          f(40.0 + i * 20, 150, 1),
          f(80.0 + i * 20, 200, 2),
        ]),
      s(200),
    ]);
    expect(out, [const InputGestureEvent(AppSwitchEvent())]);
  });

  test('mostly vertical three-finger travel does not app-switch', () {
    final out = GestureClassifier.classify([
      s(0, [f(0, 0, 0), f(40, 0, 1), f(80, 0, 2)]),
      for (var i = 1; i <= 5; i++)
        s(i * 10, [
          f(i * 10.0, i * 40.0, 0),
          f(40 + i * 10.0, i * 40.0, 1),
          f(80 + i * 10.0, i * 40.0, 2),
        ]),
      s(200),
    ]);
    expect(out.whereType<InputGestureEvent>().where((e) => e.event is AppSwitchEvent), isEmpty);
  });
}
