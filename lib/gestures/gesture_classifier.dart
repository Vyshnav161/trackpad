/// Gesture Recognizer: turns raw touch samples into gesture events.
/// Plain Dart: no Flutter dependencies.
library;

import 'dart:math' as math;

import '../protocol/input_event.dart';
import 'gesture_event.dart';
import 'gesture_sample.dart';

/// Tunable thresholds.
class GestureConfig {
  const GestureConfig({
    this.tapMaxDuration = const Duration(milliseconds: 250),
    this.tapSlop = 10.0,
    this.doubleTapWindow = const Duration(milliseconds: 300),
    this.doubleTapSlop = 40.0,
    this.appSwitchThreshold = 60.0,
  });

  /// Max touch duration (first down to last up) for a tap.
  final Duration tapMaxDuration;

  /// Max travel from the touch start for a tap, and the travel at which a
  /// second touch following a tap turns into a drag.
  final double tapSlop;

  /// Max time between a tap's lift and the next touch-down for a
  /// double-tap / tap-hold-drag.
  final Duration doubleTapWindow;

  /// Max distance between the two taps of a double-tap.
  final double doubleTapSlop;

  /// Horizontal three-finger travel that triggers one app switch.
  final double appSwitchThreshold;
}

/// Classifies a stream of [GestureSample]s.
///
/// Use [classify] for a pure whole-sequence function, or feed samples one by
/// one to [process] (each instance holds only the state of its own stream).
///
/// Click semantics: a tap emits `ClickAction(left, 1)` immediately (no wait
/// for a possible second tap, since the sample stream has no timer). A
/// second tap within the double-tap thresholds then emits
/// `ClickAction(left, 2)`, i.e. the second click of the pair.
///
/// Two-finger movement always emits `ScrollEvent` (sign inverted when
/// [naturalScrolling]).
/// Three-finger horizontal travel past `appSwitchThreshold` emits one
/// `AppSwitchEvent` per touch. Dedicated buttons use [pressButton] and
/// [releaseButton].
class GestureClassifier {
  GestureClassifier({
    this.tapToClick = true,
    this.naturalScrolling = false,
    this.config = const GestureConfig(),
  });

  /// When false, taps never produce clicks (and so no double-tap/drag).
  final bool tapToClick;

  /// When true, scroll deltas are sign-inverted.
  final bool naturalScrolling;
  final GestureConfig config;

  /// Pure function of the samples and settings.
  static List<GestureEvent> classify(
    Iterable<GestureSample> samples, {
    bool tapToClick = true,
    bool naturalScrolling = false,
    GestureConfig config = const GestureConfig(),
  }) {
    final c = GestureClassifier(
      tapToClick: tapToClick,
      naturalScrolling: naturalScrolling,
      config: config,
    );
    return [for (final s in samples) ...c.process(s)];
  }

  // --- per-stream state ---
  bool _touching = false;
  DateTime _startTime = DateTime.fromMillisecondsSinceEpoch(0);
  math.Point<double> _start = const math.Point(0, 0);
  math.Point<double> _last = const math.Point(0, 0);
  int _count = 0;
  int _maxFingers = 0;
  bool _multi = false; // more than one finger was down at some point
  bool _dragCandidate = false; // touch began shortly after a nearby tap
  bool _dragging = false;
  double _travel = 0; // max centroid distance from start
  double _swipeX = 0; // accumulated three-finger horizontal travel
  double _swipeY = 0; // accumulated three-finger vertical travel
  bool _appSwitched = false;

  DateTime? _lastTapTime;
  math.Point<double>? _lastTapPos;

