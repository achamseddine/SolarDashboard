import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils/format.dart';
import 'widgets.dart';

/// One series of a time chart: (epoch seconds, value) points.
class TimeSeries {
  const TimeSeries({required this.label, required this.color, required this.points, this.area = false, this.dashed = false, this.emphasis = true});

  final String label;
  final Color color;

  /// (epochSeconds, value) — value in the chart's unit (W or kWh).
  final List<(int, double)> points;
  final bool area;
  final bool dashed;

  /// False draws the series in the de-emphasis gray (context line).
  final bool emphasis;
}

/// Shared chart chrome: hairline grid, muted ticks, rounded tooltip.
class _Chrome {
  _Chrome(this.context) : p = ChartPalette.of(context);
  final BuildContext context;
  final ChartPalette p;

  TextStyle get tick => Theme.of(context).textTheme.labelSmall!.copyWith(color: p.inkMuted, fontFeatures: const [FontFeature.tabularFigures()]);
  TextStyle get tooltip => Theme.of(context).textTheme.labelMedium!.copyWith(color: p.inkPrimary);
  FlGridData grid({bool vertical = false}) => FlGridData(
        show: true,
        drawVerticalLine: vertical,
        getDrawingHorizontalLine: (_) => FlLine(color: p.grid, strokeWidth: 1),
        getDrawingVerticalLine: (_) => FlLine(color: p.grid, strokeWidth: 1),
      );
  FlBorderData border() => FlBorderData(show: true, border: Border(bottom: BorderSide(color: p.axis, width: 1)));
  Color get tooltipBg => p.isDark ? const Color(0xFF2C2C2A) : Colors.white;
}

/// Multi-series line chart over time (power in W, or any unit via [unitFormatter]).
/// Legend always shown for ≥ 2 series; tooltip on touch; hairline grid.
class PowerLineChart extends StatelessWidget {
  const PowerLineChart({
    super.key,
    required this.series,
    this.height = 240,
    this.unitFormatter,
    this.timeFormatter,
    this.minY,
    this.maxY,
    this.showLegend = true,
    this.xFrom,
    this.xTo,
  });

  final List<TimeSeries> series;
  final double height;
  final String Function(double)? unitFormatter;
  final String Function(int epochSeconds)? timeFormatter;
  final double? minY;
  final double? maxY;
  final bool showLegend;
  final int? xFrom;
  final int? xTo;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final fmtY = unitFormatter ?? (v) => Fmt.power(v);
    final fmtX = timeFormatter ?? (ts) => Fmt.time(ts);
    final nonEmpty = series.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return SizedBox(height: height, child: const EmptyState(message: 'No data for this period', icon: Icons.show_chart));
    final allX = nonEmpty.expand((s) => s.points.map((p) => p.$1)).toList();
    final x0 = (xFrom ?? allX.reduce(math.min)).toDouble();
    final x1 = (xTo ?? allX.reduce(math.max)).toDouble();
    final allY = nonEmpty.expand((s) => s.points.map((p) => p.$2)).toList();
    var yMin = minY ?? math.min(0, allY.reduce(math.min));
    var yMax = maxY ?? allY.reduce(math.max);
    if (yMax <= yMin) yMax = yMin + 1;
    final pad = (yMax - yMin) * 0.08;
    yMax += pad;
    if (yMin < 0) yMin -= pad;

