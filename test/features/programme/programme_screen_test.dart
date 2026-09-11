import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/programme/programme_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('programme dashboard renders header, KPIs and every card', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const ProgrammeScreen()));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('School solarisation programme'), findsOneWidget);
    expect(find.textContaining('public schools solarised'), findsOneWidget);
    expect(find.textContaining('dataset from MEHE/UNICEF workbooks'), findsOneWidget);
    expect(find.text('Public schools'), findsOneWidget);
    expect(find.text('Solarised'), findsWidgets);
    expect(find.text('Solar pipeline'), findsOneWidget);
    expect(find.text('Installed capacity'), findsOneWidget);
    expect(find.text('Investment'), findsOneWidget);
    expect(find.text('Students benefiting'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ListView builds lazily: scroll through the page and collect the card titles.
    final list = find.byType(ListView).first;
    final wanted = [
      'Coverage by governorate',
      'Solar status',
      'Funding',
      'Energy: audited load vs solar',
      'Solarised but not monitored',
      'Plants down at schools without connectivity',
      'Undersized systems',
      'Next candidates for solarisation',
      'Measured vs audited',
      'Education indicators',
      'Plant ↔ school links',
    ];
    final seen = <String>{};
    for (var i = 0; i < 14; i++) {
      for (final label in wanted) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(wanted));
    expect(find.textContaining('Education'), findsWidgets);
    expect(find.textContaining('links'), findsWidgets);
    expect(find.textContaining('correlation is not causation'), findsOneWidget);
    await TestEnv.drain(tester);
  });

  testWidgets('programme dashboard survives narrow tablets', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 12);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const ProgrammeScreen(), size: const Size(900, 800)));
    await TestEnv.settle(tester, rounds: 4);
    expect(find.text('School solarisation programme'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    for (var i = 0; i < 16; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    await TestEnv.drain(tester);
  });

  testWidgets('programme dashboard renders without any synced plant', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create(sync: false));
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const ProgrammeScreen()));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('School solarisation programme'), findsOneWidget);
    expect(find.textContaining('0 monitored plants'), findsOneWidget);
    expect(find.text('Monitored plants'), findsOneWidget);
    expect(find.text('No plant synced yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Every card must render its empty state without a single plant.
    final list = find.byType(ListView).first;
    final wanted = ['No monitored plant yet', 'Education indicators', 'Plant ↔ school links', 'No plant synced yet', 'Nothing to link yet'];
    final seen = <String>{};
    for (var i = 0; i < 14; i++) {
      for (final label in wanted) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(wanted));
    await TestEnv.drain(tester);
  });
}
