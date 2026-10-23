import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uw_ece475_542_t9_app/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('splash → connect → home, demo wearable runs a set', (
    tester,
  ) async {
    await tester.pumpWidget(const FatigueCoachApp());
    expect(find.text('Fatigue Coach'), findsOneWidget);

    // Splash plays, then fades to the connect page.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Connect your wearable'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.text('No hardware? Try the demo wearable'));
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);

    // The sensor check shows the IMU, rep counter and EMG, and EMG
    // snapshots arrive.
    expect(find.text('Gyro (°/s)'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('EMG (mV)'), findsOneWidget);
    expect(find.text('rms –'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('rms –'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Ready for some curls?'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);

    await tester.tap(find.text('Start a set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();

    // Demo curls take ~2.2 s each; give it time for a couple of reps.
    expect(find.text('0'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('0'), findsNothing);
    expect(find.text('Last rep range'), findsOneWidget);
    expect(find.textContaining('°'), findsOneWidget);
    await tester.tap(find.text('End set'));
    await tester.pumpAndSettle();

    // The set shows on Home and in History.
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('See all'), 200);
    expect(find.text('No sets yet'), findsNothing);
    await tester.tap(find.byIcon(Icons.insights));
    await tester.pumpAndSettle();
    expect(find.text('Reps per set'), findsOneWidget);

    // Disconnect from the device page so the demo's timers stop.
    await tester.tap(find.text('Connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('skip connecting goes straight to home', (tester) async {
    await tester.pumpWidget(const FatigueCoachApp());
    await tester.tapAt(const Offset(20, 20)); // a tap skips the splash
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('No wearable'), findsOneWidget);
    expect(find.text('Connect to start'), findsOneWidget);
  });
}