    final bars = <LineChartBarData>[
      for (final s in nonEmpty)
        LineChartBarData(
          spots: [for (final p in s.points) FlSpot(p.$1.toDouble(), p.$2)],
          color: s.emphasis ? s.color : c.p.deEmphasis,
          barWidth: 2,
          isCurved: false,
          isStrokeCapRound: true,
          dashArray: s.dashed ? [6, 4] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: s.area && s.emphasis, color: s.color.withValues(alpha: 0.10)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: x0,
              maxX: x1 > x0 ? x1 : x0 + 1,
              minY: yMin,
              maxY: yMax,
              gridData: c.grid(),
              borderData: c.border(),
              clipData: const FlClipData.all(),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (v, meta) => v == meta.max || v == meta.min && v < 0
                        ? const SizedBox.shrink()
                        : Padding(padding: const EdgeInsets.only(right: 6), child: Text(fmtY(v), style: c.tick, textAlign: TextAlign.right)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: _niceTimeInterval(x0, x1),
                    getTitlesWidget: (v, meta) => v == meta.max || v == meta.min
                        ? const SizedBox.shrink()
                        : Padding(padding: const EdgeInsets.only(top: 6), child: Text(fmtX(v.round()), style: c.tick)),
                  ),
                ),
              ),
              lineBarsData: bars,
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(FlLine(color: c.p.axis, strokeWidth: 1), FlDotData(getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: bar.color ?? c.p.accent, strokeWidth: 2, strokeColor: c.p.surface))),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => c.tooltipBg,
                  tooltipBorder: BorderSide(color: c.p.grid),
                  tooltipBorderRadius: BorderRadius.circular(8),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (var i = 0; i < spots.length; i++)
                      LineTooltipItem(
                        i == 0 ? '${fmtX(spots[i].x.round())}\n' : '',
                        c.tooltip.copyWith(fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(text: '● ', style: c.tooltip.copyWith(color: nonEmpty[spots[i].barIndex].color)),
                          TextSpan(text: '${nonEmpty[spots[i].barIndex].label}  ', style: c.tooltip.copyWith(color: c.p.inkSecondary)),
                          TextSpan(text: fmtY(spots[i].y), style: c.tooltip.copyWith(fontWeight: FontWeight.w600)),
                        ],
                        textAlign: TextAlign.left,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showLegend && nonEmpty.length >= 2) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 6, children: [for (final s in nonEmpty) LegendItem(color: s.emphasis ? s.color : c.p.deEmphasis, label: s.label)]),
        ],
      ],
    );
  }

  static double _niceTimeInterval(double x0, double x1) {
    final span = x1 - x0;
    for (final step in [900.0, 1800.0, 3600.0, 7200.0, 10800.0, 21600.0, 43200.0, 86400.0, 172800.0, 604800.0, 2592000.0]) {
      if (span / step <= 8) return step;
    }
    return span / 6;
  }
}

/// One bar group (a day, a month, a category) with one value per series.
class BarGroup {
  const BarGroup({required this.label, required this.values, this.fullLabel});
  final String label;
  final String? fullLabel;
  final List<double?> values;
}

/// Grouped (or stacked) bars for energy over days/months or categories.
/// Bars ≤ 24 px, 4 px rounded caps, 2 px surface gap, legend for ≥ 2 series.
class EnergyBarChart extends StatelessWidget {
  const EnergyBarChart({
    super.key,
    required this.seriesLabels,
    required this.seriesColors,
    required this.groups,
    this.height = 240,
    this.stacked = false,
    this.unitFormatter,
    this.showLegend = true,
    this.maxLabels = 12,
    this.signed = false,
    this.emptyMessage = 'No energy data for this period',
    this.onBarTap,
  });

  final List<String> seriesLabels;
  final List<Color> seriesColors;
  final List<BarGroup> groups;
  final double height;
  final bool stacked;
  final String Function(double)? unitFormatter;
  final bool showLegend;
  final int maxLabels;

  /// Let negative values stack below the axis, so a produced-versus-used
  /// history reads as one mirrored bar per day instead of two charts.
  final bool signed;

  /// Shown when there is nothing to plot. The default speaks of energy
  /// because that is where this chart began; anything else must say what it
  /// is actually missing.
  final String emptyMessage;

