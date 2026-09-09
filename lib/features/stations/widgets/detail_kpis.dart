import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';

/// KPI tiles of one school (today energy, yields, availability, battery, grid).
class DetailKpis extends StatelessWidget {
  const DetailKpis({super.key, required this.latest, required this.insight});

  final StationLatest? latest;
  final StationInsight? insight;

  @override
  Widget build(BuildContext context) {
    final today = latest?.today ?? TodayEnergy.empty;
    final i = insight;
    final gen = today.generationKwh ?? i?.todayGenKwh;
    final cons = today.consumptionKwh ?? i?.todayConsKwh;
    final imp = today.gridImportKwh ?? i?.todayImportKwh;
    final exp = today.gridExportKwh ?? i?.todayExportKwh;
    final asOf = latest?.dataTs == null ? null : 'as of ${Fmt.time(latest!.dataTs)}';
    final pr = i?.performanceRatio7d;
    final prColor = pr == null ? null : (pr < 0.5 ? AppColors.serious : (pr < 0.8 ? AppColors.warning : AppColors.good));
    final av30 = i?.availability30d;
    final soc = i?.hoursBelow20Today;
    return TileGrid(
      minTileWidth: 170,
      aspect: 1.75,
      children: [
        KpiTile(label: 'Generation today', value: Fmt.energy(gen), hint: asOf, icon: Icons.wb_sunny_outlined, color: AppColors.pv),
        KpiTile(label: 'Consumption today', value: Fmt.energy(cons), hint: asOf, icon: Icons.lightbulb_outline, color: AppColors.load),
        KpiTile(label: 'Grid import today', value: Fmt.energy(imp), hint: asOf, icon: Icons.south_west, color: AppColors.gridImport),
        KpiTile(label: 'Grid export today', value: Fmt.energy(exp), hint: asOf, icon: Icons.north_east, color: AppColors.gridExport),
        KpiTile(label: 'Yield today so far', value: i?.yieldTodaySoFar == null ? '–' : '${Fmt.two(i!.yieldTodaySoFar)} kWh/kWp', hint: 'not comparable before sunset', icon: Icons.speed),
        KpiTile(
          label: 'Yield 7 d',
          value: i?.yield7d == null ? '–' : '${Fmt.two(i!.yield7d)} kWh/kWp/d',
          hint: i?.peerMedianYield7d == null ? 'peer median n/a' : 'peer median ${Fmt.two(i!.peerMedianYield7d)} · PR ${Fmt.two(pr)}${i.isUnderPerformer ? ' · under-performing' : ''}',
          icon: pr != null && pr < 0.5 ? Icons.trending_down : Icons.trending_up,
          color: prColor,
        ),
        KpiTile(label: 'Self-sufficiency 7 d', value: Fmt.ratio(i?.selfSufficiency7d), hint: 'share of consumption not bought', icon: Icons.pie_chart_outline),
        KpiTile(
          label: 'Availability 30 d',
          value: Fmt.ratio(av30, decimals: 1),
          hint: i == null ? null : '${i.outages30d} outage${i.outages30d == 1 ? '' : 's'} · 7 d ${Fmt.ratio(i.availability7d, decimals: 1)}',
          icon: Icons.timeline,
          color: av30 == null ? null : (av30 < 0.9 ? AppColors.serious : AppColors.good),
        ),
        KpiTile(
          label: 'Outages 30 d',
          value: i == null ? '–' : '${i.outages30d}',
          hint: i?.currentOutage == null ? 'not down now' : 'down for ${Fmt.duration(i!.currentOutage)}',
          icon: Icons.cloud_off_outlined,
          color: i?.currentOutage == null ? null : AppColors.offline,
        ),
        KpiTile(
          label: 'Hours < 20 % SOC today',
          value: soc == null ? '–' : '${Fmt.one(soc)} h',
          hint: i?.socMinToday == null ? 'no battery samples' : 'min SOC ${Fmt.percent(i!.socMinToday)} · now ${Fmt.percent(i.socNow)}',
          icon: Icons.battery_alert_outlined,
          color: soc != null && soc > 0 ? AppColors.warning : null,
        ),
        KpiTile(
          label: 'Grid hours today',
          value: i?.gridHoursToday == null ? '–' : '${Fmt.one(i!.gridHoursToday)} h',
          hint: 'EDL present (voltage/frequency)',
          icon: Icons.power_outlined,
        ),
        KpiTile(
          label: 'Data completeness 7 d',
          value: Fmt.percent(i?.completeness7d),
          hint: i == null ? null : '${i.daysWithData7d} of 7 days with data',
          icon: Icons.fact_check_outlined,
          color: i?.completeness7d != null && i!.completeness7d! < 80 ? AppColors.warning : null,
        ),
      ],
    );
  }
}
