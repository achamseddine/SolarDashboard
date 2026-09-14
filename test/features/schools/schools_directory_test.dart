import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/school_insights.dart';
import 'package:unicef_solar_monitor/features/common/widgets.dart';
import 'package:unicef_solar_monitor/features/schools/schools_directory_screen.dart';
import 'package:unicef_solar_monitor/features/schools/widgets/school_csv.dart';
import 'package:unicef_solar_monitor/features/schools/widgets/school_table.dart';

import '../../helpers/test_env.dart';

/// Subtitle of the page header ("1,216 schools · 534 with internet · …").
String _subtitle(WidgetTester tester) => tester.widget<PageHeader>(find.byType(PageHeader)).subtitle!;

/// First number of the subtitle — the number of schools shown.
int _shown(WidgetTester tester) => int.parse(RegExp(r'[\d,]+').firstMatch(_subtitle(tester))!.group(0)!.replaceAll(',', ''));

/// Rows handed to the table (the table renders the first [SchoolTable.defaultMaxRows]).
List<SchoolInsight> _rows(WidgetTester tester) => tester.widget<SchoolTable>(find.byType(SchoolTable)).rows;

void main() {
  testWidgets('school directory lists the whole dataset and filters it', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolsDirectoryScreen()));
    await TestEnv.settle(tester, rounds: 5);
    expect(tester.takeException(), isNull);

    // Header: every school in the dataset, with the source counts.
    expect(find.text('Schools'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    final total = _shown(tester);
    expect(total, greaterThan(1000), reason: 'the directory shows every school, not just monitored plants');
    expect(_subtitle(tester), contains('with internet'));
    expect(_subtitle(tester), contains('solarised'));
    expect(_subtitle(tester), contains('with a monitored plant'));
    expect(_rows(tester).length, total);
    expect(_rows(tester).any((r) => r.isMonitored), isTrue, reason: 'the demo fleet impersonates real schools');

    // Columns of the table.
    for (final c in ['CERD', 'Governorate', 'District', 'Solar', 'kWp', 'Students', 'Audited load', 'Attendance', 'Plant']) {
      expect(find.text(c), findsWidgets, reason: 'missing column $c');
    }
    expect(find.byType(SchoolTable), findsOneWidget);

    // The CSV export mirrors the visible rows.
    final csv = buildSchoolsCsv(_rows(tester).take(5).toList());
    expect(csv, contains('cerd,school,name_ar,governorate,caza'));
    expect(csv.trim().split('\n').length, 6);

    // A known school: CERD 1, Uruguay First Achrafieh (Beirut).
    await tester.enterText(find.byType(TextField).first, 'Uruguay');
    await TestEnv.settle(tester, rounds: 4);
    expect(_rows(tester).any((r) => r.cerd == 1), isTrue);
    expect(find.textContaining('Uruguay'), findsWidgets);
    expect(_shown(tester), lessThan(total));
    expect(_subtitle(tester), contains(' of '));
    expect(tester.takeException(), isNull);

    // "No internet" keeps only schools off the connectivity roll-out.
    await tester.enterText(find.byType(TextField).first, '');
    await TestEnv.settle(tester, rounds: 4);
    expect(_shown(tester), total);
    await tester.tap(find.text('No internet'));
    await TestEnv.settle(tester, rounds: 4);
    final offline = _shown(tester);
    expect(offline, lessThan(total));
    expect(_subtitle(tester), contains('of '));
    expect(_subtitle(tester), contains('· 0 with internet'));
    expect(_rows(tester).every((r) => !r.isConnected), isTrue);
    // Every internet cell of the table is the "not on the roll-out" icon.
    expect(find.descendant(of: find.byType(SchoolTable), matching: find.byIcon(Icons.wifi)), findsNothing);
    expect(find.descendant(of: find.byType(SchoolTable), matching: find.byIcon(Icons.wifi_off)), findsWidgets);
    expect(find.text('Clear filters'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Searching narrows further and the rows change.
    final before = _rows(tester).map((r) => r.cerd).toList();
    await tester.enterText(find.byType(TextField).first, 'Akkar');
    await TestEnv.settle(tester, rounds: 4);
    expect(_shown(tester), lessThan(offline));
    expect(_rows(tester).map((r) => r.cerd).toList(), isNot(before));
    expect(_rows(tester), isNotEmpty);
    expect(_rows(tester).every((r) => !r.isConnected), isTrue);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('sorting by students reorders the table', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 12);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolsDirectoryScreen(initialRegion: 'Beirut')));
    await TestEnv.settle(tester, rounds: 5);
    expect(_rows(tester), isNotEmpty);
    final byName = _rows(tester).first;

    await tester.tap(find.text('Students'));
    await TestEnv.settle(tester, rounds: 4);
    final rows = _rows(tester);
    expect(rows.first.cerd, isNot(byName.cerd), reason: 'the students sort reorders the rows');
    final counts = [for (final r in rows) r.students];
    final firstNull = counts.indexWhere((c) => c == null);
    expect(firstNull == -1 || counts.sublist(firstNull).every((c) => c == null), isTrue, reason: 'schools without an enrolment sort last');
    final known = counts.whereType<int>().toList();
    for (var i = 1; i < known.length; i++) {
      expect(known[i - 1] <= known[i], isTrue);
    }
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('the directory survives a 900 px window', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 6);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SchoolsDirectoryScreen(initialRegion: 'Beirut'), size: const Size(900, 800)));
    await TestEnv.settle(tester, rounds: 5);
    expect(_rows(tester), isNotEmpty);
    expect(_rows(tester).every((r) => r.region == 'Beirut'), isTrue);
    expect(find.text('Clear filters'), findsWidgets);
    // Nothing overflows: the filter bar wraps and the table scrolls sideways.
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });
}
