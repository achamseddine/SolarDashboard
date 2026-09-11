import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import 'programme_common.dart';

/// Hero KPI grid of the programme page.
class ProgrammeKpiGrid extends StatelessWidget {
  const ProgrammeKpiGrid({super.key, required this.insights});
  final SchoolInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final p = ChartPalette.of(context);
    final planned = d.byStatus[SolarStatus.planned] ?? 0;
    final onHold = d.byStatus[SolarStatus.onHold] ?? 0;
    final unfunded = d.byStatus[SolarStatus.unfunded] ?? 0;
    final noPlants = d.monitored == 0;
    return TileGrid(
      minTileWidth: 200,
      tileHeight: 96,
      children: [
        KpiTile(
          label: 'Public schools',
          value: Fmt.int_(d.publicSchools),
          icon: Icons.school_outlined,
          hint: '${Fmt.int_(d.students)} students enrolled',
        ),
        KpiTile(
          label: 'Solarised',
          value: Fmt.int_(d.solarized),
          icon: Icons.solar_power_outlined,
          color: AppColors.good,
          hint: '${Fmt.ratio(d.solarizedShare)} of public schools',
        ),
        KpiTile(
          label: 'Solar pipeline',
          value: Fmt.int_(d.pipeline),
          icon: Icons.pending_actions_outlined,
          color: AppColors.unicefCyan,
          hint: '$planned planned · $onHold on hold · $unfunded unfunded',
        ),
        KpiTile(
          label: 'Connected schools',
          value: Fmt.int_(d.connected),
          icon: Icons.wifi_outlined,
          color: p.load,
          hint: '${Fmt.ratio(d.connectedShare)} of public schools',
        ),
        KpiTile(
          label: 'Solar + connected',
          value: Fmt.int_(d.solarizedConnected),
          icon: Icons.link_outlined,
          hint: '${Fmt.int_(d.solarizedUnconnected)} solarised without connectivity',
        ),
        KpiTile(
          label: 'Monitored plants',
          value: noPlants ? '0' : '${Fmt.int_(d.monitored)} of ${Fmt.int_(d.solarized)}',
          icon: Icons.monitor_heart_outlined,
          color: noPlants ? AppColors.muted : AppColors.good,
          hint: noPlants ? 'No plant synced yet' : '${Fmt.int_(d.solarizedUnmonitored)} solarised without a plant',
        ),
        KpiTile(
          label: 'Installed capacity',
          value: Fmt.capacity(d.installedKwp),
          icon: Icons.bolt_outlined,
          color: p.pv,
          hint: '${Fmt.energy(d.batteryKwh)} battery · ${Fmt.power(d.inverterKw * 1000)} inverters',
        ),
        KpiTile(
          label: 'Investment',
          value: usd(d.investmentUsd),
          icon: Icons.payments_outlined,
          hint: d.costPerKwp == null ? 'No cost data in the tracker' : '${usd(d.costPerKwp)} per kWp · ${usd(d.costPerStudent)} per student',
        ),
        KpiTile(
          label: 'Students benefiting',
          value: Fmt.int_(d.studentsSolarized),
          icon: Icons.groups_outlined,
          color: p.battery,
          hint: d.kwpPerHundredStudents == null ? 'Enrolled in solarised schools' : '${Fmt.one(d.kwpPerHundredStudents)} kWp per 100 students',
        ),
      ],
    );
  }
}
