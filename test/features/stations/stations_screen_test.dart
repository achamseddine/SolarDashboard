import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('station detail renders header, flow, KPIs, devices and alarms', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 12);
    addTearDown(() => tester.runAsync(env.dispose));
    final id = env.api.stationIds.first;

    await tester.pumpWidget(env.wrap(StationDetailScreen(stationId: id)));
    await TestEnv.settle(tester, rounds: 5);
    expect(find.text('Power flow'), findsOneWidget);
    expect(find.text('Generation today'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(tester.takeException(), isNull);

    // ListView builds lazily: scroll through the page and collect the section titles.
    final list = find.byType(ListView).first;
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      for (final label in ['Energy last 30 days', 'Battery — last 30 days', 'Devices ·', 'Alarms', 'Status history']) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(['Energy last 30 days', 'Battery — last 30 days', 'Devices ·', 'Alarms', 'Status history']));
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
