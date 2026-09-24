import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/network_filter.dart';
import '../../core/models/network_insights.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/network_cards.dart';
import 'widgets/network_detail_sheet.dart';
import 'widgets/network_schools_table.dart';

/// The school-network dashboards, built from the GWN Cloud account against
/// the School Digital Infrastructure & Adoption indicator framework.
///
/// Three tabs sit beside the roll-out view on the Connectivity page: the
/// executive headline with the matrix, infrastructure health, and how the
/// networks are actually used.
class NetworkOverviewTab extends ConsumerWidget {
  const NetworkOverviewTab({super.key, this.onShowSchools, this.onOpenList});

  final void Function(AdoptionQuadrant quadrant)? onShowSchools;

  /// Carries a headline slice to the Schools tab.
  final OpenSchoolList? onOpenList;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            _SourceBanner(insights: d),
            NetworkHeadlineKpis(insights: d, onOpenList: onOpenList),
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
  const NetworkInfrastructureTab({super.key, this.onOpenList});

  final OpenSchoolList? onOpenList;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            InfrastructureCard(insights: d, onOpenList: onOpenList),
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
  const NetworkSchoolsTab({super.key, this.quadrant, this.filter, this.revision = 0, this.onSelectionChanged});

  final AdoptionQuadrant? quadrant;

  /// Set when a headline tile sent its slice here.
  final NetworkSchoolFilter? filter;

  /// Rises on every jump, so the same slice can be sent twice.
  final int revision;

  /// What the table's own chips now say.
  final void Function(AdoptionQuadrant? quadrant, NetworkSchoolFilter? filter)? onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Body(
        builder: (d) => ListView(
          padding: kPagePadding,
          children: [
            NetworkSchoolsTable(
              insights: d,
              initialQuadrant: quadrant,
              initialFilter: filter,
              revision: revision,
              onSelectionChanged: onSelectionChanged,
            ),
          ],
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
      // Emptiness is handled here rather than by a bare message, because
      // there is something the operator can actually do about it.
      builder: (d) => d.isEmpty ? const _NoNetworks() : builder(d),
    );
  }
}

/// Shown until a GWN account is configured. Offers the two ways forward
/// instead of leaving the tab a dead end.
class _NoNetworks extends ConsumerStatefulWidget {
  const _NoNetworks();

  @override
  ConsumerState<_NoNetworks> createState() => _NoNetworksState();
}

class _NoNetworksState extends ConsumerState<_NoNetworks> {
  bool _busy = false;
  String? _error;

  Future<void> _loadSample() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(networkSyncReportProvider.notifier).sync();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final configured = !ref.watch(gwnIsDemoProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: kPagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_find_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text('No school network synchronised yet', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                configured
                    ? 'The GWN Cloud account is configured but has not been pulled yet.'
                    : 'Add the GWN Cloud App ID and Secret Key in Settings to monitor the real school networks. '
                        'You can also load a synthetic sample to see what the dashboards look like — it is clearly '
                        'labelled as demo data and is replaced the moment a real account is configured.',
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _loadSample,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(_busy ? 'Loading…' : (configured ? 'Sync now' : 'Load sample data')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => goTo(context, '/settings'),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Open Settings'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                SelectableText(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
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
      subtitle: '${Fmt.int_(faults.length)} schools with an infrastructure or connectivity fault · tap one for its record',
      child: Column(
        children: [
          for (final s in faults.take(40))
            CompactRow(
              onTap: () => showSchoolNetworkDetail(context, s),
              title: s.name,
              subtitle: [
                if (s.gatewayOnline == false) 'gateway offline',
                if (s.apsMostlyDown) 'most access points down',
                if (s.apsTotal > 0 && s.apsOnline < s.apsTotal) '${s.apsTotal - s.apsOnline} of ${s.apsTotal} APs down',
                if (s.poePortsFailed > 0) '${s.poePortsFailed} PoE ports failed',
                if (s.portsError > 0) '${s.portsError} ports with errors',
                if (s.openCriticalAlarms > 0) '${s.openCriticalAlarms} critical alarms',
              ].join(' · '),
              // Uptime is blank until a day of checks accrues; the access
              // points are the signal a technician acts on.
              trailing: s.apsTotal == 0 ? Fmt.ratio(s.uptimeShare, decimals: 1) : '${s.apsOnline} / ${s.apsTotal}',
              trailingHint: s.apsTotal == 0 ? 'uptime' : 'APs up',
            ),
          if (faults.length > 40) MutedNote('${Fmt.int_(faults.length - 40)} more not shown.'),
        ],
      ),
    );
  }
}
