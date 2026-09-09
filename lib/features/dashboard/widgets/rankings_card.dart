import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Top 10 / bottom 10 schools by 7-day specific yield (kWh/kWp/day).
class RankingsCard extends StatelessWidget {
  const RankingsCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final top = insights.topByYield7d(10);
    final bottom = insights.bottomByYield7d(10);
    final ranked = insights.stations.where((s) => s.yield7d != null && s.daysWithData7d >= 3).length;
    final max = top.isEmpty ? null : top.first.yield7d;
    final median = insights.fleetMedianYield7d;
    final subtitle = 'kWh per kWp and day over the last 7 complete days · $ranked plants with ≥ 3 days of data · fleet median ${median == null ? 'n/a' : Fmt.two(median)}';
    return TwoColumn(
      left: _RankList(title: 'Top 10 by 7-day yield', subtitle: subtitle, items: top, max: max),
      right: _RankList(title: 'Bottom 10 by 7-day yield', subtitle: subtitle, items: bottom, max: max),
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({required this.title, required this.subtitle, required this.items, required this.max});
  final String title;
  final String subtitle;
  final List<StationInsight> items;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final flagged = items.where((s) => (s.completeness7d ?? 100) < 80).length;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            const SizedBox(height: 120, child: EmptyState(message: 'No plant has 3 days of complete data yet', icon: Icons.leaderboard_outlined))
          else
            HorizontalBars(
              items: [for (final s in items) (s.name, s.yield7d ?? 0, null)],
              formatter: (v) => Fmt.two(v),
              maxValue: max,
              onTap: (i) => goTo(context, stationRoute(items[i].id)),
              trailing: (i) {
                final c = items[i].completeness7d;
                if (c != null && c < 80) {
                  return Tooltip(
                    message: 'Data completeness ${Fmt.percent(c)} – yield may be under-estimated',
                    triggerMode: TooltipTriggerMode.tap,
                    child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning)),
                  );
                }
                return const SizedBox(width: 26);
              },
            ),
          if (flagged > 0)
            MutedNote('⚠ $flagged with data completeness below 80 %'),
        ],
      ),
    );
  }
}
