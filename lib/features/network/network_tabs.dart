import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/network_insights.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/network_cards.dart';
import 'widgets/network_schools_table.dart';

/// The school-network dashboards, built from the GWN Cloud account against
/// the School Digital Infrastructure & Adoption indicator framework.
///
/// Three tabs sit beside the roll-out view on the Connectivity page: the
/// executive headline with the matrix, infrastructure health, and how the
/// networks are actually used.
class NetworkOverviewTab extends ConsumerWidget {
  const NetworkOverviewTab({super.key, this.onShowSchools});

  final void Function(AdoptionQuadrant quadrant)? onShowSchools;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            _SourceBanner(insights: d),
            NetworkHeadlineKpis(insights: d),
            const SizedBox(height: kGap),
            AdoptionMatrixCard(insights: d, onTap: onShowSchools),
            const SizedBox(height: kGap),
            AdoptionIndexCard(insights: d),
            const SizedBox(height: kGap),
            NetworkRegionCard(insights: d),
            const SizedBox(height: kGap),
            MissingSourcesCard(insights: d),
          ],
        ),
      );
}

class NetworkInfrastructureTab extends ConsumerWidget {
  const NetworkInfrastructureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            InfrastructureCard(insights: d),
            const SizedBox(height: kGap),
            _FaultsCard(insights: d),
          ],
        ),
      );
}

class NetworkUsageTab extends ConsumerWidget {
  const NetworkUsageTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            NetworkTrendCard(insights: d),
            const SizedBox(height: kGap),
            SsidSplitCard(insights: d),
          ],
        ),
      );
}

class NetworkSchoolsTab extends ConsumerWidget {
  const NetworkSchoolsTab({super.key, this.quadrant});

  final AdoptionQuadrant? quadrant;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [NetworkSchoolsTable(insights: d, initialQuadrant: quadrant)],
        ),
      );
}

/// Shared async shell: every network tab waits on the same insights.
class _Body extends ConsumerWidget {
  const _Body({required this.builder});

  final Widget Function(NetworkInsights insights) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(networkInsightsProvider);
    return AsyncView<NetworkInsights>(
      value: insights,
      emptyWhen: (d) => d.isEmpty,
      emptyMessage: 'No school network has been synchronised yet. Add the GWN Cloud App ID and Secret Key in Settings, '
          'or turn on demo mode to see the dashboards with synthetic data.',
      builder: builder,
    );
  }
}

/// Says where the numbers came from, and offers a synchronisation.
class _SourceBanner extends ConsumerWidget {
  const _SourceBanner({required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(gwnIsDemoProvider);
    final report = ref.watch(networkSyncReportProvider);
    final running = ref.watch(networkSyncReportProvider.notifier).isRunning;
    return Padding(
      padding: const EdgeInsets.only(bottom: kGap),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [
                if (demo) 'Synthetic demo data — no GWN Cloud account is configured',
                if (!demo && report != null) 'Synchronised ${Fmt.ago(report.finishedTs)}',
                if (!demo && report == null) 'Not synchronised yet in this session',
                '${Fmt.int_(insights.networks)} networks · ${Fmt.int_(insights.schools.length)} schools · last ${insights.days} days',
                if (report?.message != null) report!.message!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: running ? null : () => ref.read(networkSyncReportProvider.notifier).sync(),
            icon: running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
            label: Text(running ? 'Syncing…' : 'Sync networks'),
          ),
        ],
      ),
    );
  }
}

/// Sections 2 and 7 — the schools a technician should visit.
class _FaultsCard extends StatelessWidget {
  const _FaultsCard({required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final faults = insights.schools.where((s) => s.hasFault).toList()
      ..sort((a, b) => b.openCriticalAlarms.compareTo(a.openCriticalAlarms));
    if (faults.isEmpty) {
      return const SectionCard(
        title: 'Technical intervention required',
        child: EmptyState(message: 'No school is reporting a gateway, port or alarm fault.', icon: Icons.check_circle_outline),
      );
    }
    return SectionCard(
      title: 'Technical intervention required',
      subtitle: '${Fmt.int_(faults.length)} schools with an infrastructure or connectivity fault',
      child: Column(
        children: [
          for (final s in faults.take(40))
            CompactRow(
              title: s.name,
              subtitle: [
                if (s.gatewayOnline == false) 'gateway offline',
                if (s.apsTotal > 0 && s.apsOnline < s.apsTotal) '${s.apsTotal - s.apsOnline} of ${s.apsTotal} APs down',
                if (s.poePortsFailed > 0) '${s.poePortsFailed} PoE ports failed',
                if (s.portsError > 0) '${s.portsError} ports with errors',
                if (s.openCriticalAlarms > 0) '${s.openCriticalAlarms} critical alarms',
              ].join(' · '),
              trailing: Fmt.ratio(s.uptimeShare, decimals: 1),
              trailingHint: 'uptime',
            ),
          if (faults.length > 40) MutedNote('${Fmt.int_(faults.length - 40)} more not shown.'),
        ],
      ),
    );
  }
}
