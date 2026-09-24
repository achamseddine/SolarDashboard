import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'connectivity_common.dart';

/// Hero KPI grid of the connectivity page: the roll-out, the students it
/// reaches and what it means for the solar fleet.
class ConnectivityKpiGrid extends StatelessWidget {
  const ConnectivityKpiGrid({super.key, required this.insights});
  final ConnectivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final p = ChartPalette.of(context);
    final noPlants = d.monitored == 0;
    return TileGrid(
      minTileWidth: 200,
      tileHeight: 114,
      children: [
        KpiTile(
          label: 'Connected schools',
          value: Fmt.int_(d.connected),
          icon: Icons.wifi_outlined,
          color: AppColors.good,
          hint: '${Fmt.ratio(d.share)} of ${Fmt.int_(d.schools)} public schools',
          onTap: () => goTo(context, schoolsRoute(connected: true)),
        ),
        KpiTile(
          label: 'Schools without internet',
          value: Fmt.int_(d.notConnected),
          icon: Icons.wifi_off_outlined,
          color: AppColors.serious,
          hint: '${Fmt.int_(d.studentsWithout)} students',
          onTap: () => goTo(context, schoolsRoute(connected: false)),
        ),
        KpiTile(
          label: 'Students reached',
          value: Fmt.int_(d.connectedStudents),
          icon: Icons.groups_outlined,
          color: p.load,
          hint: '${Fmt.ratio(d.studentShare)} of enrolment',
          // The students are the enrolment of the connected schools, so the
          // list behind the figure is those schools.
          onTap: () => goTo(context, schoolsRoute(connected: true)),
        ),
        KpiTile(
          label: 'Solar + internet',
          value: Fmt.int_(d.quadrant(ConnectivityQuadrant.both)),
          icon: Icons.check_circle_outline,
          color: quadrantColor(ConnectivityQuadrant.both),
          hint: d.solarizedShare == null ? 'No solarised school in the dataset' : '${Fmt.ratio(d.solarizedShare)} of solarised schools',
          onTap: () => goTo(context, quadrantRoute(ConnectivityQuadrant.both)),
        ),
        KpiTile(
          label: 'Solarised without internet',
          value: Fmt.int_(d.quadrant(ConnectivityQuadrant.solarOnly)),
          icon: Icons.cloud_off_outlined,
          color: quadrantColor(ConnectivityQuadrant.solarOnly),
          hint: 'Logger may have no data path',
          onTap: () => goTo(context, quadrantRoute(ConnectivityQuadrant.solarOnly)),
        ),
        KpiTile(
          label: 'Monitored plants connected',
          value: noPlants ? '0' : '${Fmt.int_(d.monitoredConnected)} of ${Fmt.int_(d.monitored)}',
          icon: Icons.monitor_heart_outlined,
          color: noPlants ? AppColors.muted : AppColors.good,
          hint: noPlants ? 'No plant synced yet' : '${Fmt.ratio(d.monitoredShare)} of monitored plants',
          onTap: noPlants ? null : () => goTo(context, schoolsRoute(monitored: true)),
        ),
      ],
    );
  }
}
