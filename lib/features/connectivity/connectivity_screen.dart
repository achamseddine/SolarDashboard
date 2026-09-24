import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/connectivity_insights.dart';
import '../../core/models/network_filter.dart';
import '../../core/models/network_insights.dart';
import '../../core/models/school_insights.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/connectivity_common.dart';
import 'widgets/connectivity_kpis.dart';
import 'widgets/connectivity_region_card.dart';
import 'widgets/data_path_card.dart';
import 'widgets/district_cards.dart';
import 'widgets/quadrant_card.dart';
import '../network/network_tabs.dart';

/// Internet connectivity of the public schools, in two halves.
///
/// **Roll-out** is the MEHE membership list: which schools are on the
/// connectivity programme at all. The other tabs are live telemetry from the
/// GWN Cloud account — infrastructure health, how reliably each school is
/// actually connected, and whether the network is used — following the
/// School Digital Infrastructure & Adoption indicator framework.
class ConnectivityScreen extends ConsumerStatefulWidget {
  const ConnectivityScreen({super.key});

  @override
  ConsumerState<ConnectivityScreen> createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends ConsumerState<ConnectivityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  AdoptionQuadrant? _quadrant;
  NetworkSchoolFilter? _filter;
  int _jump = 0;

  @override
  void initState() {
    super.initState();
    // First open with empty network tables pulls the account once, so the
    // dashboards have something to show without hunting for a sync button.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !ref.read(canSyncNetworksProvider)) return;
      final rows = await ref.read(databaseProvider).networks.getNetworks();
      if (!mounted || rows.isNotEmpty) return;
      try {
        await ref.read(networkSyncReportProvider.notifier).sync();
      } catch (_) {
        // The banner and the empty state carry the failure.
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Jumping from the matrix to the school list carries the filter with it.
  void _showSchools(AdoptionQuadrant quadrant) {
    setState(() {
      _quadrant = quadrant;
      _filter = null;
      _jump++;
    });
    _tabs.animateTo(4);
  }

  /// …and so does jumping from a headline tile, which carries the slice that
  /// produced the number rather than a quadrant.
  void _showFiltered(NetworkSchoolFilter filter) {
    setState(() {
      _filter = filter;
      _quadrant = null;
      _jump++;
    });
    _tabs.animateTo(4);
  }

  /// The Schools tab owns its chips; the screen follows them so a filter
  /// cleared there does not return the next time the tab is built.
  void _onSelection(AdoptionQuadrant? quadrant, NetworkSchoolFilter? filter) {
    if (quadrant == _quadrant && filter == _filter) return;
    setState(() {
      _quadrant = quadrant;
      _filter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Roll-out'),
            Tab(text: 'Network overview'),
            Tab(text: 'Infrastructure'),
            Tab(text: 'Usage'),
            Tab(text: 'Schools'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const _RolloutTab(),
              NetworkOverviewTab(onShowSchools: _showSchools, onOpenList: _showFiltered),
              NetworkInfrastructureTab(onOpenList: _showFiltered),
              const NetworkUsageTab(),
              NetworkSchoolsTab(quadrant: _quadrant, filter: _filter, revision: _jump, onSelectionChanged: _onSelection),
            ],
          ),
        ),
      ],
    );
  }
}

/// The MEHE connectivity roll-out — who is on the programme.
class _RolloutTab extends ConsumerWidget {
  const _RolloutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(connectivityInsightsProvider);
    // Per-school lists (the monitored plants) come from the programme
    // insights; the page renders before they arrive.
    final programme = ref.watch(schoolInsightsProvider).value;
    return AsyncView<ConnectivityInsights>(
      value: insights,
      builder: (d) => _Connectivity(insights: d, programme: programme),
    );
  }
}

class _Connectivity extends ConsumerWidget {
  const _Connectivity({required this.insights, required this.programme});
  final ConnectivityInsights insights;
  final SchoolInsights? programme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = insights;
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).syncNow(),
      child: ListView(
        padding: kPagePadding,
        children: [
          PageHeader(
            title: 'Internet connectivity',
            subtitle: '${Fmt.int_(d.connected)} of ${Fmt.int_(d.schools)} public schools on the roll-out · ${Fmt.ratio(d.share)} · ${Fmt.int_(d.connectedStudents)} students reached',
            actions: [
              OutlinedButton.icon(
                onPressed: () => goTo(context, schoolsRoute(connected: false)),
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Schools'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => goTo(context, '/map'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Map'),
              ),
            ],
          ),
          if (d.schools == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: kGap),
              child: MutedNote('The school dataset has not been imported yet; connectivity figures appear once it is.'),
            ),
          ConnectivityKpiGrid(insights: d),
          const SizedBox(height: kGap),
          ConnectivityByRegionCard(insights: d),
          const SizedBox(height: kGap),
          SolarInternetCard(insights: d),
          const SizedBox(height: kGap),
          DistrictCards(insights: d),
          const SizedBox(height: kGap),
          DataPathCard(insights: d, programme: programme),
          const SizedBox(height: kGap),
          MutedNote(
            'The internet-connectivity roll-out is a membership list of ${Fmt.int_(d.connected + d.connectivityOnlyRecords)} schools: a school is on the list or it is not — '
            'the list carries no bandwidth, provider or uptime. ${Fmt.int_(d.connectivityOnlyRecords)} connectivity records are not in the MEHE public school master list '
            '(${Fmt.int_(d.schools)} schools) and are left out of the figures above. ${Fmt.int_(d.connectedWithCoordinates)} connected schools have coordinates and can be placed on the map. '
            'Solarisation from the UNICEF solar implementation tracker, enrolment from the MEHE master list. Pull down to synchronise the fleet.',
          ),
        ],
      ),
    );
  }
}
