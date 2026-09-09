import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/alarms/alarms_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('alarm centre lists active alarms and acknowledges one', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 30);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const AlarmsScreen()));
    await TestEnv.settle(tester);
    expect(find.text('Alarms'), findsWidgets);
    expect(find.text('Median time to recovery'), findsOneWidget);
    expect(find.textContaining('Acknowledge all'), findsOneWidget);
    expect(find.text('Active'), findsWidgets);
    expect(tester.takeException(), isNull);

    final ackButtons = find.byTooltip('Acknowledge');
    expect(ackButtons, findsWidgets);
    final before = ackButtons.evaluate().length;
    await tester.tap(ackButtons.first);
    await TestEnv.settle(tester, rounds: 2);
    expect(find.byTooltip('Acknowledge').evaluate().length, lessThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('alarm centre can be scoped to one plant', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 10);
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(env.wrap(AlarmsScreen(initialStationId: env.api.stationIds.first)));
    await TestEnv.settle(tester);
    expect(find.textContaining('Alarms ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
