import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/school_insights.dart';

/// Column headers of the school directory CSV export. One row per school
/// (CERD), joining the MEHE master list, the connectivity roll-out, the
/// UNICEF solar tracker, the energy audit, the education dashboard and the
/// linked DeyeCloud plant. Empty cells mean "not in that source".
const List<String> schoolCsvColumns = [
  'cerd',
  'school',
  'name_ar',
  'governorate',
  'caza',
  'cadaster',
  'ownership',
  'students_am',
  'students_pm',
  'enrollment',
  'internet',
  'solar_status',
  'donor',
  'kwp',
  'battery_kwh',
  'cost_usd',
  'audited_load_kwh',
  'am_attendance',
  'pm_attendance',
  'plant_id',
  'plant_status',
];

String _num(double? v, [int decimals = 2]) => v == null ? '' : v.toStringAsFixed(decimals);

/// One CSV row per school (raw numbers, no units, empty for unknown).
List<List<Object?>> schoolCsvRows(List<SchoolInsight> rows) => [
      for (final r in rows)
        [
          r.cerd,
          r.school.name,
          r.school.nameAr ?? '',
          r.region,
          r.school.caza ?? '',
          r.school.cadaster ?? '',
          r.school.ownership ?? '',
          r.school.studentsAm ?? '',
          r.school.studentsPm ?? '',
          r.school.students ?? '',
          r.school.connected ? 'yes' : 'no',
          r.school.solarStatus?.label ?? '',
          r.school.solar?.donorGroup ?? r.school.solar?.donor ?? '',
          _num(r.kwp, 1),
          _num(r.school.solar?.batteryKwh, 1),
          _num(r.school.solar?.costUsd, 0),
          _num(r.annualLoadKwh, 0),
          _num(r.school.education?.amAttendance, 3),
          _num(r.school.education?.pmAttendance, 3),
          r.station?.id ?? '',
          r.station?.status.label ?? '',
        ],
    ];

/// Serialises the current rows to CSV text.
String buildSchoolsCsv(List<SchoolInsight> rows) => Csv(lineDelimiter: '\n', addBom: true).encode([schoolCsvColumns, ...schoolCsvRows(rows)]);

/// Writes the rows to a temp file and opens the platform share sheet.
/// Reports success or failure with a SnackBar; never throws.
Future<void> exportSchoolsCsv(BuildContext context, List<SchoolInsight> rows) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final origin = _shareOrigin(context);
  try {
    final csv = buildSchoolsCsv(rows);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'school_directory_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.csv';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'School directory – ${rows.length} schools',
      text: 'CSV export of ${rows.length} schools (${now.toIso8601String().substring(0, 16)})',
      sharePositionOrigin: origin,
    ));
    messenger?.showSnackBar(SnackBar(content: Text('Exported ${rows.length} schools to $name')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