  /// Consumes one sample and returns the events it produces.
  List<GestureEvent> process(GestureSample sample) {
    final n = sample.fingers.length;
    if (n == 0) {
      return _touching ? _onAllLifted(sample.timestamp) : const [];
    }
    final c = _centroid(sample.fingers);

    if (!_touching) {
      _beginTouch(c, n, sample.timestamp);
      return const [];
    }

    if (n != _count) {
      // Finger added/removed: re-anchor so no spurious delta is produced.
      final out = <GestureEvent>[];
      if (n > _maxFingers) _maxFingers = n;
      if (n > 1) {
        _multi = true;
        if (_dragging) {
          _dragging = false;
          out.add(const DragEnd());
        }
      }
      _count = n;
      _last = c;
      _swipeX = 0;
      _swipeY = 0;
      return out;
    }

    _travel = math.max(_travel, _dist(c, _start));
    final dx = c.x - _last.x;
    final dy = c.y - _last.y;
    final out = <GestureEvent>[];

    if (_multi) {
      out.addAll(_onMultiFingerMove(dx, dy, n));
    } else if (_dragging) {
      if (dx != 0 || dy != 0) out.add(DragMove(dx, dy));
    } else if (_dragCandidate) {
      if (_travel > config.tapSlop) {
        _dragging = true;
        out
          ..add(const DragStart())
          ..add(DragMove(c.x - _start.x, c.y - _start.y));
      }
    } else if (dx != 0 || dy != 0) {
      out.add(InputGestureEvent(PointerMove(dx, dy)));
    }
    _last = c;
    return out;
  }

  /// Dedicated button control pressed.
  List<GestureEvent> pressButton(MouseButton button) => [
    InputGestureEvent(ButtonAction(button, ButtonState.down)),
  ];

  /// Dedicated button control released.
  List<GestureEvent> releaseButton(MouseButton button) => [
    InputGestureEvent(ButtonAction(button, ButtonState.up)),
  ];

  void _beginTouch(math.Point<double> c, int n, DateTime t) {
    _touching = true;
    _startTime = t;
    _start = c;
    _last = c;
    _count = n;
    _maxFingers = n;
    _multi = n > 1;
    _dragging = false;
    _travel = 0;
    _swipeX = 0;
    _swipeY = 0;
    _appSwitched = false;
    final tapTime = _lastTapTime;
    final tapPos = _lastTapPos;
    _dragCandidate =
        tapToClick &&
        n == 1 &&
        tapTime != null &&
        tapPos != null &&
        t.difference(tapTime) <= config.doubleTapWindow &&
        _dist(c, tapPos) <= config.doubleTapSlop;
  }

  List<GestureEvent> _onMultiFingerMove(double dx, double dy, int fingers) {
    if (fingers == 2) {
      if (dx == 0 && dy == 0) return const [];
      final sign = naturalScrolling ? -1.0 : 1.0;
      return [InputGestureEvent(ScrollEvent(sign * dx, sign * dy))];
    }
    if (fingers == 3 && !_appSwitched) {
      // Travel is accumulated since the third finger landed. Comparing with
      // the first touch point would count the vertical stagger of fingers
      // that land one at a time as vertical travel and reject the swipe.
      _swipeX += dx;
      _swipeY += dy;
      if (_swipeX.abs() >= config.appSwitchThreshold &&
          _swipeX.abs() > _swipeY.abs()) {
        _appSwitched = true;
        return const [InputGestureEvent(AppSwitchEvent())];
      }
    }
    return const [];
  }

  List<GestureEvent> _onAllLifted(DateTime t) {
    final out = <GestureEvent>[];
    final isTap =
        _travel <= config.tapSlop &&
        t.difference(_startTime) <= config.tapMaxDuration;

    if (_dragging) {
      out.add(const DragEnd());
      _clearTap();
    } else if (!_multi) {
      if (isTap && tapToClick) {
        if (_dragCandidate) {
          out.add(const InputGestureEvent(ClickAction(MouseButton.left, 2)));
          _clearTap();
        } else {
          out.add(const InputGestureEvent(ClickAction(MouseButton.left, 1)));
          _lastTapTime = t;
          _lastTapPos = _start;
        }
      } else {
        _clearTap();
      }
    } else {
      if (_maxFingers == 2 && isTap && tapToClick) {
        out.add(const InputGestureEvent(ClickAction(MouseButton.right, 1)));
      }
      _clearTap();
    }

    _touching = false;
    _count = 0;
    _maxFingers = 0;
    _multi = false;
    _dragCandidate = false;
    _dragging = false;
    return out;
  }

  void _clearTap() {
    _lastTapTime = null;
    _lastTapPos = null;
  }

  static math.Point<double> _centroid(List<Finger> fs) {
    var x = 0.0, y = 0.0;
    for (final f in fs) {
      x += f.x;
      y += f.y;
    }
    return math.Point(x / fs.length, y / fs.length);
  }

  static double _dist(math.Point<double> a, math.Point<double> b) =>
      a.distanceTo(b);
}
