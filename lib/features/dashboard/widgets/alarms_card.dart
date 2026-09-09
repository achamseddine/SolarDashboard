import 'package:flutter/material.dart';

import '../../../core/models/alert.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Alarm summary: active by level, new per day (14 d), top names, most-alarming schools.
class AlarmsCard extends StatelessWidget {
  const AlarmsCard({super.key, required this.insights, this.now});
  final FleetInsights insights;
  final DateTime? now;

  static String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = ChartPalette.of(context);
    final now = this.now ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
    final perDay = [for (final d in days) BarGroup(label: Fmt.shortDate(d), values: [(insights.newAlertsPerDay[_ymd(d)] ?? 0).toDouble()])];
    final total14 = insights.newAlertsPerDay.values.fold(0, (a, b) => a + b);
    final mttr = insights.alertMttrMedianSeconds;
    final names = insights.topAlertNames.take(8).toList();
    final schools = insights.mostAlarmingStations.take(8).toList();

    return SectionCard(
      title: 'Alarms',
      subtitle: '${Fmt.int_(insights.activeAlerts)} active · ${Fmt.int_(insights.alertsOpenOver7d)} open > 7 d · median time to recovery ${mttr == null ? 'n/a' : Fmt.duration(Duration(seconds: mttr.round()))}',
      trailing: const SeeAllButton(location: '/alarms', label: 'Alarm centre'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final l in [AlertLevel.high, AlertLevel.medium, AlertLevel.low])
                InkWell(
                  onTap: () => goTo(context, '/alarms'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LevelChip(l),
                        const SizedBox(width: 6),
                        Text(Fmt.int_(insights.activeAlertsByLevel[l] ?? 0), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('New alarms per day · last 14 days · $total14 total', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          EnergyBarChart(
            seriesLabels: const ['New alarms'],
            seriesColors: [p.categorical[1]],
            groups: perDay,
            height: 150,
            unitFormatter: (v) => Fmt.int_(v),
            maxLabels: 14,
          ),
          const SizedBox(height: 16),
          TwoColumn(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top alarm names (active)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                HorizontalBars(items: [for (final n in names) (n.name, n.count.toDouble(), null)], formatter: (v) => Fmt.int_(v), barHeight: 12),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Most-alarming schools (active)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                HorizontalBars(
                  items: [for (final s in schools) (s.stationName ?? 'Station ${s.stationId}', s.count.toDouble(), null)],
                  formatter: (v) => Fmt.int_(v),
                  barHeight: 12,
                  onTap: (i) => goTo(context, stationRoute(schools[i].stationId)),
                  trailing: (i) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.circle, size: 10, color: AppColors.alertLevel(schools[i].highest), semanticLabel: schools[i].highest.label),
                  ),
                ),
                if (schools.isNotEmpty) const MutedNote('Dot = highest active level · tap a school to open it'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
