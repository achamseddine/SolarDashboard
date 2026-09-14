import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import '../../programme/widgets/coverage_card.dart' show shortRegion;
import 'connectivity_common.dart';

/// Connected / not connected per governorate, with the share alongside.
class ConnectivityByRegionCard extends StatelessWidget {
  const ConnectivityByRegionCard({super.key, required this.insights});
  final ConnectivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final regions = insights.byRegion;
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Connectivity by governorate',
      subtitle: 'Public schools on the internet roll-out, and the share reached in each governorate',
      child: regions.isEmpty
          ? const SizedBox(height: 180, child: EmptyState(message: 'No school dataset imported yet', icon: Icons.map_outlined))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TwoColumn(
                  leftFlex: 3,
                  rightFlex: 2,
                  left: EnergyBarChart(
                    height: 250,
                    stacked: true,
                    seriesLabels: const ['Connected', 'Not connected'],
                    seriesColors: const [AppColors.unicefCyan, AppColors.muted],
                    unitFormatter: Fmt.int_,
                    groups: [
                      for (final r in regions)
                        BarGroup(
                          label: shortRegion(r.name),
                          fullLabel: '${r.name} · ${Fmt.int_(r.connected)} of ${Fmt.int_(r.schools)} connected',
                          values: [r.connected.toDouble(), r.notConnected.toDouble()],
                        ),
                    ],
                  ),
                  right: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share connected', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      HorizontalBars(
                        items: [for (final r in regions) (r.name, r.share * 100, null)],
                        color: p.load,
                        maxValue: 100,
                        formatter: (v) => Fmt.percent(v),
                        onTap: (i) => goTo(context, schoolsRoute(region: regions[i].name, connected: false)),
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
                const MutedNote('Tap a governorate to list its schools that are still without internet. The roll-out list carries membership only — no bandwidth, provider or uptime.'),
              ],
            ),
    );
  }
}
