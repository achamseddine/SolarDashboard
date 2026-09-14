import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/models/school_query.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../programme/widgets/programme_common.dart';

/// Wide directory table over every school in the dataset; the caller wraps it
/// in a horizontal scroll view (see `SchoolsDirectoryScreen`).
class SchoolTable extends StatelessWidget {
  const SchoolTable({super.key, required this.rows, required this.query, required this.onSort, required this.onTap, required this.onOpenPlant, this.maxRows = defaultMaxRows});

  final List<SchoolInsight> rows;
  final SchoolQuery query;
  final void Function(SchoolSort sort, bool ascending) onSort;

  /// Row tap — opens the school record.
  final void Function(SchoolInsight s) onTap;

  /// Plant icon tap — opens the monitored plant.
  final void Function(SchoolInsight s) onOpenPlant;

  /// The dataset holds 1,216 schools; rendering them all at once would build
  /// a 13,000-widget table, so the view is capped and the screen explains it.
  final int maxRows;

  /// Rows rendered before the table is truncated.
  static const int defaultMaxRows = 300;

  /// Column order with the sort key each header toggles (null = not sortable)
  /// and whether the column is numeric (right aligned).
  static const List<(String, SchoolSort?, bool)> columns = [
    ('School', SchoolSort.name, false),
    ('CERD', SchoolSort.cerd, true),
    ('Governorate', SchoolSort.region, false),
    ('District', null, false),
    ('Internet', SchoolSort.connectivity, false),
    ('Solar', SchoolSort.solarStatus, false),
    ('kWp', SchoolSort.kwp, true),
    ('Students', SchoolSort.students, true),
    ('Audited load', SchoolSort.auditedLoad, true),
    ('Attendance', SchoolSort.attendance, true),
    ('Plant', null, false),
  ];

  /// Rows actually rendered (see [maxRows]).
  List<SchoolInsight> get visibleRows => rows.length <= maxRows ? rows : rows.sublist(0, maxRows);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tabular = t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final sortIndex = columns.indexWhere((c) => c.$2 == query.sort);
    return DataTable(
      sortColumnIndex: sortIndex < 0 ? null : sortIndex,
      sortAscending: query.ascending,
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
        for (final s in visibleRows)
          DataRow(
            onSelectChanged: (_) => onTap(s),
            cells: [
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        s.school.nameAr ?? (s.school.caza == null ? s.region : '${s.region} · ${s.school.caza}'),
                        style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(Text('${s.cerd}', style: tabular)),
              DataCell(Text(s.region, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(s.school.caza ?? '–', style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(_InternetCell(s.school.connected)),
              DataCell(_SolarCell(s.school.solarStatus)),
              DataCell(Text(Fmt.capacity(s.kwp), style: tabular)),
              DataCell(_StudentsCell(s.school, style: tabular)),
              DataCell(Text(Fmt.energy(s.annualLoadKwh), style: tabular)),
              DataCell(_AttendanceCell(s.school.education, style: tabular)),
              DataCell(_PlantCell(s, onOpen: () => onOpenPlant(s))),
            ],
          ),
      ],
    );
  }
}

/// Membership of the internet-connectivity roll-out (a school is on the list
/// or not — the list carries no bandwidth, provider or uptime).
class _InternetCell extends StatelessWidget {
  const _InternetCell(this.connected);
  final bool connected;

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return const Tooltip(message: 'On the connectivity roll-out', child: Icon(Icons.wifi, size: 18, color: AppColors.good, semanticLabel: 'on the connectivity roll-out'));
    }
    return const Tooltip(message: 'Not on the roll-out', child: Icon(Icons.wifi_off, size: 18, color: AppColors.muted, semanticLabel: 'not on the roll-out'));
  }
}

/// Solarisation status pill, "–" when the school is not in the tracker.
class _SolarCell extends StatelessWidget {
  const _SolarCell(this.status);
  final SolarStatus? status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = this.status;
    if (status == null) {
      return Tooltip(message: 'No record in the UNICEF solar implementation tracker', child: Text('–', style: t.bodyMedium));
    }
    final c = solarStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(status.label, style: t.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/// Enrolment with the AM/PM split in a tooltip.
class _StudentsCell extends StatelessWidget {
  const _StudentsCell(this.school, {this.style});
  final School school;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final am = school.studentsAm;
    final pm = school.studentsPm;
    final tip = am == null && pm == null
        ? 'Enrolment; no shift split in the MEHE master list'
        : 'Morning shift ${Fmt.int_(am ?? 0)} · afternoon shift ${Fmt.int_(pm ?? 0)}';
    return Tooltip(message: tip, child: Text(Fmt.int_(school.students), style: style));
  }
}

/// Morning-shift attendance from the MEHE education dashboard.
class _AttendanceCell extends StatelessWidget {
  const _AttendanceCell(this.education, {this.style});
  final SchoolEducation? education;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final am = education?.amAttendance;
    final pm = education?.pmAttendance;
    if (am == null) return Text('–', style: style);
    final tip = pm == null ? 'Morning-shift attendance' : 'Morning shift ${Fmt.ratio(am)} · afternoon shift ${Fmt.ratio(pm)}';
    return Tooltip(message: tip, child: Text(Fmt.ratio(am), style: style));
  }
}

/// Linked DeyeCloud plant, "–" when the school is not monitored.
class _PlantCell extends StatelessWidget {
  const _PlantCell(this.s, {required this.onOpen});
  final SchoolInsight s;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final station = s.station;
    if (station == null) {
      return Tooltip(message: 'No monitored plant linked to this school', child: Text('–', style: Theme.of(context).textTheme.bodyMedium));
    }
    return IconButton(
      onPressed: onOpen,
      visualDensity: VisualDensity.compact,
      tooltip: '${station.name} · ${station.status.label}',
      icon: Icon(Icons.sensors, size: 18, color: AppColors.stationStatus(station.status), semanticLabel: 'monitored plant'),
    );
  }
}
