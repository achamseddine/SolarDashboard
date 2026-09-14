import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/connectivity_insights.dart';
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

/// Internet connectivity of the public schools: the roll-out per governorate
/// and district, how it overlaps with the solar programme, and which
/// monitored plants have no data path back to the cloud.
class ConnectivityScreen extends ConsumerWidget {
  const ConnectivityScreen({super.key});

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
