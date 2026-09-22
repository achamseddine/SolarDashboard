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
/// The console mirrors usage below the axis. [EnergyBarChart] pins `minY` to 0
/// and drops non-positive stack items, so negative values would simply
/// disappear; the usage side is therefore drawn as a second stacked chart
/// directly underneath, sharing one legend with the production side.
class UsageHistoryCard extends StatelessWidget {
  const UsageHistoryCard({super.key, required this.detail});

  final StationDetail detail;

  static const _produced = ['Production', 'Discharge'];
  static const _used = ['Consumption', 'Charge', 'Purchased'];

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final days = detail.daily;
    final producedColors = [p.pv, p.battery];
    final usedColors = [p.load, p.gridExport, p.gridImport];

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

    final producedGroups = [
      for (final d in days)
        BarGroup(
          label: Fmt.shortDay(d.period),
          fullLabel: full(d.period, d.generationKwh, d.consumptionKwh),
          values: [d.generationKwh, d.dischargeKwh],
        ),
    ];
    final usedGroups = [
      for (final d in days)
        BarGroup(
          label: Fmt.shortDay(d.period),
          fullLabel: full(d.period, d.generationKwh, d.consumptionKwh),
          values: [d.consumptionKwh, d.chargeKwh, d.gridImportKwh],
        ),
    ];

    return ChartOrTable(
      title: 'Generation & usage history',
      subtitle: 'Last ${days.length} days · Σ ${Fmt.energy(gen)} produced · ${Fmt.energy(cons)} used',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AxisLabel('Produced', color: p.pv),
          EnergyBarChart(
            seriesLabels: _produced,
            seriesColors: producedColors,
            groups: producedGroups,
            stacked: true,
            showLegend: false,
            height: 170,
            maxLabels: 10,
          ),
          const SizedBox(height: 10),
          _AxisLabel('Used', color: p.load),
          EnergyBarChart(
            seriesLabels: _used,
            seriesColors: usedColors,
            groups: usedGroups,
            stacked: true,
            showLegend: false,
            height: 170,
            maxLabels: 10,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _produced.length; i++) LegendItem(color: producedColors[i], label: _produced[i]),
              for (var i = 0; i < _used.length; i++) LegendItem(color: usedColors[i], label: _used[i]),
            ],
          ),
          const MutedNote('Both axes share one legend: production and battery discharge are stacked on the upper chart, consumption, battery charging and purchased grid energy on the lower one. Values are the daily counters returned by the cloud, so a day the plant did not report is missing rather than zero.'),
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

/// Tiny heading that names one of the two stacked halves.
class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 3, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
