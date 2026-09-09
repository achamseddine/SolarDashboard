import 'package:flutter/material.dart';

import '../../../core/models/station.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/app_time.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';

/// Today's power curve of one plant with yesterday's PV as gray context.
class TodayPowerCard extends StatelessWidget {
  const TodayPowerCard({super.key, required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final loc = detail.station.location;
    final today = AppTime.today(loc);
    final start = AppTime.dayStart(today, loc);
    final end = AppTime.dayEnd(today, loc);
    final frames = detail.todayFrames;
    // Shift yesterday's frames by one day so they overlay today's axis.
    final yFrames = [for (final f in detail.yesterdayFrames) (f.ts + 86400, f.generationW)];
    final series = [
      TimeSeries(label: 'PV', color: p.pv, area: true, points: [for (final f in frames) if (f.generationW != null) (f.ts, f.generationW!)]),
      TimeSeries(label: 'Load', color: p.load, points: [for (final f in frames) if (f.consumptionW != null) (f.ts, f.consumptionW!)]),
      TimeSeries(label: 'Grid import', color: p.gridImport, points: [for (final f in frames) (f.ts, f.importW)]),
      TimeSeries(label: 'Grid export', color: p.gridExport, points: [for (final f in frames) (f.ts, f.exportW)]),
      TimeSeries(label: 'PV yesterday', color: p.deEmphasis, emphasis: false, points: [for (final y in yFrames) if (y.$2 != null) (y.$1, y.$2!)]),
    ];
    final battery = TimeSeries(label: 'Battery (+ charge / − discharge)', color: p.battery, points: [for (final f in frames) (f.ts, f.batteryNetW)]);
    final soc = TimeSeries(label: 'SOC', color: p.accent, points: [for (final f in frames) if (f.batterySoc != null) (f.ts, f.batterySoc!)]);
    return ChartOrTable(
      title: 'Today',
      subtitle: frames.isEmpty ? 'No intraday frames yet' : '${frames.length} readings · ${Fmt.time(frames.first.ts)}–${Fmt.time(frames.last.ts)} · yesterday shown in gray',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PowerLineChart(series: series, height: 240, xFrom: start, xTo: end),
          if (frames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Battery power and state of charge', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            PowerLineChart(series: [battery], height: 90, showLegend: false, xFrom: start, xTo: end),
            const SizedBox(height: 4),
            PowerLineChart(series: [soc], height: 90, showLegend: false, xFrom: start, xTo: end, minY: 0, maxY: 100, unitFormatter: (v) => Fmt.percent(v)),
          ],
        ],
      ),
      table: ChartTable(
        columns: const ['Time', 'PV', 'Load', 'Import', 'Export', 'Battery', 'SOC'],
        rows: [
          for (final f in frames.reversed)
            [Fmt.time(f.ts), Fmt.power(f.generationW), Fmt.power(f.consumptionW), Fmt.power(f.importW), Fmt.power(f.exportW), Fmt.power(f.batteryNetW, signed: true), Fmt.percent(f.batterySoc)],
        ],
      ),
    );
  }
}

