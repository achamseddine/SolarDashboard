import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Measured 30-day generation of monitored schools as a share of their
/// audited monthly load.
class MeasuredVsAuditedCard extends StatelessWidget {
  const MeasuredVsAuditedCard({super.key, required this.insights});
  final SchoolInsights insights;

  static const _maxRows = 12;
  static const _cap = 300.0;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final all = d.byMeasuredCoverage;
    final rows = all.take(_maxRows).toList();
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final values = [for (final s in rows) math.min(_cap, s.measuredCoverage! * 100)];
    final maxValue = values.fold(100.0, math.max);

    return SectionCard(
      title: 'Measured vs audited',
      subtitle: all.length > _maxRows
          ? 'Showing $_maxRows of ${all.length} monitored schools · highest coverage first'
          : 'Measured PV generation of the last 30 days, scaled to a month, as a share of the monthly audited load',
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.monitored == 0
                          ? 'No monitored plant yet — the comparison appears after the first synchronisation.'
                          : 'No monitored school has both an energy audit and generation data for the last 30 days.',
                      style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HorizontalBars(
                  items: [for (var i = 0; i < rows.length; i++) (rows[i].name, values[i], null)],
                  color: p.pv,
                  maxValue: maxValue,
                  formatter: (v) => v >= _cap ? '≥ ${Fmt.percent(_cap)}' : Fmt.percent(v),
                  onTap: (i) => goTo(context, stationRoute(rows[i].station!.id)),
                  trailing: (i) => SizedBox(
                    width: 64,
                    child: Text(
                      '${rows[i].measuredDays30d} d data',
                      style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                const MutedNote('100 % = the plant generated as much as the audit says the school uses. Well above 100 % points to a conservative audit or export to the grid; well below to an undersized or under-performing system. Display capped at 300 %. Tap a school to open its plant.'),
              ],
            ),
    );
  }
}
