import 'package:flutter/material.dart';

import '../../../core/models/alert.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Stat tiles at the top of the dashboard.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final p = ChartPalette.of(context);
    final reporting = i.reportingStations;
    final high = i.activeAlertsByLevel[AlertLevel.high] ?? 0;
    final medium = i.activeAlertsByLevel[AlertLevel.medium] ?? 0;
    final low = i.activeAlertsByLevel[AlertLevel.low] ?? 0;
    final dieselToday = i.today.selfConsumedKwh * i.dieselLitresPerKwh;
    final noLive = reporting == 0;

    String live(double w) => noLive ? '–' : Fmt.power(w);

    return TileGrid(
      minTileWidth: 196,
      aspect: 1.85,
      children: [
        KpiTile(
          label: 'Schools',
          value: Fmt.int_(i.totalStations),
          icon: Icons.school_outlined,
          hint: '${i.count(StationStatus.online)} online · ${i.count(StationStatus.offline)} offline · ${i.count(StationStatus.alarm)} alarm · ${i.count(StationStatus.stale)} stale',
          onTap: () => goTo(context, stationsRoute()),
        ),
        KpiTile(
          label: 'Generation now',
          value: live(i.generationNowW),
          icon: Icons.wb_sunny_outlined,
          color: p.pv,
          hint: noLive ? 'No plant reporting' : '${Fmt.ratio(i.capacityUtilisation)} of ${Fmt.capacity(i.reportingKwp)} reporting',
        ),
        KpiTile(
          label: 'Consumption now',
          value: live(i.consumptionNowW),
          icon: Icons.bolt_outlined,
          color: p.load,
          hint: noLive ? 'No plant reporting' : 'Σ over $reporting of ${i.totalStations} plants',
        ),
        KpiTile(
          label: 'Grid import now',
          value: live(i.importNowW),
          icon: Icons.electrical_services_outlined,
          color: p.gridImport,
          hint: 'Export now: ${live(i.exportNowW)}',
        ),
        KpiTile(
          label: 'Battery',
          value: i.socMedian == null ? '–' : '${Fmt.percent(i.socMedian)} SOC',
          icon: Icons.battery_charging_full_outlined,
          color: p.battery,
          hint: noLive ? 'No plant reporting' : 'Median · charging ${Fmt.power(i.chargeNowW)} · discharging ${Fmt.power(i.dischargeNowW)}',
        ),
        KpiTile(
          label: "Today's generation",
          value: Fmt.energy(i.today.generationKwh),
          icon: Icons.today_outlined,
          color: p.pv,
          hint: i.dataTsMax == null ? 'No data yet' : 'as of ${Fmt.time(i.dataTsMax)} · ${i.today.stations} plants',
        ),
        KpiTile(
          label: 'Self-sufficiency',
          value: i.selfSufficiencyToday == null ? 'n/a' : Fmt.ratio(i.selfSufficiencyToday),
          icon: Icons.donut_large_outlined,
          hint: 'Today · 7 d: ${i.selfSufficiency7d == null ? 'n/a' : Fmt.ratio(i.selfSufficiency7d)}',
        ),
        KpiTile(
          label: 'CO₂ avoided 30 d',
          value: Fmt.co2(i.co2Avoided30dKg),
          icon: Icons.eco_outlined,
          color: AppColors.good,
          hint: '${Fmt.litres(i.dieselAvoided30dL)} diesel avoided · today ${Fmt.litres(dieselToday)}',
        ),
        KpiTile(
          label: 'Availability 7 d',
          value: i.availability7d == null ? 'n/a' : Fmt.ratio(i.availability7d, decimals: 1),
          icon: Icons.verified_outlined,
          hint: '${Fmt.int_(i.outages7d)} outages · MTTR ${i.outageMttrMedianSeconds == null ? '–' : Fmt.duration(Duration(seconds: i.outageMttrMedianSeconds!.round()))}',
        ),
        KpiTile(
          label: 'Active alarms',
          value: Fmt.int_(i.activeAlerts),
          icon: Icons.notifications_active_outlined,
          color: high > 0 ? AppColors.levelHigh : (medium > 0 ? AppColors.levelMedium : null),
          hint: '$high high · $medium medium · $low low',
          onTap: () => goTo(context, '/alarms'),
        ),
      ],
    );
  }
}
