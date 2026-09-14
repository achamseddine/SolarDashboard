import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/education_insights.dart';
import '../../core/models/school.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../common/charts.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import '../programme/widgets/coverage_card.dart' show shortRegion;

/// Colour of a risk level, shared by the student and teacher cards.
Color riskColor(RiskLevel level) => switch (level) {
      RiskLevel.low => AppColors.good,
      RiskLevel.medium => AppColors.warning,
      RiskLevel.high => AppColors.critical,
    };

/// Student and teacher indicators of the public schools, from the MEHE
/// education dashboard extract bundled with the app.
class EducationScreen extends ConsumerWidget {
  const EducationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(educationInsightsProvider);
    return AsyncView<EducationInsights>(
      value: insights,
      emptyWhen: (d) => d.schools == 0,
      emptyMessage: 'The school dataset has not been imported yet.',
      builder: (d) => ListView(
        padding: kPagePadding,
        children: [
          PageHeader(
            title: 'Students and teachers',
            subtitle: '${Fmt.int_(d.schools)} public schools · ${Fmt.int_(d.secondShiftSchools)} with an afternoon shift · ${Fmt.int_(d.teachers)} afternoon-shift teachers',
            actions: [
              OutlinedButton.icon(
                onPressed: () => goTo(context, '/schools'),
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Schools'),
              ),
            ],
          ),
          _StudentSection(insights: d),
          const SizedBox(height: kGap),
          _TeacherSection(insights: d),
          const SizedBox(height: kGap),
          _ByRegionCard(insights: d),
          const SizedBox(height: kGap),
          MutedNote(
            'Source: the MEHE education dashboard extract (attendance, risk levels, afternoon-shift teaching staff) bundled with the app, joined with the public school master list. '
            'Attendance is the share of enrolled students present; AM is the morning shift, PM the afternoon shift. '
            '${d.hasAbsenceRates ? '' : 'The "10 or more days of non-justified absences" columns are empty in this extract, so they are not shown. '}'
            'Risk levels come from third-party verification and only a minority of schools carry one.',
          ),
        ],
      ),
    );
  }
}

class _StudentSection extends StatelessWidget {
  const _StudentSection({required this.insights});
  final EducationInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    return SectionCard(
      title: 'Students',
      subtitle: 'Attendance and risk rating by shift',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileGrid(
            minTileWidth: 210,
            tileHeight: 122,
            children: [
              KpiTile(
                label: 'Morning attendance',
                value: Fmt.ratio(d.amAttendance, decimals: 1),
                icon: Icons.wb_twilight,
                color: AppColors.unicefCyan,
                hint: '${Fmt.int_(d.amSchools)} schools · ${Fmt.ratio(d.amAttendanceWeighted, decimals: 1)} weighted by students',
              ),
              KpiTile(
                label: 'Afternoon attendance',
                value: Fmt.ratio(d.pmAttendance, decimals: 1),
                icon: Icons.nightlight_outlined,
                color: AppColors.gridExport,
                hint: d.pmSchools == 0 ? 'No afternoon shift in the extract' : '${Fmt.int_(d.pmSchools)} schools · ${Fmt.ratio(d.pmAttendanceWeighted, decimals: 1)} weighted',
              ),
              KpiTile(
                label: 'Second-shift schools',
                value: Fmt.int_(d.secondShiftSchools),
                icon: Icons.groups_2_outlined,
                hint: '${Fmt.ratio(d.secondShiftShare)} of public schools',
                onTap: () => goTo(context, '/schools'),
              ),
              KpiTile(
                label: 'Attendance submitted',
                value: '${Fmt.int_(d.amSubmitted)} AM · ${Fmt.int_(d.pmSubmitted)} PM',
                icon: Icons.fact_check_outlined,
                hint: 'Schools that reported attendance data',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TwoColumn(
            left: _RiskBlock(title: 'Morning risk rating', counts: d.studentRiskAm, rated: d.riskRatedAm, total: d.schools),
            right: _RiskBlock(title: 'Afternoon risk rating', counts: d.studentRiskPm, rated: d.riskRatedPm, total: d.secondShiftSchools),
          ),
          const MutedNote('Risk ratings come from the discrepancy between school logbooks and the education information system, as verified by a third party.'),
        ],
      ),
    );
  }
}

