import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackpad/transport/transport_manager.dart';
import 'package:trackpad/ui/trackpad_screen.dart';

void main() {
  testWidgets('app-switch button invokes onAppSwitch once per tap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: TrackpadScreen(
        status: const ConnectionStatus(connected: true, hostName: 'PC'),
        onGestureSample: (_) {},
        onButton: (_, _) {},
        onDisconnect: () {},
        onAppSwitch: () => taps++,
      ),
    ));
    expect(find.byKey(const Key('leftButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('appSwitchButton')));
    await tester.pump();
    expect(taps, 1);
  });
}
