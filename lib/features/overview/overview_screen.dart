import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fleet_insights.dart';
import '../../core/models/sync.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/hero_cards.dart';
import 'widgets/overview_cards.dart';

/// Landing page: fleet-wide generation, consumption and carbon footprint.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

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
      builder: (d) => _Overview(insights: d, sync: sync),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.insights, required this.sync});
  final FleetInsights insights;
  final SyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = insights;
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).syncNow(),
      child: ListView(
        padding: kPagePadding,
        children: [
          PageHeader(
            title: 'UNICEF school solar fleet — Lebanon',
            subtitle: '${i.totalStations} schools · ${Fmt.capacity(i.installedKwp)} installed · updated ${Fmt.time(i.generatedAt.millisecondsSinceEpoch ~/ 1000)} · ${i.reportingStations} reporting live',
            actions: [
              OutlinedButton.icon(onPressed: () => goTo(context, '/analytics'), icon: const Icon(Icons.insights_outlined, size: 18), label: const Text('Analytics')),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: sync.running ? null : () => ref.read(syncEngineProvider).syncNow(),
                icon: sync.running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
                label: Text(sync.running ? sync.phase.label : 'Sync now'),
              ),
            ],
          ),
          HeroRow(
            insights: i,
            onGeneration: () => goTo(context, '/analytics'),
            onConsumption: () => goTo(context, '/analytics'),
            onCarbon: () => goTo(context, '/analytics'),
          ),
          const SizedBox(height: kGap),
          const GenerationVsConsumptionCard(),
          const SizedBox(height: kGap),
          TwoColumn(left: EnergyBalanceCard(insights: i), right: CarbonByMonthCard(insights: i)),
          const SizedBox(height: kGap),
          TwoColumn(leftFlex: 3, rightFlex: 2, left: RegionGenerationCard(insights: i), right: FleetHealthCard(insights: i)),
          const SizedBox(height: kGap),
          MutedNote('Live figures sum the schools reporting within the stale threshold. Carbon and diesel figures apply the factors in Settings to self-consumed solar energy (generation minus grid export).'),
        ],
      ),
    );
  }
}
