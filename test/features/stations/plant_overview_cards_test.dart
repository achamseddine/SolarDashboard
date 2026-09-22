import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/providers.dart';
import 'package:unicef_solar_monitor/features/common/charts.dart';
import 'package:unicef_solar_monitor/features/common/widgets.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/plant_summary_card.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/solar_utilisation_card.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/usage_history_card.dart';

import '../../helpers/test_env.dart';

/// Watches the detail of one plant and pumps the three overview cards, handing
/// the loaded [StationDetail] back to the test so assertions can adapt to the
/// synthetic fleet instead of hard-coding kWh values.
class _OverviewCards extends ConsumerWidget {
  const _OverviewCards(this.stationId, this.onDetail);

  final int stationId;
  final void Function(StationDetail) onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(stationDetailProvider(stationId)).value;
    if (detail == null) return const Center(child: Text('loading'));
    onDetail(detail);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        PlantSummaryCard(detail: detail),
        const SizedBox(height: 12),
        SolarUtilisationCard(detail: detail),
        const SizedBox(height: 12),
        UsageHistoryCard(detail: detail),
      ],
    );
  }
}

KpiTile _tile(WidgetTester tester, String label) =>
    tester.widget<KpiTile>(find.byWidgetPredicate((w) => w is KpiTile && w.label == label, description: 'KpiTile "$label"'));

void main() {
  testWidgets('the plant overview cards mirror the console summary, utilisation donuts and usage history', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 8);
    addTearDown(() => tester.runAsync(env.dispose));

    late List<int> ids;
    await tester.runAsync(() async => ids = await env.db.stations.getStationIds());
    expect(ids, isNotEmpty, reason: 'the demo sweep must have seeded plants');

    StationDetail? detail;
    await tester.pumpWidget(env.wrap(_OverviewCards(ids.first, (d) => detail = d), size: const Size(1400, 900)));
    await TestEnv.settle(tester, rounds: 4);
    expect(detail, isNotNull, reason: 'the station detail provider must resolve');
    final d = detail!;

    // --- Card 1: summary -----------------------------------------------
    expect(find.text('Summary'), findsOneWidget);
    for (final label in ['Accumulative production', 'Accumulative consumption', 'Daily production', 'Daily consumption', 'This month', 'Self-sufficiency']) {
      expect(find.text(label), findsOneWidget, reason: 'the summary tile "$label" must be shown');
    }
    expect(_tile(tester, 'Accumulative production').value, isNotEmpty);
    expect(_tile(tester, 'Accumulative production').value, isNot('0'));
    expect(_tile(tester, 'Accumulative production').hint, contains('since commissioning'));
    expect(_tile(tester, 'This month').hint, 'production, month to date');
    // A plant that reported nothing prints the en dash, never a bare zero.
    if (d.lifetime.generationKwh <= 0) {
      expect(_tile(tester, 'Accumulative production').value, '–');
    } else {
      expect(_tile(tester, 'Accumulative production').value, contains('Wh'));
    }

    // --- Card 2: solar & utilisation -----------------------------------
    expect(find.text('Solar & utilisation'), findsOneWidget);
    final hasMonth = d.monthToDate.consumptionKwh > 0 || d.monthToDate.generationKwh > 0;
    if (hasMonth) {
      expect(find.text('Where the consumption came from'), findsOneWidget);
      expect(find.text('Where the production went'), findsOneWidget);
      expect(find.byType(DonutChart), findsNWidgets(2));
      // Each slice gets its own legend line (value + share) from DonutChart.
      final donutLegend = find.descendant(of: find.byType(SolarUtilisationCard), matching: find.byType(LegendItem));
      expect(donutLegend, findsNWidgets(6), reason: 'three slices per donut, each with its value and share');
      expect(find.descendant(of: find.byType(SolarUtilisationCard), matching: find.textContaining('Grid feed-in')), findsOneWidget);
      expect(find.descendant(of: find.byType(SolarUtilisationCard), matching: find.textContaining('%')), findsWidgets);
      expect(find.textContaining('Month to date, from the daily energy counters'), findsOneWidget);
    } else {
      expect(find.textContaining('once the plant reports a full day'), findsOneWidget);
    }

    // --- Card 3: generation & usage history -----------------------------
    expect(find.text('Generation & usage history'), findsOneWidget);
    if (d.daily.isEmpty) {
      expect(find.text('No daily energy counters for this plant yet.'), findsOneWidget);
    } else {
      expect(find.byType(EnergyBarChart), findsNWidgets(2), reason: 'production above, usage below');
      expect(find.descendant(of: find.byType(UsageHistoryCard), matching: find.byWidgetPredicate((w) => w is LegendItem && w.label == 'Purchased')), findsOneWidget);
      // The table twin carries the same five series.
      await tester.tap(find.byTooltip('Show table'));
      await TestEnv.settle(tester, rounds: 2);
      expect(find.byType(ChartTable), findsWidgets);
      for (final column in ['Day', 'Production', 'Discharge', 'Consumption', 'Charge', 'Purchased']) {
        expect(find.text(column), findsWidgets, reason: 'the table column "$column" must be shown');
      }
    }

    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('the plant overview cards lay out without overflow at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 8);
    addTearDown(() => tester.runAsync(env.dispose));

    late List<int> ids;
    await tester.runAsync(() async => ids = await env.db.stations.getStationIds());

    StationDetail? detail;
    await tester.pumpWidget(env.wrap(_OverviewCards(ids.first, (d) => detail = d), size: const Size(900, 800)));
    await TestEnv.settle(tester, rounds: 4);
    expect(detail, isNotNull);
    expect(find.text('Summary'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no render overflow at 900 x 800');

    // Scroll the whole page: the cards further down must lay out too.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.text('Generation & usage history'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no render overflow after scrolling');
    await TestEnv.drain(tester);
  });
}
