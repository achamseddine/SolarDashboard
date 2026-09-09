import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Generation vs consumption over the current day, fleet-wide.
class GenerationVsConsumptionCard extends ConsumerWidget {
  const GenerationVsConsumptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(powerBucketsProvider(('', 24)));
    final p = ChartPalette.of(context);
    final data = [...?buckets.value]..sort((a, b) => a.bucketTs.compareTo(b.bucketTs));
    final usable = data.length >= 2;
    return ChartOrTable(
      title: 'Generation vs consumption today',
      subtitle: usable ? 'All schools · 15-min buckets · ${Fmt.time(data.first.bucketTs)}–${Fmt.time(data.last.bucketTs)}' : 'All schools · 15-min buckets',
      chart: usable
          ? PowerLineChart(
              height: 260,
              series: [
                TimeSeries(label: 'Generation', color: p.pv, area: true, points: [for (final b in data) (b.bucketTs, b.generationW)]),
                TimeSeries(label: 'Consumption', color: p.load, points: [for (final b in data) (b.bucketTs, b.consumptionW)]),
                TimeSeries(label: 'Grid import', color: p.gridImport, points: [for (final b in data) (b.bucketTs, b.gridImportW)]),
              ],
            )
          : const SizedBox(height: 260, child: EmptyState(message: 'The curve appears after the first synchronisation.', icon: Icons.show_chart)),
      table: ChartTable(
        columns: const ['Time', 'Generation', 'Consumption', 'Grid import', 'Schools'],
        rows: [for (final b in data.reversed) [Fmt.time(b.bucketTs), Fmt.power(b.generationW), Fmt.power(b.consumptionW), Fmt.power(b.gridImportW), Fmt.int_(b.stationsReporting)]],
      ),
    );
  }
}

/// Energy balance for today / 7 days / 30 days.
class EnergyBalanceCard extends StatelessWidget {
  const EnergyBalanceCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final i = insights;
    final periods = [('Today', i.today), ('7 days', i.last7d), ('30 days', i.last30d)];
    return ChartOrTable(
      title: 'Energy balance',
      subtitle: 'Generated vs consumed vs bought from the grid, all schools',
      chart: EnergyBarChart(
        height: 220,
        seriesLabels: const ['Generation', 'Consumption', 'Grid import'],
        seriesColors: [p.pv, p.load, p.gridImport],
        groups: [for (final e in periods) BarGroup(label: e.$1, values: [e.$2.generationKwh, e.$2.consumptionKwh, e.$2.gridImportKwh])],
        maxLabels: 3,
      ),
      table: ChartTable(
        columns: const ['Period', 'Generation', 'Consumption', 'Grid import', 'Grid export', 'Self-sufficiency'],
        rows: [for (final e in periods) [e.$1, Fmt.energy(e.$2.generationKwh), Fmt.energy(e.$2.consumptionKwh), Fmt.energy(e.$2.gridImportKwh), Fmt.energy(e.$2.gridExportKwh), e.$2.selfSufficiency == null ? 'n/a' : Fmt.ratio(e.$2.selfSufficiency)]],
      ),
    );
  }
}

/// Monthly carbon avoided over the last 12 months.
class CarbonByMonthCard extends StatelessWidget {
  const CarbonByMonthCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final months = i.monthlySeries12m;
    final kgs = [for (final m in months) m.selfConsumedKwh * i.co2FactorKgPerKwh];
    final total = kgs.fold(0.0, (a, b) => a + b);
    return ChartOrTable(
      title: 'Carbon footprint avoided by month',
      subtitle: '${Fmt.co2(total)} over the last ${months.length} months · self-consumed solar × ${i.co2FactorKgPerKwh.toStringAsFixed(2)} kg/kWh',
      chart: EnergyBarChart(
        height: 220,
        seriesLabels: const ['CO₂ avoided'],
        seriesColors: const [AppColors.good],
        groups: [for (var k = 0; k < months.length; k++) BarGroup(label: Fmt.monthLabel(months[k].day).split(' ').first, fullLabel: Fmt.monthLabel(months[k].day), values: [kgs[k]])],
        unitFormatter: (v) => Fmt.co2(v),
        showLegend: false,
        maxLabels: 12,
      ),
      table: ChartTable(
        columns: const ['Month', 'Self-consumed solar', 'CO₂ avoided', 'Diesel avoided'],
        rows: [
          for (var k = months.length - 1; k >= 0; k--)
            [Fmt.monthLabel(months[k].day), Fmt.energy(months[k].selfConsumedKwh), Fmt.co2(kgs[k]), Fmt.litres(months[k].selfConsumedKwh * i.dieselLitresPerKwh)],
        ],
      ),
    );
  }
}

/// Fleet health strip: status counts, alarms, availability, links.
class FleetHealthCard extends StatelessWidget {
  const FleetHealthCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Fleet health',
      subtitle: '${i.totalStations} schools · availability 7 d ${i.availability7d == null ? 'n/a' : Fmt.ratio(i.availability7d, decimals: 1)} · ${i.activeAlerts} active alarms',
      trailing: SeeAllButton(location: '/analytics', label: 'Analytics'),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in StationStatus.values)
            if (i.count(s) > 0)
              ActionChip(
                avatar: Icon(AppColors.stationStatusIcon(s), size: 16, color: AppColors.stationStatus(s)),
                label: Text('${s.label} ${i.count(s)}'),
                onPressed: () => goTo(context, stationsRoute(status: s.name)),
              ),
          ActionChip(
            avatar: Icon(Icons.notifications_active_outlined, size: 16, color: i.activeAlerts > 0 ? AppColors.alarm : null),
            label: Text('Alarms ${i.activeAlerts}'),
            onPressed: () => goTo(context, '/alarms'),
          ),
          if (i.underPerformers.isNotEmpty)
            ActionChip(avatar: const Icon(Icons.trending_down, size: 16, color: AppColors.serious), label: Text('Under-performing ${i.underPerformers.length}'), onPressed: () => goTo(context, stationsRoute(filter: 'underperforming'))),
          if (i.lowSocStations.isNotEmpty)
            ActionChip(avatar: const Icon(Icons.battery_alert_outlined, size: 16, color: AppColors.warning), label: Text('Low battery ${i.lowSocStations.length}'), onPressed: () => goTo(context, stationsRoute(filter: 'lowsoc'))),
          ActionChip(avatar: const Icon(Icons.map_outlined, size: 16), label: Text('Map', style: t.labelLarge), onPressed: () => goTo(context, '/map')),
        ],
      ),
    );
  }
}

/// Generation now per governorate (single hue, sorted).
class RegionGenerationCard extends StatelessWidget {
  const RegionGenerationCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final regions = [...insights.regions]..sort((a, b) => b.todayGenKwh.compareTo(a.todayGenKwh));
    return SectionCard(
      title: 'Generation today by governorate',
      subtitle: 'Tap a governorate to open its schools',
      child: HorizontalBars(
        items: [for (final r in regions) ('${r.name} (${r.stations})', r.todayGenKwh, null)],
        formatter: (v) => Fmt.energy(v),
        onTap: (k) => goTo(context, stationsRoute(region: regions[k].name)),
      ),
    );
  }
}