/// 30-day daily energy of one plant.
class StationEnergy30dCard extends StatelessWidget {
  const StationEnergy30dCard({super.key, required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final days = detail.daily;
    final gen = days.fold(0.0, (a, d) => a + (d.generationKwh ?? 0));
    final cons = days.fold(0.0, (a, d) => a + (d.consumptionKwh ?? 0));
    final imp = days.fold(0.0, (a, d) => a + (d.gridImportKwh ?? 0));
    return ChartOrTable(
      title: 'Energy last 30 days',
      subtitle: 'Σ ${Fmt.energy(gen)} generated · ${Fmt.energy(cons)} consumed · ${Fmt.energy(imp)} imported',
      chart: EnergyBarChart(
        seriesLabels: const ['Generation', 'Consumption', 'Grid import'],
        seriesColors: [p.pv, p.load, p.gridImport],
        groups: [
          for (final d in days)
            BarGroup(
              label: Fmt.shortDay(d.period),
              fullLabel: '${Fmt.shortDay(d.period)}${d.source == EnergySource.counter ? ' (counter, so far)' : ''}${d.completenessPct != null && d.completenessPct! < 80 ? ' · completeness ${Fmt.percent(d.completenessPct)}' : ''}',
              values: [d.generationKwh, d.consumptionKwh, d.gridImportKwh],
            ),
        ],
        maxLabels: 10,
      ),
      table: ChartTable(
        columns: const ['Day', 'Generation', 'Consumption', 'Import', 'Export', 'Charge', 'Discharge', 'Yield', 'Self-suff.', 'Completeness', 'Source'],
        rows: [
          for (final d in days.reversed)
            [
              Fmt.shortDay(d.period),
              Fmt.energy(d.generationKwh),
              Fmt.energy(d.consumptionKwh),
              Fmt.energy(d.gridImportKwh),
              Fmt.energy(d.gridExportKwh),
              Fmt.energy(d.chargeKwh),
              Fmt.energy(d.dischargeKwh),
              d.fullPowerHours == null ? '–' : '${Fmt.two(d.fullPowerHours)} h',
              d.selfSufficiency == null ? 'n/a' : Fmt.ratio(d.selfSufficiency),
              Fmt.percent(d.completenessPct),
              d.source.name,
            ],
        ],
      ),
    );
  }
}

/// 12-month energy of one plant.
class StationEnergy12mCard extends StatelessWidget {
  const StationEnergy12mCard({super.key, required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final months = detail.monthly;
    final gen = months.fold(0.0, (a, d) => a + (d.generationKwh ?? 0));
    return ChartOrTable(
      title: 'Energy last 12 months',
      subtitle: 'Σ ${Fmt.energy(gen)} generated',
      chart: EnergyBarChart(
        seriesLabels: const ['Generation', 'Consumption', 'Grid import'],
        seriesColors: [p.pv, p.load, p.gridImport],
        groups: [for (final m in months) BarGroup(label: Fmt.monthLabel(m.period).split(' ').first, fullLabel: Fmt.monthLabel(m.period), values: [m.generationKwh, m.consumptionKwh, m.gridImportKwh])],
        maxLabels: 12,
      ),
      table: ChartTable(
        columns: const ['Month', 'Generation', 'Consumption', 'Import', 'Export', 'Self-suff.'],
        rows: [
          for (final m in months.reversed)
            [Fmt.monthLabel(m.period), Fmt.energy(m.generationKwh), Fmt.energy(m.consumptionKwh), Fmt.energy(m.gridImportKwh), Fmt.energy(m.gridExportKwh), m.selfSufficiency == null ? 'n/a' : Fmt.ratio(m.selfSufficiency)],
        ],
      ),
    );
  }
}

/// Battery SOC min / max / average per day over the last 30 days.
class BatteryHistoryCard extends StatelessWidget {
  const BatteryHistoryCard({super.key, required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final days = detail.batteryDays;
    final loc = detail.station.location;
    (int, double)? pt(BatteryDay d, double? v) => v == null ? null : (AppTime.dayStart(d.day, loc) + 43200, v);
    final series = [
      TimeSeries(label: 'SOC max', color: p.socRamp[3], points: [for (final d in days) ?pt(d, d.socMax)]),
      TimeSeries(label: 'SOC average', color: p.accent, points: [for (final d in days) ?pt(d, d.socAvg)]),
      TimeSeries(label: 'SOC min', color: p.gridImport, points: [for (final d in days) ?pt(d, d.socMin)]),
    ];
    final hoursLow = days.fold(0.0, (a, d) => a + d.hoursBelow20);
    final tempMax = days.map((d) => d.tempMax).whereType<double>().fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    final cap = detail.station.batteryCapacityKwh;
    final dis30 = days.fold(0.0, (a, d) => a + (d.dischargeKwh ?? 0));
    return ChartOrTable(
      title: 'Battery — last 30 days',
      subtitle: '${Fmt.one(hoursLow)} h below 20 % · max temperature ${tempMax == null ? '–' : '${Fmt.one(tempMax)} °C'}${cap == null || cap <= 0 ? '' : ' · ≈ ${Fmt.one(dis30 / cap)} full cycles (${Fmt.energy(dis30)} discharged / ${Fmt.energy(cap)} nominal)'}',
      chart: PowerLineChart(
        series: series,
        height: 200,
        minY: 0,
        maxY: 100,
        unitFormatter: (v) => Fmt.percent(v),
        timeFormatter: (ts) => Fmt.shortDate(Fmt.fromEpoch(ts)),
      ),
      table: ChartTable(
        columns: const ['Day', 'SOC min', 'SOC avg', 'SOC max', 'h < 20 %', 'Temp max', 'Charge', 'Discharge', 'Samples'],
        rows: [
          for (final d in days.reversed)
            [Fmt.shortDay(d.day), Fmt.percent(d.socMin), Fmt.percent(d.socAvg), Fmt.percent(d.socMax), Fmt.one(d.hoursBelow20), d.tempMax == null ? '–' : '${Fmt.one(d.tempMax)} °C', Fmt.energy(d.chargeKwh), Fmt.energy(d.dischargeKwh), Fmt.int_(d.samples)],
        ],
      ),
    );
  }
}

/// Status transitions of the last 30 days as a proportional timeline.
class StatusHistoryCard extends StatelessWidget {
  const StatusHistoryCard({super.key, required this.events, this.now});
  final List<StatusEvent> events;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final from = n - 30 * 86400;
    final sorted = [...events]..sort((a, b) => a.startTs.compareTo(b.startTs));
    final segments = <(StationStatus, int, int)>[];
    for (final e in sorted) {
      final s = e.startTs < from ? from : e.startTs;
      final end = (e.endTs ?? n) > n ? n : (e.endTs ?? n);
      if (end > s) segments.add((e.status, s, end));
    }
    final down = segments.where((s) => s.$1.isDown).fold(0, (a, s) => a + (s.$3 - s.$2));
    final covered = segments.fold(0, (a, s) => a + (s.$3 - s.$2));
    final transitions = sorted.where((e) => e.startTs >= from).toList().reversed.take(10).toList();
    return SectionCard(
      title: 'Status history — last 30 days',
      subtitle: covered == 0 ? 'No status history yet' : 'Availability ${Fmt.ratio(1 - down / covered, decimals: 1)} · ${sorted.where((e) => e.status.isDown && e.startTs >= from).length} outages',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segments.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 18,
                child: Row(
                  children: [
                    if (segments.first.$2 > from) Expanded(flex: segments.first.$2 - from, child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
                    for (final s in segments)
                      Expanded(
                        flex: (s.$3 - s.$2).clamp(1, 1 << 30),
                        child: Tooltip(message: '${s.$1.label}: ${Fmt.dateTime(s.$2)} → ${Fmt.dateTime(s.$3)}', child: Container(color: AppColors.stationStatus(s.$1))),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [for (final s in StationStatus.values) LegendItem(color: AppColors.stationStatus(s), label: s.label)]),
          const SizedBox(height: 12),
          Text('Latest transitions', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (transitions.isEmpty)
            Text('No transitions in the last 30 days', style: t.bodySmall)
          else
            for (final e in transitions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(AppColors.stationStatusIcon(e.status), size: 16, color: AppColors.stationStatus(e.status)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${e.status.label} since ${Fmt.dateTime(e.startTs)}', style: t.bodySmall)),
                    Text(Fmt.duration(e.durationUntil(n)), style: t.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