  /// Called with the group index when a bar is tapped, so a day on the chart
  /// can open what it is made of. The tooltip stays; this is the drill-down.
  final void Function(int index)? onBarTap;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final fmt = unitFormatter ?? (v) => Fmt.energy(v);
    if (groups.isEmpty || groups.every((g) => g.values.every((v) => v == null || v == 0))) {
      return SizedBox(height: height, child: EmptyState(message: emptyMessage, icon: Icons.bar_chart));
    }
    final n = seriesLabels.length;
    var maxY = 0.0;
    var minY = 0.0;
    for (final g in groups) {
      if (stacked) {
        // Positive and negative series stack away from the axis separately.
        final up = g.values.fold<double>(0, (a, v) => a + math.max(0.0, v ?? 0));
        final down = g.values.fold<double>(0, (a, v) => a + math.min(0.0, v ?? 0));
        maxY = math.max(maxY, up);
        minY = math.min(minY, down);
      } else {
        for (final v in g.values) {
          maxY = math.max(maxY, v ?? 0);
          minY = math.min(minY, v ?? 0);
        }
      }
    }
    if (maxY <= 0) maxY = 1;
    if (!signed) minY = 0;
    final labelEvery = math.max(1, (groups.length / maxLabels).ceil());
    return LayoutBuilder(builder: (context, constraints) {
      final slot = constraints.maxWidth / math.max(1, groups.length);
      final barW = stacked ? math.min(24.0, slot * 0.6) : math.min(24.0, (slot * 0.7) / n - 2).clamp(2.0, 24.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.08,
                minY: minY * 1.08,
                alignment: BarChartAlignment.spaceAround,
                gridData: c.grid(),
                borderData: c.border(),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      // The bounds sit a hair outside the last gridline, so
                      // labelling them would overprint the tick next to them.
                      getTitlesWidget: (v, meta) => v == meta.max || (signed && v == meta.min)
                          ? const SizedBox.shrink()
                          : Padding(padding: const EdgeInsets.only(right: 6), child: Text(fmt(signed ? v.abs() : v), style: c.tick, textAlign: TextAlign.right)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i < 0 || i >= groups.length || i % labelEvery != 0) return const SizedBox.shrink();
                        return Padding(padding: const EdgeInsets.only(top: 6), child: Text(groups[i].label, style: c.tick));
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchCallback: onBarTap == null
                      ? null
                      : (event, response) {
                          // A deliberate tap only: the callback also fires on
                          // hover and on touch-down.
                          if (event is! FlTapUpEvent) return;
                          final i = response?.spot?.touchedBarGroupIndex;
                          if (i != null && i >= 0 && i < groups.length) onBarTap!(i);
                        },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => c.tooltipBg,
                    tooltipBorder: BorderSide(color: c.p.grid),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, gi, rod, ri) {
                      final g = groups[group.x];
                      final children = <TextSpan>[];
                      for (var s = 0; s < n; s++) {
                        final v = g.values.length > s ? g.values[s] : null;
                        if (v == null) continue;
                        children.add(TextSpan(text: '\n● ', style: c.tooltip.copyWith(color: seriesColors[s])));
                        children.add(TextSpan(text: '${seriesLabels[s]}  ', style: c.tooltip.copyWith(color: c.p.inkSecondary)));
                        children.add(TextSpan(text: fmt(signed ? v.abs() : v), style: c.tooltip.copyWith(fontWeight: FontWeight.w600)));
                      }
                      return BarTooltipItem(g.fullLabel ?? g.label, c.tooltip.copyWith(fontWeight: FontWeight.w600), children: children, textAlign: TextAlign.left);
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < groups.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: stacked
                          ? [
                              BarChartRodData(
                                toY: signed
                                    ? groups[i].values.fold<double>(0, (a, v) => a + math.max(0.0, v ?? 0))
                                    : groups[i].values.fold<double>(0, (a, v) => a + (v ?? 0)),
                                fromY: signed ? groups[i].values.fold<double>(0, (a, v) => a + math.min(0.0, v ?? 0)) : 0,
                                width: barW,
                                borderRadius: signed ? BorderRadius.circular(3) : const BorderRadius.vertical(top: Radius.circular(4)),
                                rodStackItems: _stackItems(groups[i].values, c.p.surface),
                              ),
                            ]
                          : [
                              for (var s = 0; s < n; s++)
                                BarChartRodData(
                                  toY: (groups[i].values.length > s ? groups[i].values[s] : null) ?? 0,
                                  color: seriesColors[s],
                                  width: barW,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                            ],
                    ),
                ],
              ),
            ),
          ),
          if (showLegend && n >= 2) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, children: [for (var s = 0; s < n; s++) LegendItem(color: seriesColors[s], label: seriesLabels[s])]),
          ],
        ],
      );
    });
  }

  List<BarChartRodStackItem> _stackItems(List<double?> values, Color surface) {
    final items = <BarChartRodStackItem>[];
    var up = 0.0;
    var down = 0.0;
    for (var s = 0; s < values.length; s++) {
      final v = values[s] ?? 0;
      if (v > 0) {
        items.add(BarChartRodStackItem(up, up + v, seriesColors[s], borderSide: BorderSide(color: surface, width: 1)));
        up += v;
      } else if (v < 0 && signed) {
        items.add(BarChartRodStackItem(down + v, down, seriesColors[s], borderSide: BorderSide(color: surface, width: 1)));
        down += v;
      }
    }
    return items;
  }
}

