import 'package:flutter/material.dart';

import '../../../core/models/alert.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../station_filters.dart';

/// Wide schools table; the caller wraps it in a horizontal scroll view.
class StationTable extends StatelessWidget {
  const StationTable({super.key, required this.rows, required this.filter, required this.onSort, required this.onTap, this.now});

  final List<StationInsight> rows;
  final StationFilter filter;
  final void Function(StationSort sort, bool ascending) onSort;
  final void Function(StationInsight s) onTap;
  final DateTime? now;

  /// Column order with the sort key each header toggles (null = not sortable).
  static const List<(String, StationSort?, bool)> columns = [
    ('Status', StationSort.status, false),
    ('School', StationSort.name, false),
    ('kWp', null, true),
    ('PV now', StationSort.generationNow, true),
    ('Load now', null, true),
    ('SOC', StationSort.soc, true),
    ('Today', StationSort.todayKwh, true),
    ('Yield 7 d', StationSort.yield7d, true),
    ('Availability 7 d', StationSort.availability, true),
    ('Alarms', null, true),
    ('Last data', StationSort.lastUpdate, false),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tabular = t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final sortIndex = columns.indexWhere((c) => c.$2 == filter.sort);
    return DataTable(
      sortColumnIndex: sortIndex < 0 ? null : sortIndex,
      sortAscending: filter.ascending,
      showCheckboxColumn: false,
      columnSpacing: 20,
      horizontalMargin: 12,
      columns: [
        for (final c in columns)
          DataColumn(
            label: Text(c.$1),
            numeric: c.$3,
            onSort: c.$2 == null ? null : (i, asc) => onSort(c.$2!, asc),
          ),
      ],
      rows: [
        for (final s in rows)
          DataRow(
            onSelectChanged: (_) => onTap(s),
            cells: [
              DataCell(StatusChip(s.status)),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        s.station.caza == null ? s.region : '${s.region} · ${s.station.caza}',
                        style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(Text(Fmt.capacity(s.kwp), style: tabular)),
              DataCell(Text(Fmt.power(s.snapshot?.generationW), style: tabular)),
              DataCell(Text(Fmt.power(s.snapshot?.consumptionW), style: tabular)),
              DataCell(_SocCell(s.socNow)),
              DataCell(Text(Fmt.energy(s.todayGenKwh), style: tabular)),
              DataCell(_YieldCell(s)),
              DataCell(Text(Fmt.ratio(s.availability7d), style: tabular)),
              DataCell(_AlarmCell(s)),
              DataCell(
                Tooltip(
                  message: Fmt.dateTime(s.latest?.dataTs ?? s.station.lastUpdateTs),
                  child: Text(Fmt.ago(s.latest?.dataTs ?? s.station.lastUpdateTs, now: now), style: tabular),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _SocCell extends StatelessWidget {
  const _SocCell(this.soc);
  final double? soc;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (soc == null) return Text('–', style: t);
    final p = ChartPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (soc! < 20) ...[Icon(Icons.battery_alert, size: 16, color: AppColors.warning, semanticLabel: 'low'), const SizedBox(width: 4)],
        SizedBox(
          width: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: (soc! / 100).clamp(0, 1), minHeight: 6, color: p.socColor(soc!), backgroundColor: p.socColor(soc!).withValues(alpha: 0.18)),
          ),
        ),
        const SizedBox(width: 6),
        Text(Fmt.percent(soc), style: t),
      ],
    );
  }
}

class _YieldCell extends StatelessWidget {
  const _YieldCell(this.s);
  final StationInsight s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pr = s.performanceRatio7d;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(s.yield7d == null ? '–' : '${Fmt.two(s.yield7d)} kWh/kWp', style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.isUnderPerformer) ...[const Icon(Icons.trending_down, size: 14, color: AppColors.serious, semanticLabel: 'under-performing'), const SizedBox(width: 3)],
            Text(pr == null ? 'PR –' : 'PR ${Fmt.two(pr)}', style: t.bodySmall?.copyWith(color: s.isUnderPerformer ? AppColors.serious : scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _AlarmCell extends StatelessWidget {
  const _AlarmCell(this.s);
  final StationInsight s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (s.activeAlerts == 0) return Text('0', style: t);
    final level = s.highestAlert ?? AlertLevel.medium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.alertLevel(level), semanticLabel: level.label),
        const SizedBox(width: 4),
        Text('${s.activeAlerts} ${level.label.toLowerCase()}', style: t),
      ],
    );
  }
}
