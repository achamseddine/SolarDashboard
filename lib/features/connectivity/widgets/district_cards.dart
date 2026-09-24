import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'connectivity_common.dart';

/// The two district rankings: where the roll-out still has the most to do,
/// and where it is already finished.
class DistrictCards extends StatelessWidget {
  const DistrictCards({super.key, required this.insights});
  final ConnectivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final gaps = insights.topGaps;
    final best = insights.bestServed;
    return TwoColumn(
      left: _DistrictCard(
        title: 'Districts with the largest gap',
        subtitle: 'Most schools still waiting for an internet connection',
        emptyText: 'No district in the dataset',
        groups: gaps,
        color: AppColors.serious,
        trailing: (g) => Fmt.int_(g.notConnected),
        trailingHint: 'without internet',
        note: 'Tap a district to list its schools without internet.',
        route: (g) => schoolsRoute(caza: g.name, connected: false),
      ),
      right: _DistrictCard(
        title: 'Best served districts',
        subtitle: 'Highest share connected (districts with at least 5 schools)',
        emptyText: 'No district with at least 5 schools',
        groups: best,
        color: AppColors.good,
        trailing: (g) => Fmt.ratio(g.share),
        trailingHint: 'connected',
        // This ranking is about the share connected, so the row opens the
        // connected schools; sending it to the without-internet list shows
        // the opposite of the figure it was tapped on.
        note: 'Tap a district to list its connected schools. A finished district is where a next solar phase has a data path from day one.',
        route: (g) => schoolsRoute(caza: g.name, connected: true),
      ),
    );
  }
}

class _DistrictCard extends StatelessWidget {
  const _DistrictCard({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.groups,
    required this.color,
    required this.trailing,
    required this.trailingHint,
    required this.note,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<ConnectivityGroup> groups;
  final Color color;
  final String Function(ConnectivityGroup) trailing;
  final String trailingHint;
  final String note;

  /// Where one district's row leads — the list the ranking is about.
  final String Function(ConnectivityGroup) route;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(emptyText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ]),
            )
          else
            for (final g in groups)
              CompactRow(
                leading: Icon(Icons.location_city_outlined, size: 18, color: color),
                title: g.name,
                subtitle: '${Fmt.int_(g.connected)} of ${Fmt.int_(g.schools)} connected · ${Fmt.int_(g.studentsWithout)} students without',
                trailing: trailing(g),
                trailingHint: trailingHint,
                onTap: () => goTo(context, route(g)),
              ),
          MutedNote(note),
        ],
      ),
    );
  }
}
