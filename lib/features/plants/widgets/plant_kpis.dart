import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';

/// The five figures of the DeyeCloud overview strip, in the app's own style:
/// live power, installed capacity, today, this month, lifetime.
class PlantKpiStrip extends StatelessWidget {
  const PlantKpiStrip({super.key, required this.insights});

  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final month = Fmt.month(i.generatedAt);
    return TileGrid(
      tileHeight: 120,
      children: [
        KpiTile(
          label: 'Real-time generating power',
          value: Fmt.power(i.generationNowW),
          hint: '${Fmt.int_(i.reportingStations)} of ${Fmt.int_(i.totalStations)} plants reporting',
          icon: Icons.bolt,
          color: AppColors.pv,
        ),
        KpiTile(
          label: 'Installed capacity',
          value: Fmt.capacity(i.installedKwp),
          hint: '${Fmt.int_(i.totalStations)} plants',
          icon: Icons.solar_power_outlined,
          color: AppColors.unicefCyan,
        ),
        KpiTile(
          label: 'Daily production',
          value: Fmt.energy(i.today.generationKwh),
          hint: 'today, from the plants that reported',
          icon: Icons.today_outlined,
          color: AppColors.good,
        ),
        KpiTile(
          label: 'Monthly production',
          value: Fmt.energy(i.monthGenerationKwh),
          hint: month,
          icon: Icons.calendar_month_outlined,
          color: AppColors.load,
        ),
        KpiTile(
          label: 'Total production',
          value: Fmt.energy(i.lifetime.generationKwh),
          hint: 'since commissioning',
          icon: Icons.insights_outlined,
          color: AppColors.battery,
        ),
      ],
    );
  }
}
