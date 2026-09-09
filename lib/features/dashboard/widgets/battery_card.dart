import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// SOC histogram of reporting plants + plants with hours below 20 % today.
class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final counts = insights.socHistogram.length == 5 ? insights.socHistogram : List<int>.filled(5, 0);
    final withBattery = counts.fold(0, (a, b) => a + b);
    final below = insights.stations.where((s) => (s.hoursBelow20Today ?? 0) > 0).toList()..sort((a, b) => b.hoursBelow20Today!.compareTo(a.hoursBelow20Today!));
    final cycles = insights.stations.map((s) => s.batteryCyclesProxy7d).whereType<double>().toList();
    final meanCycles = cycles.isEmpty ? null : cycles.reduce((a, b) => a + b) / cycles.length;
    return SectionCard(
      title: 'Battery health',
      subtitle: 'Median SOC ${Fmt.percent(insights.socMedian)} · $withBattery plants with SOC · mean 7-day cycles ${meanCycles == null ? 'n/a' : Fmt.one(meanCycles)}',
      child: TwoColumn(
        leftFlex: 3,
        rightFlex: 2,
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SOC distribution now', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SocHistogram(counts: counts, height: 170, onTap: (b) => goTo(context, b == 0 ? stationsRoute(filter: 'lowsoc') : stationsRoute())),
            const MutedNote('Reporting plants only · tap the first bucket to list low-SOC schools'),
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hours below 20 % today · ${below.length}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (below.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, size: 18, color: AppColors.good),
                  const SizedBox(width: 8),
                  Expanded(child: Text('No battery spent time below 20 % today', style: t.bodyMedium)),
                ]),
              )
            else
              for (final s in below.take(8))
                CompactRow(
                  leading: Icon(Icons.battery_2_bar_outlined, size: 18, color: ChartPalette.of(context).socColor(s.socNow ?? 0)),
                  title: s.name,
                  subtitle: '${s.region} · SOC now ${Fmt.percent(s.socNow)} · min ${Fmt.percent(s.socMinToday)}',
                  trailing: '${Fmt.one(s.hoursBelow20Today)} h',
                  onTap: () => goTo(context, stationRoute(s.id)),
                ),
            if (below.length > 8) MutedNote('Showing 8 of ${below.length}'),
          ],
        ),
      ),
    );
  }
}
