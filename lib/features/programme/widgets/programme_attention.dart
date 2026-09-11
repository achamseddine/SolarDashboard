import 'package:flutter/material.dart';

import '../../../core/models/school_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'programme_common.dart';

const _maxRows = 8;

/// The four programme triage lists.
class ProgrammeAttentionLists extends StatelessWidget {
  const ProgrammeAttentionLists({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final unmonitored = d.unmonitoredSolarized;
    final down = d.downWithoutConnectivity;
    final undersized = d.undersized;
    final candidates = d.solarCandidates;
    final p = ChartPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoColumn(
          left: ProgrammeListCard(
            title: 'Solarised but not monitored',
            count: unmonitored.length,
            emptyText: d.solarized == 0 ? 'No solarised school in the dataset' : 'Every solarised school has a linked plant',
            emptyIcon: d.solarized == 0 ? Icons.info_outline : Icons.check_circle_outline,
            emptyColor: d.solarized == 0 ? AppColors.muted : AppColors.good,
            note: d.monitored == 0 && d.solarized > 0
                ? 'No plant has been synced yet; links are created after the first synchronisation.'
                : 'Completed in the tracker, but no plant in the DeyeCloud account matches the school.',
            rows: [
              for (final s in unmonitored.take(_maxRows))
                CompactRow(
                  leading: const Icon(Icons.solar_power_outlined, size: 18, color: AppColors.muted),
                  title: s.name,
                  subtitle: '${s.region} · ${s.school.solar?.donorGroup ?? s.school.solar?.donor ?? 'donor n/a'} · ${s.students == null ? '–' : Fmt.int_(s.students)} students',
                  trailing: Fmt.capacity(s.kwp),
                  trailingHint: 'installed',
                ),
            ],
          ),
          right: ProgrammeListCard(
            title: 'Plants down at schools without connectivity',
            count: down.length,
            trailing: SeeAllButton(location: stationsRoute(status: StationStatus.offline.name)),
            emptyText: d.monitored == 0 ? 'No monitored plant yet' : 'No plant down at a school without connectivity',
            emptyIcon: d.monitored == 0 ? Icons.info_outline : Icons.check_circle_outline,
            emptyColor: d.monitored == 0 ? AppColors.muted : AppColors.good,
            note: 'These schools are not on the internet-connectivity roll-out: the logger\'s internet link is a likely cause of the outage.',
            rows: [
              for (final s in down.take(_maxRows))
                CompactRow(
                  leading: Icon(AppColors.stationStatusIcon(s.station!.status), size: 18, color: AppColors.stationStatus(s.station!.status)),
                  title: s.name,
                  subtitle: '${s.station!.name} · ${s.region} · last data ${Fmt.ago(s.station!.latest?.dataTs ?? s.station!.station.lastUpdateTs)}',
                  trailing: s.station!.status.label,
                  trailingHint: s.station!.currentOutage == null ? 'plant status' : 'for ${Fmt.duration(s.station!.currentOutage)}',
                  onTap: () => goTo(context, stationRoute(s.station!.id)),
                ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        TwoColumn(
          left: ProgrammeListCard(
            title: 'Undersized systems',
            count: undersized.length,
            emptyText: d.solarizedAuditCount == 0 ? 'No solarised school with an energy audit' : 'No solarised school below 60 % of its audited load',
            emptyIcon: d.solarizedAuditCount == 0 ? Icons.info_outline : Icons.check_circle_outline,
            emptyColor: d.solarizedAuditCount == 0 ? AppColors.muted : AppColors.good,
            note: 'Expected generation (kWp × specific yield) below 60 % of the audited annual load.',
            rows: [
              for (final s in undersized.take(_maxRows))
                CompactRow(
                  leading: const Icon(Icons.trending_down, size: 18, color: AppColors.serious),
                  title: s.name,
                  subtitle: '${s.region} · load ${Fmt.energy(s.annualLoadKwh)}/yr · ${Fmt.capacity(s.kwp)} installed',
                  trailing: Fmt.ratio(s.sizingRatio),
                  trailingHint: 'of audited load',
                  onTap: s.station == null ? null : () => goTo(context, stationRoute(s.station!.id)),
                ),
            ],
          ),
          right: ProgrammeListCard(
            title: 'Next candidates for solarisation',
            count: candidates.length,
            subtitle: 'highest audited loads first',
            emptyText: 'No audited school outside the programme',
            emptyIcon: Icons.info_outline,
            emptyColor: AppColors.muted,
            note: 'Public schools not in the solar tracker, ranked by audited annual load.',
            rows: [
              for (final s in candidates.take(_maxRows))
                CompactRow(
                  leading: Icon(Icons.wb_sunny_outlined, size: 18, color: p.pv),
                  title: s.name,
                  subtitle: '${s.region} · ${s.students == null ? '–' : Fmt.int_(s.students)} students · ${s.isConnected ? 'connected' : 'not connected'}',
                  trailing: Fmt.energy(s.annualLoadKwh),
                  trailingHint: 'audited load / yr',
                ),
            ],
          ),
        ),
      ],
    );
  }
}
