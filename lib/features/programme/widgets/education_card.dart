import 'package:flutter/material.dart';

import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Attendance and risk indicators compared between groups of schools.
class EducationCard extends StatelessWidget {
  const EducationCard({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  Widget build(BuildContext context) {
    final comparisons = [for (final c in insights.attendance) if (c.countA + c.countB > 0) c];
    return SectionCard(
      title: 'Education indicators',
      subtitle: 'Mean attendance and schools at high risk, by group (MEHE education dashboard)',
      child: comparisons.isEmpty
          ? const SizedBox(height: 120, child: EmptyState(message: 'No education indicators in the dataset', icon: Icons.school_outlined))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < comparisons.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _ComparisonRow(comparison: comparisons[i]),
                ],
                const MutedNote('Attendance = share of enrolled students present (AM = morning shift, PM = afternoon shift). The groups differ in size, location and context: a gap is not evidence that solar or connectivity caused it — correlation is not causation.'),
              ],
            ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.comparison});
  final AttendanceComparison comparison;

  static final _pattern = RegExp(r'^(.*?) vs (.*?)(?: \((AM|PM)\))?$');

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    final m = _pattern.firstMatch(c.label);
    final nameA = _capitalise(m?.group(1) ?? 'Group A');
    final nameB = _capitalise(m?.group(2) ?? 'Group B');
    final shift = m?.group(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shift == null ? c.label : '$nameA vs ${nameB.toLowerCase()} · $shift shift', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _GroupMeter(name: nameA, mean: c.meanA, count: c.countA, highRisk: c.highRiskA, color: p.load)),
            const SizedBox(width: 20),
            Expanded(child: _GroupMeter(name: nameB, mean: c.meanB, count: c.countB, highRisk: c.highRiskB, color: p.battery)),
          ],
        ),
      ],
    );
  }
}

class _GroupMeter extends StatelessWidget {
  const _GroupMeter({required this.name, required this.mean, required this.count, required this.highRisk, required this.color});
  final String name;
  final double? mean;
  final int count;
  final int highRisk;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final none = mean == null || count == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(none ? '–' : Fmt.ratio(mean, decimals: 1), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 4),
        RatioMeter(value: none ? 0 : mean!, color: none ? AppColors.muted : color),
        const SizedBox(height: 2),
        Text(
          none ? 'No school with attendance data' : '${Fmt.int_(count)} school${count == 1 ? '' : 's'} · ${Fmt.int_(highRisk)} at high risk',
          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
