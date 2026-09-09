import 'package:flutter/material.dart';

import '../../../core/models/alert.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

const _maxRows = 8;

/// The four triage lists: offline/stale, under-performers, low battery, critical alarms.
class AttentionLists extends StatelessWidget {
  const AttentionLists({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final down = insights.downStations;
    final under = insights.underPerformers;
    final lowSoc = insights.lowSocStations;
    final critical = insights.criticalStations;
    return CardRow(
      children: [
        _AttentionCard(
          title: 'Offline / stale',
          count: down.length,
          icon: Icons.cloud_off_outlined,
          seeAll: stationsRoute(status: StationStatus.offline.name),
          emptyText: 'All plants are reporting',
          rows: [
            for (final s in down.take(_maxRows))
              CompactRow(
                leading: Icon(AppColors.stationStatusIcon(s.status), size: 18, color: AppColors.stationStatus(s.status)),
                title: s.name,
                subtitle: '${s.status.label} · ${s.region} · last data ${Fmt.ago(s.latest?.dataTs ?? s.station.lastUpdateTs)}',
                trailing: s.currentOutage == null ? '–' : Fmt.duration(s.currentOutage),
                trailingHint: 'down for',
                onTap: () => goTo(context, stationRoute(s.id)),
              ),
          ],
        ),
        _AttentionCard(
          title: 'Under-performers',
          count: under.length,
          icon: Icons.trending_down,
          seeAll: stationsRoute(filter: 'underperforming'),
          emptyText: 'No plant below 50 % of its peer median',
          rows: [
            for (final s in under.take(_maxRows))
              CompactRow(
                leading: const Icon(Icons.trending_down, size: 18, color: AppColors.serious),
                title: s.name,
                subtitle: '${s.region} · yield ${Fmt.two(s.yield7d)} vs peer ${Fmt.two(s.peerMedianYield7d)} kWh/kWp/d',
                trailing: Fmt.ratio(s.performanceRatio7d),
                trailingHint: 'of peer median',
                onTap: () => goTo(context, stationRoute(s.id)),
              ),
          ],
        ),
        _AttentionCard(
          title: 'Low battery',
          count: lowSoc.length,
          icon: Icons.battery_alert_outlined,
          seeAll: stationsRoute(filter: 'lowsoc'),
          emptyText: 'No battery below 20 %',
          rows: [
            for (final s in lowSoc.take(_maxRows))
              CompactRow(
                leading: const Icon(Icons.battery_alert_outlined, size: 18, color: AppColors.warning),
                title: s.name,
                subtitle: '${s.region} · min today ${Fmt.percent(s.socMinToday)} · ${s.hoursBelow20Today == null ? '–' : Fmt.one(s.hoursBelow20Today)} h below 20 %',
                trailing: Fmt.percent(s.socNow),
                trailingHint: 'SOC now',
                onTap: () => goTo(context, stationRoute(s.id)),
              ),
          ],
        ),
        _AttentionCard(
          title: 'Critical alarms',
          count: critical.length,
          icon: Icons.warning_amber_rounded,
          seeAll: '/alarms',
          emptyText: 'No high-level alarm active',
          rows: [
            for (final s in critical.take(_maxRows))
              CompactRow(
                leading: const LevelChip(AlertLevel.high),
                title: s.name,
                subtitle: '${s.region} · ${s.status.label}',
                trailing: Fmt.int_(s.activeAlerts),
                trailingHint: 'active',
                onTap: () => goTo(context, stationRoute(s.id)),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.title, required this.count, required this.icon, required this.seeAll, required this.emptyText, required this.rows});
  final String title;
  final int count;
  final IconData icon;
  final String seeAll;
  final String emptyText;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '$title · $count',
      subtitle: count > _maxRows ? 'Showing $_maxRows of $count' : null,
      trailing: SeeAllButton(location: seeAll),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: AppColors.good),
                  const SizedBox(width: 8),
                  Expanded(child: Text(emptyText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ),
            )
          : Column(children: rows),
    );
  }
}
