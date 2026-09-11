import 'package:flutter/material.dart';

import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'programme_common.dart';

/// Audited annual load (MEHE energy audit) against expected and measured
/// generation, plus the top equipment loads of the inventory.
class EnergyAuditCard extends StatelessWidget {
  const EnergyAuditCard({super.key, required this.insights});
  final SchoolInsights insights;

  static const _maxEquipment = 10;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    final cats = d.loadByCategory;
    final known = {'Lighting': p.pv, 'HVAC': p.gridImport, 'IT': p.load, 'Miscellaneous': AppColors.muted};
    final slices = <(String, double, Color)>[
      for (final e in known.entries) (e.key, cats[e.key] ?? 0, e.value),
    ];
    var other = 0.0;
    for (final e in cats.entries) {
      if (!known.containsKey(e.key)) other += e.value;
    }
    if (other > 0) slices.add(('Other', other, p.gridExport));
    final total = slices.fold(0.0, (a, s) => a + s.$2);
    final hasAudit = d.auditedSchools > 0 && total > 0;
    // The donut legend prints whole numbers: show MWh once the audit runs into
    // the millions of kWh so the labels stay short.
    final inMwh = total >= 1e6;
    final donutSlices = [for (final s in slices) (s.$1, inMwh ? s.$2 / 1e3 : s.$2, s.$3)];
    final noMeasured = d.measuredSchools == 0;
    final sizing = d.fleetSizingRatio;
    final led = d.ledShare;
    final top = d.topEquipment.take(_maxEquipment).toList();

    return SectionCard(
      title: 'Energy: audited load vs solar',
      subtitle: 'MEHE energy audit (annual loads in kWh/year) against the installed capacity and the measured generation of linked plants',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TwoColumn(
            left: hasAudit
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DonutChart(size: 170, slices: donutSlices, centerValue: energyCompact(total), centerLabel: 'per year'),
                      MutedNote('Audited load by category, ${inMwh ? 'MWh' : 'kWh'}/year.'),
                    ],
                  )
                : const SizedBox(height: 170, child: EmptyState(message: 'No energy audit in the dataset', icon: Icons.donut_large_outlined)),
            right: FactWrap(
              children: [
                FactTile(label: 'Audited schools', value: Fmt.int_(d.auditedSchools), hint: 'with an annual load estimate'),
                FactTile(label: 'Audited load', value: Fmt.energy(d.auditedLoadKwh), hint: 'per year, all audited schools'),
                FactTile(label: 'Solarised audited load', value: Fmt.energy(d.solarizedLoadKwh), hint: '${Fmt.int_(d.solarizedAuditCount)} solarised schools audited'),
                FactTile(label: 'Expected generation', value: Fmt.energy(d.expectedGenKwh), hint: '${Fmt.capacity(d.installedKwp)} × ${Fmt.int_(d.specificYieldKwhPerKwp)} kWh/kWp/yr', color: p.pv),
                FactTile(
                  label: 'Measured generation · 30 d',
                  value: noMeasured ? '–' : Fmt.energy(d.measuredGenKwh30d),
                  hint: noMeasured ? 'No monitored plant yet' : '${Fmt.int_(d.measuredSchools)} monitored schools',
                  color: noMeasured ? null : p.pv,
                ),
                FactTile(
                  label: 'Measured consumption · 30 d',
                  value: noMeasured ? '–' : Fmt.energy(d.measuredConsKwh30d),
                  hint: noMeasured ? 'No monitored plant yet' : 'same ${Fmt.int_(d.measuredSchools)} schools',
                  color: noMeasured ? null : p.load,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Meter(
                  title: 'Fleet sizing ratio',
                  value: sizing,
                  color: sizing == null
                      ? AppColors.muted
                      : sizing >= 1
                          ? AppColors.good
                          : sizing >= 0.6
                              ? AppColors.warning
                              : AppColors.serious,
                  hint: sizing == null ? 'Needs solarised schools with an energy audit' : 'Expected generation ÷ audited load of the solarised, audited schools',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Meter(
                  title: 'LED share of lighting',
                  value: led,
                  color: p.pv,
                  hint: led == null ? 'No lighting inventory' : 'Lighting energy already on LED (audit inventory)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Top equipment loads', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (top.isEmpty)
            const MutedNote('No equipment inventory in the dataset.')
          else
            ChartTable(
              maxHeight: 280,
              columns: const ['Equipment', 'Category', 'Items', 'kWh/year'],
              rows: [for (final e in top) [e.type, e.category, Fmt.int_(e.items), Fmt.int_(e.annualKwh)]],
            ),
          const MutedNote('Expected generation = installed kWp × specific yield (Settings, default 1,500 kWh/kWp/yr). Audited loads are MEHE energy-audit estimates; measured figures come from the linked DeyeCloud plants over the last 30 days.'),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.title, required this.value, required this.color, required this.hint});
  final String title;
  final double? value;
  final Color color;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(value == null ? 'n/a' : Fmt.ratio(value), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 4),
        RatioMeter(value: value ?? 0, color: color),
        const SizedBox(height: 2),
        Text(hint, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
