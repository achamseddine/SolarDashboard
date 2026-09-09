import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/dashboard/dashboard_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('dashboard renders KPIs, charts, regions and attention lists from a synced demo fleet', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 24);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const DashboardScreen()));
    await TestEnv.settle(tester);

    expect(find.textContaining('School solar fleet'), findsOneWidget);
    expect(find.text('Schools'), findsWidgets);
    expect(find.text('Generation now'), findsOneWidget);
    expect(find.text('Active alarms'), findsOneWidget);
    expect(find.text('Plant status'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ListView builds lazily: scroll through the page and check the lower cards.
    final list = find.byType(ListView).first;
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      for (final label in ['Governorates', 'Offline / stale', 'Top 10 by 7-day yield', 'Battery health', 'Alarms', 'Environmental impact']) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(['Governorates', 'Offline / stale', 'Top 10 by 7-day yield', 'Battery health', 'Alarms', 'Environmental impact']));
  });

  testWidgets('dashboard shows an empty state before the first sync', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create(schools: 5, sync: false));
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(env.wrap(const DashboardScreen()));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.textContaining('No schools yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