/// Horizontal single-hue bars for rankings and category comparison
/// (nominal categories take one colour; a ranked list is not a value ramp).
class HorizontalBars extends StatelessWidget {
  const HorizontalBars({
    super.key,
    required this.items,
    this.color,
    this.formatter,
    this.maxValue,
    this.onTap,
    this.trailing,
    this.barHeight = 14,
    this.labelWidth = 150,
  });

  /// (label, value, optional accent override)
  final List<(String, double, Color?)> items;

  /// Width reserved for the row labels; widen it for longer names.
  final double labelWidth;
  final Color? color;
  final String Function(double)? formatter;
  final double? maxValue;
  final void Function(int index)? onTap;
  final Widget Function(int index)? trailing;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    if (items.isEmpty) return const EmptyState(message: 'Nothing to show', icon: Icons.bar_chart);
    final max = maxValue ?? items.map((e) => e.$2).fold<double>(0.0, (a, b) => math.max(a, b));
    final fmt = formatter ?? (v) => Fmt.one(v);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: labelWidth, child: Text(items[i].$1, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: max <= 0 ? 0 : (items[i].$2 / max).clamp(0.02, 1.0),
                        child: Container(
                          height: math.min(barHeight, 24),
                          decoration: BoxDecoration(
                            color: items[i].$3 ?? color ?? p.accent,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 72, child: Text(fmt(items[i].$2), style: t.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.right)),
                  if (trailing != null) trailing!(i),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Part-to-whole donut (≤ 6 slices) with a centre figure and side legend.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.centerLabel, this.centerValue, this.size = 160, this.onTap, this.valueFormatter});

  /// (label, value, color)
  final List<(String, double, Color)> slices;
  final String? centerLabel;
  final String? centerValue;

