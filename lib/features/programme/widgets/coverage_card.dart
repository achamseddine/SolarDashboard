import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Stacked bars per governorate (solarised / pipeline / not solarised) and
/// the connectivity share per governorate.
class CoverageByRegionCard extends StatelessWidget {
  const CoverageByRegionCard({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  Widget build(BuildContext context) {
    final regions = insights.regions;
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Coverage by governorate',
      subtitle: 'Public schools by solarisation status, and the share on the internet-connectivity roll-out',
      child: regions.isEmpty
          ? const SizedBox(height: 200, child: EmptyState(message: 'No school dataset imported yet', icon: Icons.map_outlined))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TwoColumn(
                  leftFlex: 3,
                  rightFlex: 2,
                  left: EnergyBarChart(
                    height: 260,
                    stacked: true,
                    seriesLabels: const ['Solarised', 'Pipeline', 'Not solarised'],
                    seriesColors: const [AppColors.good, AppColors.unicefCyan, AppColors.muted],
                    unitFormatter: Fmt.int_,
                    groups: [
                      for (final r in regions)
                        BarGroup(
                          label: shortRegion(r.name),
                          fullLabel: '${r.name} · ${Fmt.int_(r.schools)} schools',
                          values: [r.solarized.toDouble(), r.pipeline.toDouble(), math.max(0, r.notSolarized).toDouble()],
                        ),
                    ],
                  ),
                  right: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connected schools', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      HorizontalBars(
                        items: [for (final r in regions) (r.name, r.connectedShare * 100, null)],
                        color: p.load,
                        maxValue: 100,
                        formatter: (v) => Fmt.percent(v),
                        trailing: (i) => SizedBox(
                          width: 76,
                          child: Text(
                            '${Fmt.int_(regions[i].connected)} / ${Fmt.int_(regions[i].schools)}',
                            style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const MutedNote('Sources: MEHE public school master list (1,211 schools), the internet-connectivity roll-out (534 schools) and the UNICEF solar implementation tracker. Pipeline = planned, on hold and unfunded.'),
              ],
            ),
    );
  }
}

/// Axis-friendly governorate names (full names stay in the tooltips).
String shortRegion(String name) => switch (name) {
      'Mount Lebanon' => 'Mt Lebanon',
      'Keserwan-Jbeil' => 'Kes.-Jbeil',
      'Baalbek-Hermel' => 'Baalbek-H.',
      'Unassigned' => 'Unassigned',
      _ => name,
    };