class _TeacherSection extends StatelessWidget {
  const _TeacherSection({required this.insights});
  final EducationInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final terms = d.teacherTerms;
    return SectionCard(
      title: 'Afternoon-shift teachers',
      subtitle: '${Fmt.int_(d.teacherSchools)} schools report special-contract teaching staff',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileGrid(
            minTileWidth: 210,
            tileHeight: 122,
            children: [
              KpiTile(
                label: 'Teachers',
                value: Fmt.int_(d.teachers),
                icon: Icons.person_outline,
                color: AppColors.unicefCyan,
                hint: '${Fmt.int_(d.femaleTeachers)} female · ${Fmt.int_(d.maleTeachers)} male',
              ),
              KpiTile(
                label: 'Female share',
                value: Fmt.ratio(d.femaleShare),
                icon: Icons.female_outlined,
                color: AppColors.battery,
                hint: 'Of all afternoon-shift teachers',
              ),
              KpiTile(
                label: 'Students per teacher',
                value: Fmt.two(d.studentTeacherRatio),
                icon: Icons.groups_outlined,
                hint: 'Mean over ${Fmt.int_(d.teacherSchools)} schools',
              ),
              KpiTile(
                label: 'Teaching days',
                value: d.teachingDays == null ? '–' : Fmt.int_(d.teachingDays!.round()),
                icon: Icons.event_available_outlined,
                hint: 'Mean total teaching days',
              ),
              KpiTile(
                label: 'Visited by a third party',
                value: Fmt.int_(d.visitedThirdParty),
                icon: Icons.how_to_reg_outlined,
                hint: '${Fmt.ratio(d.visitedShare)} of schools · verification visits',
              ),
              KpiTile(
                label: 'High-risk teacher records',
                value: Fmt.int_(d.highRiskTeachers),
                icon: Icons.report_gmailerrorred_outlined,
                color: d.highRiskTeachers > 0 ? AppColors.critical : AppColors.muted,
                hint: '${Fmt.int_(d.riskRatedTeachers)} schools rated',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TwoColumn(
            leftFlex: 3,
            rightFlex: 2,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Teachers with attendance reported, by term', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (terms.every((t) => t == 0))
                  const MutedNote('No term attendance in this extract.')
                else
                  EnergyBarChart(
                    height: 200,
                    seriesLabels: const ['Teachers reported'],
                    seriesColors: const [AppColors.unicefCyan],
                    unitFormatter: Fmt.int_,
                    showLegend: false,
                    groups: [
                      for (var i = 0; i < terms.length; i++)
                        BarGroup(label: 'Term ${i + 1}', fullLabel: 'Term ${i + 1} · ${Fmt.int_(terms[i])} of ${Fmt.int_(d.teachers)} teachers', values: [terms[i].toDouble()]),
                    ],
                  ),
                if (d.termReportingShare != null) MutedNote('On average ${Fmt.ratio(d.termReportingShare)} of the ${Fmt.int_(d.teachers)} teachers were reported per term.'),
              ],
            ),
            right: _RiskBlock(title: 'Teacher risk rating', counts: d.teacherRisk, rated: d.riskRatedTeachers, total: d.teacherSchools),
          ),
        ],
      ),
    );
  }
}

/// Risk-level distribution with the unrated remainder made explicit.
class _RiskBlock extends StatelessWidget {
  const _RiskBlock({required this.title, required this.counts, required this.rated, required this.total});

  final String title;
  final Map<RiskLevel, int> counts;
  final int rated;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (rated == 0)
          Text('No school in this group carries a risk rating.', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
        else ...[
          for (final level in RiskLevel.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: riskColor(level), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(level.label, style: t.bodyMedium)),
                  Text(Fmt.int_(counts[level] ?? 0), style: t.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text('${Fmt.int_(rated)} of ${Fmt.int_(total)} schools rated', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// Schools, shifts, attendance and teachers per governorate.
class _ByRegionCard extends StatelessWidget {
  const _ByRegionCard({required this.insights});
  final EducationInsights insights;

  @override
  Widget build(BuildContext context) {
    final regions = insights.byRegion;
    return SectionCard(
      title: 'By governorate',
      subtitle: 'Schools, afternoon shifts, attendance and teaching staff',
      child: regions.isEmpty
          ? const MutedNote('No education data in the dataset.')
          : TwoColumn(
              leftFlex: 3,
              rightFlex: 2,
              left: EnergyBarChart(
                height: 240,
                stacked: true,
                seriesLabels: const ['Morning only', 'Also afternoon'],
                seriesColors: const [AppColors.unicefCyan, AppColors.gridExport],
                unitFormatter: Fmt.int_,
                groups: [
                  for (final r in regions)
                    BarGroup(
                      label: shortRegion(r.name),
                      fullLabel: '${r.name} · ${Fmt.int_(r.schools)} schools · ${Fmt.int_(r.teachers)} PM teachers',
                      values: [(r.schools - r.secondShiftSchools).toDouble(), r.secondShiftSchools.toDouble()],
                    ),
                ],
              ),
              right: ChartTable(
                columns: const ['Governorate', 'Schools', 'AM', 'PM'],
                rows: [
                  for (final r in regions)
                    [r.name, Fmt.int_(r.schools), Fmt.ratio(r.amAttendance), r.pmAttendance == null ? '–' : Fmt.ratio(r.pmAttendance)],
                ],
              ),
            ),
    );
  }
}
