import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/school_insights.dart';
import '../../core/providers.dart';
import '../../core/schools/school_dataset.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/coverage_card.dart';
import 'widgets/education_card.dart';
import 'widgets/energy_card.dart';
import 'widgets/links_card.dart';
import 'widgets/measured_card.dart';
import 'widgets/programme_attention.dart';
import 'widgets/programme_kpis.dart';
import 'widgets/status_funding_cards.dart';

/// Programme dashboard: solarisation coverage, connectivity, investment,
/// audited loads vs generation, education indicators and plant ↔ school
/// links — the school dataset joined with the live fleet.
class ProgrammeScreen extends ConsumerWidget {
  const ProgrammeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(schoolInsightsProvider);
    final info = ref.watch(schoolDatasetInfoProvider).value;
    return AsyncView<SchoolInsights>(
      value: insights,
      builder: (d) => _Programme(insights: d, info: info),
    );
  }
}

class _Programme extends ConsumerWidget {
  const _Programme({required this.insights, required this.info});
  final SchoolInsights insights;
  final SchoolDatasetInfo? info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = insights;
    final version = info?.version;
    final generated = info?.generatedAt;
    return RefreshIndicator(
      onRefresh: () => ref.read(syncEngineProvider).syncNow(),
      child: ListView(
        padding: kPagePadding,
        children: [
          PageHeader(
            title: 'School solarisation programme',
            subtitle: '${Fmt.int_(d.solarized)} of ${Fmt.int_(d.publicSchools)} public schools solarised · ${Fmt.int_(d.connected)} connected · ${Fmt.int_(d.monitored)} monitored plants · dataset from MEHE/UNICEF workbooks',
            actions: [
              OutlinedButton.icon(onPressed: () => goTo(context, stationsRoute()), icon: const Icon(Icons.list_alt_outlined, size: 18), label: const Text('Plants')),
            ],
          ),
          if (d.publicSchools == 0)
            const Padding(
              padding: EdgeInsets.only(bottom: kGap),
              child: MutedNote('The school dataset has not been imported yet; programme figures appear once it is.'),
            ),
          ProgrammeKpiGrid(insights: d),
          const SizedBox(height: kGap),
          CoverageByRegionCard(insights: d),
          const SizedBox(height: kGap),
          TwoColumn(left: SolarStatusCard(insights: d), right: FundingCard(insights: d)),
          const SizedBox(height: kGap),
          EnergyAuditCard(insights: d),
          const SizedBox(height: kGap),
          ProgrammeAttentionLists(insights: d),
          const SizedBox(height: kGap),
          MeasuredVsAuditedCard(insights: d),
          const SizedBox(height: kGap),
          EducationCard(insights: d),
          const SizedBox(height: kGap),
          LinksCard(insights: d),
          const SizedBox(height: kGap),
          MutedNote(
            'Dataset${version == null ? '' : ' v$version'}${generated == null ? '' : ' generated $generated'}: MEHE public school master list, internet-connectivity roll-out, UNICEF solar implementation tracker, '
            'MEHE energy audit (annual loads and equipment inventory) and MEHE education dashboard (attendance and risk). '
            'Expected generation = installed kWp × specific yield (Settings, default 1,500 kWh/kWp/yr). '
            'Plant ↔ school links are automatic (name + coordinates) unless set by hand. Pull down to synchronise the fleet.',
          ),
        ],
      ),
    );
  }
}
