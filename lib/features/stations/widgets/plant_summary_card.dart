import 'package:flutter/material.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Lifetime, today and month-to-date energy of one plant — the "Summary" and
/// "Daily Production" blocks of the DeyeCloud plant overview.
///
/// Accumulative figures come from the stored monthly counters, the daily ones
/// from today's row of the daily counters (the fleet insight is the fallback
/// while today's row has not been written yet).
class PlantSummaryCard extends StatelessWidget {
  const PlantSummaryCard({super.key, required this.detail});

  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final station = detail.station;
    final life = detail.lifetime;
    final month = detail.monthToDate;
    final today = AppTime.today(station.location);
    final todayRow = detail.daily.where((d) => d.period == today).firstOrNull;
    final genToday = todayRow?.generationKwh ?? detail.insight?.todayGenKwh;
    final consToday = todayRow?.consumptionKwh ?? detail.insight?.todayConsKwh;
    final since = station.startOperatingTs;
    // Today's row is written once the cloud returns the day; until then the
    // figure comes from the fleet insight, so the hint says where it is from.
    String dailyHint(double? v) => todayRow != null
        ? 'today, ${Fmt.shortDay(today)}'
        : v == null
            ? 'today, not counted yet'
            : 'today, from the live counters';
    final selfSufficiency = life.selfSufficiency;

    return SectionCard(
      title: 'Summary',
      subtitle: 'Accumulated, daily and month-to-date energy of this plant, as reported by the cloud counters',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileGrid(
            minTileWidth: 190,
            tileHeight: 120,
            children: [
              KpiTile(
                label: 'Accumulative production',
                value: _total(life.generationKwh),
                hint: since == null ? 'since commissioning' : 'since commissioning, ${Fmt.date(since)}',
                dense: true,
                icon: Icons.wb_sunny_outlined,
                color: p.pv,
              ),
              KpiTile(
                label: 'Accumulative consumption',
                value: _total(life.consumptionKwh),
                hint: 'since commissioning',
                dense: true,
                icon: Icons.lightbulb_outline,
                color: p.load,
              ),
              KpiTile(
                label: 'Daily production',
                value: Fmt.energy(genToday),
                hint: dailyHint(genToday),
                dense: true,
                icon: Icons.today_outlined,
                color: p.pv,
              ),
              KpiTile(
                label: 'Daily consumption',
                value: Fmt.energy(consToday),
                hint: dailyHint(consToday),
                dense: true,
                icon: Icons.bolt_outlined,
                color: p.load,
              ),
              KpiTile(
                label: 'This month',
                value: _total(month.generationKwh),
                hint: 'production, month to date',
                dense: true,
                icon: Icons.calendar_month_outlined,
                color: p.pv,
              ),
              KpiTile(
                label: 'Self-sufficiency',
                value: Fmt.ratio(selfSufficiency),
                hint: 'share of consumption not bought from the grid',
                dense: true,
                icon: Icons.pie_chart_outline,
                color: selfSufficiency == null ? null : p.battery,
              ),
            ],
          ),
          const MutedNote('Accumulative totals are the sum of the stored monthly counters, so they only reach as far back as the history the cloud returned. A figure the plant does not report is shown as "–", never as zero.'),
        ],
      ),
    );
  }

  /// Accumulated counters are non-nullable sums: a zero total means the plant
  /// reported nothing, so it prints as "–" rather than "0.0 kWh".
  static String _total(double kwh) => kwh <= 0 ? '–' : Fmt.energy(kwh);
}
