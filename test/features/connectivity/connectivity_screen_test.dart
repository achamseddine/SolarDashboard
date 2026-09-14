import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/common/widgets.dart';
import 'package:unicef_solar_monitor/features/connectivity/connectivity_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('connectivity dashboard renders the header, the KPIs and every card', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const ConnectivityScreen(), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 5);

    expect(find.text('Internet connectivity'), findsOneWidget);
    expect(find.textContaining('public schools on the roll-out'), findsOneWidget);
    expect(find.textContaining('students reached'), findsOneWidget);
    expect(find.text('Connected schools'), findsOneWidget);
    expect(find.text('Schools without internet'), findsOneWidget);
    expect(find.text('Students reached'), findsOneWidget);
    expect(find.text('Monitored plants connected'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ListView children build lazily: scroll through the page and collect the
    // card titles as they come into view.
    final list = find.byType(ListView).first;
    final wanted = [
      'Connectivity by governorate',
      'Solar and internet',
      'Districts with the largest gap',
      'Best served districts',
      'Plants without a data path',
      'membership list of',
    ];
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      for (final label in wanted) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(wanted));
    await TestEnv.drain(tester);
  });

  testWidgets('connectivity dashboard survives an empty fleet', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create(sync: false));
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const ConnectivityScreen(), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 5);

    expect(find.text('Internet connectivity'), findsOneWidget);
    final monitored = tester.widget<KpiTile>(find.byWidgetPredicate((w) => w is KpiTile && w.label == 'Monitored plants connected'));
    expect(monitored.value, '0');
    expect(monitored.hint, 'No plant synced yet');
    expect(tester.takeException(), isNull);

    // Every card still builds without a single plant.
    final list = find.byType(ListView).first;
    final seen = <String>{};
    const wanted = ['Connectivity by governorate', 'Solar and internet', 'Plants without a data path', 'No monitored plant synced yet'];
    for (var i = 0; i < 12; i++) {
      for (final label in wanted) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(wanted));
    await TestEnv.drain(tester);
  });
}
