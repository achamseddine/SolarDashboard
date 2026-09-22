import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/school.dart';
import 'package:unicef_solar_monitor/features/stations/station_detail_screen.dart';
import 'package:unicef_solar_monitor/features/stations/station_filters.dart';
import 'package:unicef_solar_monitor/features/stations/stations_screen.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/station_csv.dart';
import 'package:unicef_solar_monitor/core/insights/fleet_insights_builder.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('schools list renders a filterable table', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 24);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const StationsScreen()));
    await TestEnv.settle(tester);
    expect(find.textContaining('24 schools'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Yield 7 d'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Search narrows the list.
    await tester.enterText(find.byType(TextField).first, 'Tripoli');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('of 24 schools'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status deep link pre-filters the list', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 24);
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(env.wrap(const StationsScreen(initialStatus: 'online')));
    await TestEnv.settle(tester);
    expect(find.textContaining('online'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('station filter applies quick filters and sorts with nulls last', () async {
    final env = await TestEnv.create(schools: 24);
    final insights = await FleetInsightsBuilder(env.db).build(env.settings);
    final all = insights.stations;
    final low = const StationFilter(lowSoc: true).apply(all);
    expect(low.every((s) => s.socNow != null && s.socNow! < 20), isTrue);
    final sorted = const StationFilter(sort: StationSort.generationNow, ascending: false).apply(all);
    final withValue = sorted.where((s) => s.snapshot?.generationW != null).toList();
    for (var i = 1; i < withValue.length; i++) {
      expect(withValue[i - 1].snapshot!.generationW! >= withValue[i].snapshot!.generationW!, isTrue);
    }
    final csv = buildStationsCsv(all);
    expect(csv.split('\n').length, greaterThan(24));
    expect(csv, contains('governorate'));
    await env.dispose();
  });

  test('station filter uses the school links: connected, linked, CERD search and sort', () async {
    final env = await TestEnv.create(schools: 24);
    final insights = await FleetInsightsBuilder(env.db).build(env.settings);
    final all = insights.stations;
    final Map<int, School> map = await env.db.schools.linkedSchools();
    expect(map, isNotEmpty, reason: 'demo plants impersonate real schools, so links must exist');

    // Connected keeps only linked stations whose school is on the roll-out.
    final connected = const StationFilter(connected: true).apply(all, schools: map);
    final expected = all.where((s) => map[s.id]?.connected == true).toList();
    expect(connected.length, expected.length);
    expect(connected.every((s) => map[s.id]?.connected == true), isTrue);
    // Without the link map nothing is connected.
    expect(const StationFilter(connected: true).apply(all), isEmpty);

    // Linked / unlinked partition the fleet.
    final linked = const StationFilter(linked: true).apply(all, schools: map);
    final unlinked = const StationFilter(linked: false).apply(all, schools: map);
    expect(linked.length + unlinked.length, all.length);
    expect(linked.every((s) => map.containsKey(s.id)), isTrue);
    expect(unlinked.any((s) => map.containsKey(s.id)), isFalse);

    // Search by CERD and by the MEHE school name.
    final first = map.entries.first;
    final byCerd = StationFilter(query: '${first.value.cerd}').apply(all, schools: map);
    expect(byCerd.map((s) => s.id), contains(first.key));
    final byName = StationFilter(query: first.value.name).apply(all, schools: map);
    expect(byName.map((s) => s.id), contains(first.key));

    // CERD sort: ascending numbers, unlinked plants last.
    final sorted = const StationFilter(sort: StationSort.cerd).apply(all, schools: map);
    final cerds = [for (final s in sorted) map[s.id]?.cerd];
    final firstNull = cerds.indexWhere((c) => c == null);
    expect(firstNull == -1 || cerds.sublist(firstNull).every((c) => c == null), isTrue);
    final nonNull = cerds.whereType<int>().toList();
    for (var i = 1; i < nonNull.length; i++) {
      expect(nonNull[i - 1] <= nonNull[i], isTrue);
    }

    // Route flags and the CSV columns.
    final fromRoute = StationFilter.fromRoute(connected: '1', linked: '0');
    expect(fromRoute.connected, isTrue);
    expect(fromRoute.linked, isFalse);
    expect(fromRoute.hasActiveFilter, isTrue);
    expect(StationFilter.fromRoute().connected, isNull);
    final csv = buildStationsCsv(all, schools: map);
    expect(csv, contains('cerd,mehe_school_name,connected,donor,students'));
    expect(csv, contains('${first.value.cerd}'));
    await env.dispose();
  });

  testWidgets('linked-to-school chip filters the list and the table shows CERD numbers', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 24);
    addTearDown(() => tester.runAsync(env.dispose));
    // Database queries need the real async zone.
    final map = (await tester.runAsync<Map<int, School>>(() => env.db.schools.linkedSchools()))!;
    expect(map, isNotEmpty);

    await tester.pumpWidget(env.wrap(const StationsScreen()));
    await TestEnv.settle(tester);
    expect(find.text('24 schools'), findsOneWidget);
    expect(find.text('CERD'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('Donor'), findsOneWidget);
    // A linked plant shows its CERD number in the table.
    expect(find.text('${map.values.first.cerd}'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Linked to school'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('24 schools'), findsNothing);
    expect(find.textContaining('schools · linked'), findsOneWidget);
    expect(find.textContaining(map.length == 24 ? '24 schools' : '${map.length} of 24 schools'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Connected chip narrows further (or keeps the count) and is reflected in the subtitle.
    await tester.tap(find.text('Connected'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('connected · linked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('plant page shows the overview and every tab of the console layout', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 12);
    addTearDown(() => tester.runAsync(env.dispose));
    final id = env.api.stationIds.first;

    await tester.pumpWidget(env.wrap(StationDetailScreen(stationId: id)));
    await TestEnv.settle(tester, rounds: 5);

    // Header and the four console tabs.
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Plant info'), findsOneWidget);
    expect(find.textContaining('Inverters online'), findsOneWidget);
    expect(find.text('Power flow'), findsOneWidget);
    expect(find.text('Generation today'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The overview scrolls through the summary, utilisation and history cards.
    final list = find.byType(ListView).first;
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      for (final label in ['Summary', 'Energy last 30 days', 'Battery — last 30 days']) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(['Summary', 'Energy last 30 days', 'Battery — last 30 days']));

    // Each remaining tab renders its own content.
    await tester.tap(find.text('Devices'));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.textContaining('Devices ·'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Alerts'));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.textContaining('Alarms'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Plant info'));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.text('Plant'), findsWidgets);
    expect(find.text('Plant id'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('station detail handles an unknown id', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 3);
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(env.wrap(const StationDetailScreen(stationId: 999999)));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.textContaining('not in the local database'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });
}
