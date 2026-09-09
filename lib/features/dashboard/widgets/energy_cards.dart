import 'package:flutter/material.dart';

import '../../../core/db/station_dao.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';

/// Daily energy for the last 30 days: generation vs consumption vs import.
class Energy30dCard extends StatelessWidget {
  const Energy30dCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final days = insights.dailySeries30d;
    final l = insights.last30d;
    return ChartOrTable(
      title: 'Energy last 30 days',
      subtitle: 'Σ ${Fmt.energy(l.generationKwh)} generated · ${Fmt.energy(l.consumptionKwh)} consumed · ${Fmt.energy(l.gridImportKwh)} imported · self-sufficiency ${Fmt.ratio(l.selfSufficiency)}',
      chart: EnergyBarChart(
        seriesLabels: const ['Generation', 'Consumption', 'Grid import'],
        seriesColors: [p.pv, p.load, p.gridImport],
        groups: [for (final d in days) BarGroup(label: Fmt.shortDay(d.day), fullLabel: '${Fmt.shortDay(d.day)} · ${d.stations} plants', values: [d.generationKwh, d.consumptionKwh, d.gridImportKwh])],
        maxLabels: 10,
      ),
      table: _energyTable(days, (d) => Fmt.shortDay(d.day)),
    );
  }
}

/// Monthly energy for the last 12 months.
class Energy12mCard extends StatelessWidget {
  const Energy12mCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final months = insights.monthlySeries12m;
    final lt = insights.lifetime;
    return ChartOrTable(
      title: 'Energy last 12 months',
      subtitle: 'Lifetime: ${Fmt.energy(lt.generationKwh)} generated · ${Fmt.energy(lt.consumptionKwh)} consumed',
      chart: EnergyBarChart(
        seriesLabels: const ['Generation', 'Consumption', 'Grid import'],
        seriesColors: [p.pv, p.load, p.gridImport],
        groups: [
          for (final m in months) BarGroup(label: Fmt.monthLabel(m.day).split(' ').first, fullLabel: '${Fmt.monthLabel(m.day)} · ${m.stations} plants', values: [m.generationKwh, m.consumptionKwh, m.gridImportKwh]),
        ],
        maxLabels: 12,
      ),
      table: _energyTable(months, (m) => Fmt.monthLabel(m.day)),
    );
  }
}

ChartTable _energyTable(List<FleetEnergyDay> rows, String Function(FleetEnergyDay) label) => ChartTable(
      columns: const ['Period', 'Plants', 'Generation', 'Consumption', 'Import', 'Export', 'Self-sufficiency'],
      rows: [
        for (final r in rows.reversed)
          [label(r), Fmt.int_(r.stations), Fmt.energy(r.generationKwh), Fmt.energy(r.consumptionKwh), Fmt.energy(r.gridImportKwh), Fmt.energy(r.gridExportKwh), r.selfSufficiency == null ? 'n/a' : Fmt.ratio(r.selfSufficiency)],
      ],
    );
