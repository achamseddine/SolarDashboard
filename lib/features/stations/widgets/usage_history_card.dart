import 'package:flutter/material.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Daily production and usage of one plant over the last 30 days — the
/// "Generation & Usage History" block of the DeyeCloud plant overview.
///
/// Like the console, usage is mirrored below the axis: production and battery
/// discharge stack upwards, consumption, charging and purchased grid energy
/// stack downwards, one bar per day.
class UsageHistoryCard extends StatelessWidget {
  const UsageHistoryCard({super.key, required this.detail});

  final StationDetail detail;

  static const _series = ['Production', 'Discharge', 'Consumption', 'Charge', 'Purchased'];

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final days = detail.daily;
    final colors = [p.pv, p.battery, p.load, p.gridExport, p.gridImport];

    if (days.isEmpty) {
      return const SectionCard(
        title: 'Generation & usage history',
        subtitle: 'Daily production and usage of the last 30 days',
        child: EmptyState(message: 'No daily energy counters for this plant yet.', icon: Icons.bar_chart),
      );
    }

    final gen = days.fold(0.0, (a, d) => a + (d.generationKwh ?? 0));
    final cons = days.fold(0.0, (a, d) => a + (d.consumptionKwh ?? 0));
    String full(String period, double? g, double? c) => '${Fmt.shortDay(period)} · ${Fmt.energy(g)} produced · ${Fmt.energy(c)} used';

    // Usage series are passed negative so they stack below the axis.
    double? down(double? v) => v == null ? null : -v;
    final groups = [
      for (final d in days)
        BarGroup(
          label: Fmt.shortDay(d.period),
          fullLabel: full(d.period, d.generationKwh, d.consumptionKwh),
          values: [d.generationKwh, d.dischargeKwh, down(d.consumptionKwh), down(d.chargeKwh), down(d.gridImportKwh)],
        ),
    ];

    return ChartOrTable(
      title: 'Generation & usage history',
      subtitle: 'Last ${days.length} days · Σ ${Fmt.energy(gen)} produced · ${Fmt.energy(cons)} used',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnergyBarChart(
            seriesLabels: _series,
            seriesColors: colors,
            groups: groups,
            stacked: true,
            signed: true,
            height: 280,
            maxLabels: 10,
          ),
          const MutedNote('Production and battery discharge stack above the axis, consumption, battery charging and purchased grid energy below it, so each day reads as one mirrored bar. Values are the daily counters returned by the cloud, so a day the plant did not report is missing rather than zero.'),
        ],
      ),
      table: ChartTable(
        columns: const ['Day', 'Production', 'Discharge', 'Consumption', 'Charge', 'Purchased'],
        rows: [
          for (final d in days.reversed)
            [
              Fmt.shortDay(d.period),
              Fmt.energy(d.generationKwh),
              Fmt.energy(d.dischargeKwh),
              Fmt.energy(d.consumptionKwh),
              Fmt.energy(d.chargeKwh),
              Fmt.energy(d.gridImportKwh),
            ],
        ],
      ),
    );
  }
}
