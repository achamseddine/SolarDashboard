import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/models/school.dart';

/// Column headers of the schools CSV export. The `cerd`, `mehe_school_name`,
/// `connected`, `donor` and `students` columns come from the linked MEHE
/// school record and are empty for unlinked plants.
const List<String> stationCsvColumns = [
  'id',
  'name',
  'cerd',
  'mehe_school_name',
  'connected',
  'donor',
  'students',
  'governorate',
  'caza',
  'address',
  'status',
  'kwp',
  'battery_kwh',
  'pv_now_w',
  'load_now_w',
  'grid_import_now_w',
  'grid_export_now_w',
  'soc_pct',
  'today_generation_kwh',
  'today_consumption_kwh',
  'today_import_kwh',
  'today_export_kwh',
  'yield_7d_kwh_per_kwp',
  'peer_median_yield_7d',
  'performance_ratio_7d',
  'self_sufficiency_7d',
  'availability_7d',
  'availability_30d',
  'outages_30d',
  'active_alarms',
  'last_data_utc',
  'lat',
  'lng',
];

String _num(double? v, [int decimals = 2]) => v == null ? '' : v.toStringAsFixed(decimals);

String _iso(int? ts) => ts == null ? '' : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toIso8601String();

/// One CSV row per station (raw numbers, no units, empty for unknown).
/// [schools] maps a station id to its linked MEHE school.
List<List<Object?>> stationCsvRows(List<StationInsight> rows, {Map<int, School> schools = const {}}) => [
      for (final s in rows)
        [
          s.id,
          s.name,
          schools[s.id]?.cerd ?? '',
          schools[s.id]?.name ?? '',
          schools[s.id] == null ? '' : (schools[s.id]!.connected ? 'yes' : 'no'),
          schools[s.id]?.solar?.donorGroup ?? '',
          schools[s.id]?.students ?? '',
          s.region,
          s.station.caza ?? '',
          s.station.address ?? '',
          s.status.label,
          _num(s.kwp, 1),
          _num(s.station.batteryCapacityKwh, 1),
          _num(s.snapshot?.generationW, 0),
          _num(s.snapshot?.consumptionW, 0),
          _num(s.snapshot?.importW, 0),
          _num(s.snapshot?.exportW, 0),
          _num(s.socNow, 0),
          _num(s.todayGenKwh),
          _num(s.todayConsKwh),
          _num(s.todayImportKwh),
          _num(s.todayExportKwh),
          _num(s.yield7d),
          _num(s.peerMedianYield7d),
          _num(s.performanceRatio7d),
          _num(s.selfSufficiency7d, 3),
          _num(s.availability7d, 3),
          _num(s.availability30d, 3),
          s.outages30d,
          s.activeAlerts,
          _iso(s.latest?.dataTs ?? s.station.lastUpdateTs),
          _num(s.station.lat, 5),
          _num(s.station.lng, 5),
        ],
    ];

/// Serialises the current rows to CSV text.
String buildStationsCsv(List<StationInsight> rows, {Map<int, School> schools = const {}}) =>
    Csv(lineDelimiter: '\n', addBom: true).encode([stationCsvColumns, ...stationCsvRows(rows, schools: schools)]);

/// Writes the rows to a temp file and opens the platform share sheet.
/// Reports success or failure with a SnackBar; never throws.
Future<void> exportStationsCsv(BuildContext context, List<StationInsight> rows, {Map<int, School> schools = const {}}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final origin = _shareOrigin(context);
  try {
    final csv = buildStationsCsv(rows, schools: schools);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'schools_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.csv';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'School solar fleet – ${rows.length} schools',
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
