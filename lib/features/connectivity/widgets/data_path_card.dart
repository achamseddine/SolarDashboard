import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import '../../programme/widgets/programme_common.dart';
import 'connectivity_common.dart';

const _maxRows = 10;

/// Monitored plants at schools that are not on the connectivity roll-out:
/// their logger has no official data path, so silence is expected rather
/// than alarming — and a real outage there stays invisible.
class DataPathCard extends StatelessWidget {
  const DataPathCard({super.key, required this.insights, this.programme});
  final ConnectivityInsights insights;

  /// Null while the programme insights are still loading.
  final SchoolInsights? programme;

  @override
  Widget build(BuildContext context) {
    final d = programme;
    final rows = <SchoolInsight>[];
    if (d != null) {
      final down = [for (final s in d.downWithoutConnectivity) if (s.isMonitored) s];
      final seen = {for (final s in down) s.cerd};
      rows
        ..addAll(down)
        ..addAll([for (final s in d.schools) if (s.isMonitored && !s.isConnected && !seen.contains(s.cerd)) s]);
    }
    final loading = d == null;
    return ProgrammeListCard(
      title: 'Plants without a data path',
      count: rows.length,
      // The header count exceeds the rows shown as soon as there are more
      // than ten; the whole list is one tap away rather than truncated in
      // silence.
      trailing: rows.isEmpty ? null : SeeAllButton(location: schoolsRoute(monitored: true, connected: false)),
      subtitle: 'Monitored plants at schools that are not on the internet roll-out',
      emptyText: loading
          ? 'Loading monitored plants…'
          : insights.monitored == 0
              ? 'No monitored plant synced yet'
              : 'Every monitored plant is at a connected school',
      emptyIcon: loading || insights.monitored == 0 ? Icons.info_outline : Icons.check_circle_outline,
      emptyColor: loading || insights.monitored == 0 ? AppColors.muted : AppColors.good,
      note: '${Fmt.int_(insights.downWithoutInternet)} of these plants are currently down. The roll-out list says nothing about a private connection a school may have arranged itself.',
      rows: [
        for (final s in rows.take(_maxRows))
          CompactRow(
            leading: StatusChip(s.station!.status, compact: true),
            title: s.name,
            subtitle: '${s.station!.name} · ${s.region} · not on the connectivity roll-out',
            trailing: Fmt.ago(s.station!.latest?.dataTs ?? s.station!.station.lastUpdateTs),
            trailingHint: 'last data',
            onTap: () => goTo(context, stationRoute(s.station!.id)),
          ),
      ],
    );
  }
}
