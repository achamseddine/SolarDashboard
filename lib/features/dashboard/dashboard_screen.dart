import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fleet_insights.dart';
import '../../core/models/sync.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import 'widgets/alarms_card.dart';
import 'widgets/attention_lists.dart';
import 'widgets/battery_card.dart';
import 'widgets/dashboard_common.dart';
import 'widgets/energy_cards.dart';
import 'widgets/environment_card.dart';
import 'widgets/fleet_power_card.dart';
import 'widgets/kpi_row.dart';
import 'widgets/rankings_card.dart';
import 'widgets/region_table.dart';
import 'widgets/status_card.dart';

/// Country-level fleet dashboard.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(fleetInsightsProvider);
    final sync = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final canSync = ref.watch(canSyncProvider);
    return AsyncView<FleetInsights>(
      value: insights,
      emptyWhen: (d) => d.stations.isEmpty,
      emptyMessage: canSync
          ? (sync.running ? 'First synchronisation in progress – ${sync.phase.label}…' : 'No schools yet. The first synchronisation will populate the dashboard.')
          : 'No data source configured. Enter the DeyeCloud credentials or enable demo mode in Settings.',
      builder: (d) => _Dashboard(insights: d, sync: sync),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.insights, required this.sync});
  final FleetInsights insights;
  final SyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = insights;
    final nowRange = i.dataTsMin == null || i.dataTsMax == null ? 'no live data' : '"now" = ${Fmt.time(i.dataTsMin)}–${Fmt.time(i.dataTsMax)}';
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).syncNow(),
      child: ListView(
        padding: kPagePadding,
        children: [
          PageHeader(
            title: 'School solar fleet — Lebanon',
            subtitle: 'Updated ${Fmt.time(i.generatedAt.millisecondsSinceEpoch ~/ 1000)} · $nowRange · ${i.reportingStations} of ${i.totalStations} plants reporting',
            actions: [
              FilledButton.tonalIcon(
                onPressed: sync.running ? null : () => ref.read(syncEngineProvider).syncNow(),
                icon: sync.running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 18),
                label: Text(sync.running ? sync.phase.label : 'Sync now'),
              ),
            ],
          ),
          KpiRow(insights: i),
          const SizedBox(height: kGap),
          TwoColumn(leftFlex: 3, rightFlex: 2, left: const FleetPowerCard(), right: StatusCard(insights: i)),
          const SizedBox(height: kGap),
          TwoColumn(left: Energy30dCard(insights: i), right: Energy12mCard(insights: i)),
          const SizedBox(height: kGap),
          RegionTable(insights: i),
          const SizedBox(height: kGap),
          AttentionLists(insights: i),
          const SizedBox(height: kGap),
          RankingsCard(insights: i),
          const SizedBox(height: kGap),
          BatteryCard(insights: i),
          const SizedBox(height: kGap),
          AlarmsCard(insights: i),
          const SizedBox(height: kGap),
          EnvironmentCard(insights: i),
          const SizedBox(height: kGap),
          MutedNote('Live figures sum reporting plants only (data within the stale threshold). Energy for closed days comes from DeyeCloud history; today from inverter counters.'),
        ],
      ),
    );
  }
}
