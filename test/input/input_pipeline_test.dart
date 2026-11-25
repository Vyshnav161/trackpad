import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackpad/gestures/gesture_sample.dart';
import 'package:trackpad/input/input_pipeline.dart';
import 'package:trackpad/protocol/input_event.dart';
import 'package:trackpad/storage/settings_store.dart';

GestureSample _one(double x, double y, int ms) =>
    GestureSample([Finger(1, x, y)], DateTime.fromMillisecondsSinceEpoch(ms));
GestureSample _none(int ms) =>
    GestureSample(const [], DateTime.fromMillisecondsSinceEpoch(ms));

void main() {
  test('applies current sensitivity to pointer moves without reconnecting',
      () async {
    final sent = <InputEvent>[];
    var settings = const AppSettings(sensitivity: 2.0);
    final p = InputPipeline(
      send: (e) async {
        sent.add(e);
        return true;
      },
      settings: () => settings,
    );
    p.onSample(_one(0, 0, 0));
    p.onSample(_one(10, 5, 10));
    await Future<void>.delayed(Duration.zero);
    expect(sent.last, const PointerMove(20, 10));

    settings = const AppSettings(sensitivity: 0.5);
    p.onSample(_one(20, 5, 20));
    await Future<void>.delayed(Duration.zero);
    expect(sent.last, const PointerMove(5, 0));
  });

  test('scales drag moves and sends button down/up around them', () async {
    final sent = <InputEvent>[];
    final p = InputPipeline(
      send: (e) async {
        sent.add(e);
        return true;
      },
      settings: () => const AppSettings(sensitivity: 3.0),
    );
    // Tap, then touch again nearby and slide: drag.
    p.onSample(_one(0, 0, 0));
    p.onSample(_none(50));
    p.onSample(_one(0, 0, 100));
    p.onSample(_one(30, 0, 120));
    p.onSample(_one(40, 0, 140));
    p.onSample(_none(160));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sent.whereType<ButtonAction>().map((e) => e.action),
        [ButtonState.down, ButtonState.up]);
    final dx = sent.whereType<PointerMove>().fold<double>(0, (a, e) => a + e.dx);
    expect(dx, 40 * 3.0);
  });

  test('does not throttle: every sample is sent when the link is fast',
      () async {
    final sent = <InputEvent>[];
    final p = InputPipeline(
      send: (e) async {
        sent.add(e);
        return true;
      },
      settings: () => const AppSettings(),
    );
    p.onSample(_one(0, 0, 0));
    for (var i = 1; i <= 120; i++) {
      p.onSample(_one(i.toDouble(), 0, i * 8));
      await Future<void>.delayed(Duration.zero);
    }
    expect(sent.whereType<PointerMove>().length, 120);
  });

  test('coalesces while a send is in flight without losing displacement',
      () async {
    final sent = <InputEvent>[];
    final gate = Completer<bool>();
    var first = true;
    final p = InputPipeline(
      send: (e) {
        sent.add(e);
        if (first) {
          first = false;
          return gate.future;
        }
        return Future.value(true);
      },
      settings: () => const AppSettings(),
    );
    p.onSample(_one(0, 0, 0));
    for (var i = 1; i <= 10; i++) {
      p.onSample(_one(i.toDouble(), 0, i * 8));
    }
    gate.complete(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final total = sent.whereType<PointerMove>().fold<double>(0, (a, e) => a + e.dx);
    expect(total, 10);
    expect(sent.length, 2);
  });

  test('tap-to-click setting changes take effect immediately', () async {
    final sent = <InputEvent>[];
    var settings = const AppSettings(tapToClick: false);
    final p = InputPipeline(
      send: (e) async {
        sent.add(e);
        return true;
      },
      settings: () => settings,
    );
    p.onSample(_one(0, 0, 0));
    p.onSample(_none(50));
    expect(sent.whereType<ClickAction>(), isEmpty);

    settings = const AppSettings(tapToClick: true);
    p.onSample(_one(0, 0, 1000));
    p.onSample(_none(1050));
    await Future<void>.delayed(Duration.zero);
    expect(sent.whereType<ClickAction>().length, 1);
  });

  test('sendAppSwitch sends an unscaled AppSwitchEvent after pending moves',
      () async {
    final sent = <InputEvent>[];
    final p = InputPipeline(
      send: (e) async {
        sent.add(e);
        return true;
      },
      settings: () => const AppSettings(sensitivity: 3.0),
    );
    p.sendAppSwitch();
    await Future<void>.delayed(Duration.zero);
    expect(sent, [const AppSwitchEvent()]);
  });
}
