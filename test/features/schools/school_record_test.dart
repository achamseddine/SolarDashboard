import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/schools/school_record_screen.dart';

import '../../helpers/test_env.dart';

/// Scrolls the record page and collects which of [wanted] ever appeared —
/// the ListView builds its children lazily, so off-screen cards only exist
/// once they scroll into view.
Future<Set<String>> _collect(WidgetTester tester, List<String> wanted, {int scrolls = 12}) async {
  final list = find.byType(ListView).first;
  final seen = <String>{};
  for (var i = 0; i < scrolls; i++) {
    for (final label in wanted) {
      if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
    }
    await tester.drag(list, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
  }
  return seen;
}

void main() {
  testWidgets('school record shows the full record of a connected, solarised, audited school', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolRecordScreen(cerd: 1), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 5);

    expect(find.text('Uruguay First Achrafieh Public School for Boys'), findsOneWidget);
    expect(find.textContaining('CERD 1 · Beirut'), findsOneWidget);
    expect(find.text('Internet connected'), findsOneWidget);
    expect(find.text('Students'), findsWidgets);
    expect(find.text('Audited load'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final seen = await _collect(tester, [
      'School record',
      'Internet connectivity',
      'membership list',
      'Solar programme',
      'KfW',
      'Arison',
      'Energy audit',
      'Equipment inventory',
      'Education indicators',
      'Morning shift attendance',
      'MEHE education dashboard',
    ]);
    expect(
      seen,
      containsAll(<String>[
        'School record',
        'Internet connectivity',
        'membership list',
        'Solar programme',
        'KfW',
        'Arison',
        'Energy audit',
        'Equipment inventory',
        'Education indicators',
        'Morning shift attendance',
      ]),
    );
    await TestEnv.drain(tester);
  });

  testWidgets('school record of a school with no solar system and no plant renders', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    late final int cerd;
    late final String name;
    await tester.runAsync(() async {
      final schools = await env.db.schools.getSchools(solarized: false, connected: false);
      cerd = schools.first.cerd;
      name = schools.first.name;
    });

    await tester.pumpWidget(env.wrap(SchoolRecordScreen(cerd: cerd), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 5);

    expect(find.text(name), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.text('No monitored plant'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final seen = await _collect(tester, ['not in the solar tracker', 'Sizing reference', 'School record', 'Internet connectivity']);
    expect(seen, containsAll(<String>['not in the solar tracker', 'School record', 'Internet connectivity']));
    await TestEnv.drain(tester);
  });

  testWidgets('school record survives a narrow tablet', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 12);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolRecordScreen(cerd: 1), size: const Size(900, 800)));
    await TestEnv.settle(tester, rounds: 5);
    expect(find.text('Uruguay First Achrafieh Public School for Boys'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _collect(tester, const ['Energy audit'], scrolls: 16);
    await TestEnv.drain(tester);
  });

  testWidgets('unknown CERD shows the empty message', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 8);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolRecordScreen(cerd: 999999), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 5);

    expect(find.text('School 999999 is not in the dataset.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });
}
