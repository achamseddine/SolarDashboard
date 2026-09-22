import 'package:flutter/material.dart';

import '../../../core/models/alert.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'plant_filters.dart';

/// The plant table of the DeyeCloud overview: name + location, communication
/// status, alarms, capacity, power, trend, daily production, battery and the
/// age of the data. The caller wraps it in the scroll views.
class PlantTable extends StatelessWidget {
  const PlantTable({super.key, required this.rows, required this.query, required this.onSort, required this.onOpen, this.now});

  final List<StationInsight> rows;
  final PlantQuery query;
  final void Function(PlantSort sort, bool ascending) onSort;
  final void Function(StationInsight s) onOpen;
  final DateTime? now;

  /// (header, sort key or null, numeric).
  static const List<(String, PlantSort?, bool)> columns = [
    ('Plant', PlantSort.name, false),
    ('Status', PlantSort.status, false),
    ('Alerts', PlantSort.alerts, true),
    ('Capacity (kWp)', PlantSort.capacity, true),
    ('Power now', PlantSort.powerNow, true),
    ('Trend', null, false),
    ('Daily production', PlantSort.dailyKwh, true),
    ('Battery SOC', PlantSort.soc, true),
    ('Last data', PlantSort.lastData, false),
    ('Open', null, false),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tabular = t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final sortIndex = columns.indexWhere((c) => c.$2 == query.sort);
    return DataTable(
      sortColumnIndex: sortIndex < 0 ? null : sortIndex,
      sortAscending: query.ascending,
      showCheckboxColumn: false,
      columnSpacing: 22,
      horizontalMargin: 12,
      columns: [
        for (final c in columns)
          DataColumn(
            label: c.$1 == 'Open' ? const SizedBox.shrink() : Text(c.$1),
            numeric: c.$3,
            onSort: c.$2 == null ? null : (i, asc) => onSort(c.$2!, asc),
          ),
      ],
      rows: [
        for (final s in rows)
          DataRow(
            key: ValueKey(s.id),
            onSelectChanged: (_) => onOpen(s),
            cells: [
              DataCell(PlantNameCell(insight: s)),
              DataCell(StatusChip(s.status)),
              DataCell(_AlertsCell(s)),
              DataCell(Text(Fmt.capacity(s.kwp), style: tabular)),
              DataCell(Text(Fmt.power(s.snapshot?.generationW), style: tabular)),
              DataCell(_TrendCell(s)),
              DataCell(Text(Fmt.energy(s.todayGenKwh), style: tabular)),
              DataCell(Text(Fmt.percent(s.socNow), style: tabular)),
              DataCell(
                Tooltip(
                  message: Fmt.dateTime(PlantQuery.lastDataTs(s)),
                  child: Text(Fmt.ago(PlantQuery.lastDataTs(s), now: now), style: tabular),
                ),
              ),
              DataCell(
                IconButton(
                  onPressed: () => onOpen(s),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: 'Open ${s.name}',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Plant name with its location underneath — governorate, district and
/// address when the cloud knows them, "Unassigned" when it does not.
class PlantNameCell extends StatelessWidget {
  const PlantNameCell({super.key, required this.insight});

  final StationInsight insight;

  /// "Beirut · Achrafieh · Rue X", never empty.
  String get location {
    final bits = <String>[
      insight.region,
      ?insight.station.caza,
      ?insight.station.address,
    ];
    return bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(location, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _AlertsCell extends StatelessWidget {
  const _AlertsCell(this.s);
  final StationInsight s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (s.activeAlerts == 0) return Text('–', style: t);
    final level = s.highestAlert ?? AlertLevel.medium;
    final color = AppColors.alertLevel(level);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: color, semanticLabel: level.label),
        const SizedBox(width: 4),
        Text(Fmt.int_(s.activeAlerts), style: t?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Today's generation curve; a muted dash when the plant sent nothing.
class _TrendCell extends StatelessWidget {
  const _TrendCell(this.s);
  final StationInsight s;

  @override
  Widget build(BuildContext context) {
    if (s.trend.length < 2) {
      return Text('–', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted));
    }
    return SparkLine(values: s.trend, color: AppColors.pv, height: 26, width: 84);
  }
}
