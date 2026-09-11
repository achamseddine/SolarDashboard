import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'programme_common.dart';

/// Donut of public schools by programme status.
class SolarStatusCard extends StatelessWidget {
  const SolarStatusCard({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  Widget build(BuildContext context) {
    final by = insights.byStatus;
    final total = by.values.fold(0, (a, b) => a + b);
    return SectionCard(
      title: 'Solar status',
      subtitle: 'Public schools by programme status',
      child: total == 0
          ? const SizedBox(height: 170, child: EmptyState(message: 'No school dataset imported yet', icon: Icons.donut_large_outlined))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DonutChart(
                  size: 170,
                  slices: [for (final s in SolarStatus.values) (s.label, (by[s] ?? 0).toDouble(), solarStatusColor(s))],
                  centerValue: Fmt.int_(total),
                  centerLabel: 'schools',
                ),
                const MutedNote('Status from the UNICEF solar implementation tracker; public schools absent from the tracker count as not solarised.'),
              ],
            ),
    );
  }
}

enum _SliceKind {
  donor('Donor', 'donor'),
  project('Project', 'project'),
  contractor('Contractor', 'contractor');

  const _SliceKind(this.label, this.noun);
  final String label;
  final String noun;
}

/// Installed kWp by donor / project / contractor with a toggle.
class FundingCard extends StatefulWidget {
  const FundingCard({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  State<FundingCard> createState() => _FundingCardState();
}

class _FundingCardState extends State<FundingCard> {
  static const _maxRows = 10;
  _SliceKind _kind = _SliceKind.donor;

  List<ProgrammeSlice> get _slices => switch (_kind) {
        _SliceKind.donor => widget.insights.byDonor,
        _SliceKind.project => widget.insights.byProject,
        _SliceKind.contractor => widget.insights.byContractor,
      };

  /// Top rows by kWp; the remainder folded into one "Other" row.
  List<ProgrammeSlice> _fold(List<ProgrammeSlice> all) {
    final sorted = [...all]..sort((a, b) => b.kwp.compareTo(a.kwp));
    if (sorted.length <= _maxRows) return sorted;
    var other = ProgrammeSlice(label: 'Other (${sorted.length - _maxRows + 1})');
    for (final s in sorted.skip(_maxRows - 1)) {
      other = other.add(schools: s.schools, kwp: s.kwp, costUsd: s.costUsd, students: s.students);
    }
    return [...sorted.take(_maxRows - 1), other];
  }

  @override
  Widget build(BuildContext context) {
    final all = _slices;
    final rows = _fold(all);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Funding',
      subtitle: all.isEmpty ? 'Installed kWp by ${_kind.noun}' : 'Installed kWp by ${_kind.noun} · ${all.length} ${_kind.noun}${all.length == 1 ? '' : 's'}',
      trailing: SegmentedButton<_SliceKind>(
        segments: [for (final k in _SliceKind.values) ButtonSegment(value: k, label: Text(k.label))],
        selected: {_kind},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
        onSelectionChanged: (s) => setState(() => _kind = s.first),
      ),
      child: rows.isEmpty
          ? const SizedBox(height: 170, child: EmptyState(message: 'No solarised school in the tracker yet', icon: Icons.bar_chart))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HorizontalBars(
                  items: [for (final s in rows) (s.label, s.kwp, null)],
                  color: AppColors.pv,
                  formatter: (v) => Fmt.capacity(v),
                  trailing: (i) => SizedBox(
                    width: 150,
                    child: Text(
                      '${Fmt.int_(rows[i].schools)} school${rows[i].schools == 1 ? '' : 's'} · ${usdCompact(rows[i].costUsd)}',
                      style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const MutedNote('Completed installations only, from the UNICEF solar implementation tracker (cost = installation cost recorded per school).'),
              ],
            ),
    );
  }
}
