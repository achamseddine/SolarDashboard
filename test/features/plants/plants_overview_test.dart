import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/station.dart';
import 'package:unicef_solar_monitor/features/plants/plants_overview_screen.dart';
import 'package:unicef_solar_monitor/features/plants/widgets/plant_table.dart';

import '../../helpers/test_env.dart';

/// Plant names of the rows the table currently builds, in display order.
List<String> _rowNames(WidgetTester tester) =>
    tester.widgetList<PlantNameCell>(find.byType(PlantNameCell)).map((c) => c.insight.name).toList();

List<StationStatus> _rowStatuses(WidgetTester tester) =>
    tester.widgetList<PlantNameCell>(find.byType(PlantNameCell)).map((c) => c.insight.status).toList();

List<double?> _rowCapacities(WidgetTester tester) =>
    tester.widgetList<PlantNameCell>(find.byType(PlantNameCell)).map((c) => c.insight.kwp).toList();

Future<void> _tapAt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('plants overview lists every plant with the DeyeCloud figures, counters, sorting and paging', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 40);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const PlantsOverviewScreen(), size: const Size(1600, 1200)));
    await TestEnv.settle(tester, rounds: 4);

    // Header and the five figures of the console's KPI strip.
    expect(find.text('Plants'), findsOneWidget);
    expect(find.textContaining('40 plants in the DeyeCloud account'), findsOneWidget);
    for (final label in ['Real-time generating power', 'Installed capacity', 'Daily production', 'Monthly production', 'Total production']) {
      expect(find.text(label), findsWidgets, reason: 'KPI "$label" missing');
    }

    // Counter row: the total mirrors the number of plants in the account.
    expect(find.text('Total 40'), findsOneWidget);

    // Every plant is listed, whatever its location — no plant is dropped for a
    // missing governorate, address or school link.
    final allNames = _rowNames(tester);
    expect(allNames.length, 40);
    expect(find.text(env.api.seedByStation[3000]!.name), findsWidgets);
    expect(tester.takeException(), isNull);

    // Counter chips filter the table but keep showing the fleet-wide totals.
    await _tapAt(tester, find.byKey(const ValueKey('plant-counter-offline')));
    final offlineNames = _rowNames(tester);
    expect(offlineNames.length, lessThan(allNames.length));
    expect(_rowStatuses(tester).every((s) => s == StationStatus.offline), isTrue);
    expect(find.text('Total 40'), findsOneWidget);
    expect(find.textContaining('40 plants in the DeyeCloud account'), findsOneWidget);

    // Back to the whole fleet.
    await _tapAt(tester, find.byKey(const ValueKey('plant-counter-total')));
    expect(_rowNames(tester).length, 40);

    // Sorting by capacity reorders the rows (nulls last, both directions).
    await _tapAt(tester, find.text('Capacity (kWp)'));
    final ascending = _rowCapacities(tester);
    expect(_isSorted(ascending, ascending: true), isTrue, reason: 'capacities not ascending: $ascending');
    final firstAscending = _rowNames(tester).first;

    await _tapAt(tester, find.text('Capacity (kWp)'));
    final descending = _rowCapacities(tester);
    expect(_isSorted(descending, ascending: false), isTrue, reason: 'capacities not descending: $descending');
    expect(_rowNames(tester).first, isNot(firstAscending));

    // Paging: 25 per page over the 40 plants of the account.
    await _tapAt(tester, find.byKey(const ValueKey('plant-page-size-25')));
    expect(find.textContaining('Showing 1–25 of 40'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(_rowNames(tester).length, 25);

    await _tapAt(tester, find.byKey(const ValueKey('plant-page-next')));
    expect(find.textContaining('Showing 26–40 of 40'), findsOneWidget);
    expect(_rowNames(tester).length, 15);
    expect(tester.takeException(), isNull);

    await TestEnv.drain(tester);
  });

  testWidgets('plants overview survives a narrow tablet and a deep-linked counter', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 24);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const PlantsOverviewScreen(initialStatus: 'online'), size: const Size(1024, 768)));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('Plants'), findsOneWidget);
    expect(find.text('Total 24'), findsOneWidget);
    expect(_rowStatuses(tester).every((s) => s == StationStatus.online), isTrue);
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    for (var i = 0; i < 4; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    await TestEnv.drain(tester);
  });

  testWidgets('plants overview shows the empty state before the first sync', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create(sync: false));
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const PlantsOverviewScreen(), size: const Size(1280, 900)));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('Plants'), findsOneWidget);
    expect(find.textContaining('0 plants in the DeyeCloud account'), findsOneWidget);
    expect(find.text('Total 0'), findsOneWidget);
    expect(find.textContaining('The first synchronisation pulls every plant'), findsOneWidget);
    expect(find.byType(PlantNameCell), findsNothing);
    expect(tester.takeException(), isNull);

    await TestEnv.drain(tester);
  });
}

/// True when the non-null values run in the requested direction and every
/// missing capacity sits at the end.
bool _isSorted(List<double?> values, {required bool ascending}) {
  final firstNull = values.indexWhere((v) => v == null);
  if (firstNull >= 0 && values.skip(firstNull).any((v) => v != null)) return false;
  final present = values.whereType<double>().toList();
  for (var i = 1; i < present.length; i++) {
    if (ascending ? present[i] < present[i - 1] : present[i] > present[i - 1]) return false;
  }
  return true;
}