  /// How a slice's value reads in the legend. Defaults to a plain count;
  /// pass one for bytes, energy or anything else with a unit.
  final String Function(double value)? valueFormatter;
  final double size;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final t = Theme.of(context).textTheme;
    final total = slices.fold(0.0, (a, s) => a + s.$2);
    final visible = slices.where((s) => s.$2 > 0).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: size * 0.32,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      // A deliberate tap only. isInterestedForInteractions is
                      // also true for hover and touch-down, which fired the
                      // callback repeatedly as a finger slid over the chart.
                      if (onTap == null || event is! FlTapUpEvent) return;
                      final idx = response?.touchedSection?.touchedSectionIndex;
                      if (idx != null && idx >= 0 && idx < visible.length) onTap!(slices.indexOf(visible[idx]));
                    },
                  ),
                  sections: [
                    for (final s in visible)
                      PieChartSectionData(value: s.$2, color: s.$3, radius: size * 0.16, showTitle: false, borderSide: BorderSide(color: p.surface, width: 1)),
                    if (visible.isEmpty) PieChartSectionData(value: 1, color: p.grid, radius: size * 0.16, showTitle: false),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (centerValue != null) Text(centerValue!, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (centerLabel != null) Text(centerLabel!, style: t.labelSmall?.copyWith(color: p.inkSecondary)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < slices.length; i++)
                InkWell(
                  onTap: onTap == null ? null : () => onTap!(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: LegendItem(color: slices[i].$3, label: slices[i].$1, value: total <= 0 ? '0' : '${valueFormatter?.call(slices[i].$2) ?? Fmt.int_(slices[i].$2)} (${(slices[i].$2 / total * 100).toStringAsFixed(0)} %)'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// SOC distribution: five ordered buckets on the validated blue ramp.
class SocHistogram extends StatelessWidget {
  const SocHistogram({super.key, required this.counts, this.height = 150, this.onTap});

  /// Counts for 0-20, 20-40, 40-60, 60-80, 80-100.
  final List<int> counts;
  final double height;
  final void Function(int bucket)? onTap;

  static const labels = ['0–20 %', '20–40 %', '40–60 %', '60–80 %', '80–100 %'];

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final max = counts.fold(0, math.max);
    if (max == 0) return SizedBox(height: height, child: const EmptyState(message: 'No battery data yet', icon: Icons.battery_unknown));
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: max * 1.15,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          gridData: c.grid(),
          borderData: c.border(),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: math.max(1, (max / 4).ceilToDouble()), getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(Fmt.int_(v), style: c.tick))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, meta) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[v.round().clamp(0, 4)], style: c.tick)))),
          ),
          barTouchData: BarTouchData(
            touchCallback: (event, response) {
              if (onTap == null || event is! FlTapUpEvent) return;
              final idx = response?.spot?.touchedBarGroupIndex;
              if (idx != null) onTap!(idx);
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.tooltipBg,
              tooltipBorder: BorderSide(color: c.p.grid),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem('${labels[g.x]}\n', c.tooltip.copyWith(fontWeight: FontWeight.w600), children: [TextSpan(text: '${counts[g.x]} schools', style: c.tooltip)]),
            ),
          ),
          barGroups: [
            for (var i = 0; i < 5; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: counts[i].toDouble(), color: c.p.socRamp[i], width: 24, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Tiny trend line for stat tiles (de-emphasis hue, last point accent).
class SparkLine extends StatelessWidget {
  const SparkLine({super.key, required this.values, this.color, this.height = 28, this.width = 90});
  final List<double> values;
  final Color? color;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    if (values.length < 2) return SizedBox(width: width, height: height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparkPainter(values, color ?? p.accent, p.deEmphasis)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.accent, this.muted);
  final List<double> values;
  final Color accent;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final span = max - min == 0 ? 1 : max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i] - min) / span * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, Paint()..color = muted..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    final lx = size.width;
    final ly = size.height - (values.last - min) / span * (size.height - 4) - 2;
    canvas.drawCircle(Offset(lx - 2, ly), 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.accent != accent;
}

/// Same-ramp meter for a ratio (e.g. SOC, utilisation): the fill carries the
/// value, the track is a lighter step of the same hue.
class RatioMeter extends StatelessWidget {
  const RatioMeter({super.key, required this.value, this.color, this.height = 10, this.label});
  final double value; // 0..1
  final Color? color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final c = color ?? p.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label!, style: Theme.of(context).textTheme.labelSmall)),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(value: value.isNaN ? 0 : value.clamp(0, 1), minHeight: height, color: c, backgroundColor: c.withValues(alpha: 0.18)),
        ),
      ],
    );
  }
}

/// Table twin of a chart — the accessible / exact-values view.
class ChartTable extends StatelessWidget {
  const ChartTable({super.key, required this.columns, required this.rows, this.maxHeight = 320, this.onRowTap});
  final List<String> columns;
  final List<List<String>> rows;
  final double maxHeight;

  /// Called with the row index when a row is tapped. A table cell is a
  /// number like any other, and this is how it opens.
  final void Function(int index)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            // Row taps must not turn the table into a selection list.
            showCheckboxColumn: false,
            headingRowHeight: 36,
            // A row that can be tapped has to be big enough to tap.
            dataRowMinHeight: onRowTap == null ? 32 : 44,
            dataRowMaxHeight: onRowTap == null ? 36 : 48,
            columnSpacing: 20,
            columns: [for (final c in columns) DataColumn(label: Text(c))],
            rows: [
              for (var i = 0; i < rows.length; i++)
                DataRow(
                  onSelectChanged: onRowTap == null ? null : (_) => onRowTap!(i),
                  cells: [for (final v in rows[i]) DataCell(Text(v, style: t))],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card wrapper that offers a chart ↔ table toggle.
class ChartOrTable extends StatefulWidget {
  const ChartOrTable({super.key, required this.chart, required this.table, this.title, this.subtitle, this.trailing});
  final Widget chart;
  final ChartTable table;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<ChartOrTable> createState() => _ChartOrTableState();
}

class _ChartOrTableState extends State<ChartOrTable> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?widget.trailing,
          IconButton(
            tooltip: _table ? 'Show chart' : 'Show table',
            icon: Icon(_table ? Icons.show_chart : Icons.table_rows_outlined, size: 20),
            onPressed: () => setState(() => _table = !_table),
          ),
        ],
      ),
      child: _table ? widget.table : widget.chart,
    );
  }
}
