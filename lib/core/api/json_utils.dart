/// Tolerant JSON helpers.
///
/// DeyeCloud responses are not perfectly consistent across regions, account
/// types and firmware versions: numbers may arrive as strings, timestamps as
/// epoch seconds, epoch milliseconds or ISO-8601 text, and list payloads under
/// slightly different keys. Every parser in the app goes through these helpers
/// so a single odd value never breaks a whole sync.
library;

import 'package:timezone/timezone.dart' as tz;

import '../utils/app_time.dart';

double? asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is bool) return v ? 1 : 0;
  final s = v.toString().trim();
  if (s.isEmpty || s == '-' || s.toLowerCase() == 'null') return null;
  return double.tryParse(s.replaceAll(',', ''));
}

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.round() : null;
  if (v is bool) return v ? 1 : 0;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s) ?? double.tryParse(s)?.round();
}

String? asString(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

bool? asBool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
  if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  return null;
}

/// Converts any DeyeCloud time representation to **epoch seconds (UTC)**.
///
/// Accepts: epoch seconds, epoch milliseconds, numeric strings of either,
/// ISO-8601 (with or without offset), `yyyy-MM-dd HH:mm:ss`, `yyyy/MM/dd`,
/// `yyyy-MM-dd`, and `{year, month, day[, hour, minute]}` maps. Text without
/// an explicit offset is interpreted as wall-clock time in [location]
/// (Asia/Beirut by default) because the cloud reports plant-local time for
/// history rows. Returns null rather than guessing.
int? asEpochSeconds(Object? v, {tz.Location? location}) {
  if (v == null) return null;
  if (v is num) return _normaliseEpoch(v);
  if (v is Map) {
    final m = asMap(v);
    final y = asInt(pick(m, ['year']));
    final mo = asInt(pick(m, ['month']));
    final d = asInt(pick(m, ['day'])) ?? 1;
    if (y == null || mo == null) return null;
    return AppTime.fromLocalParts(y, mo, d, asInt(pick(m, ['hour'])) ?? 0, asInt(pick(m, ['minute'])) ?? 0, 0, location);
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n != null) return _normaliseEpoch(n);
  final iso = s.replaceFirst(' ', 'T').replaceAll('/', '-');
  final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(iso) && iso.contains('T');
  if (hasOffset) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? null : dt.toUtc().millisecondsSinceEpoch ~/ 1000;
  }
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:T(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?$').firstMatch(iso);
  if (m == null) return null;
  return AppTime.fromLocalParts(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.tryParse(m.group(4) ?? '') ?? 0,
    int.tryParse(m.group(5) ?? '') ?? 0,
    int.tryParse(m.group(6) ?? '') ?? 0,
    location,
  );
}

int? _normaliseEpoch(num n) {
  if (!n.isFinite || n <= 0) return null;
  // > 1e11 cannot be seconds (year 5138) so it must be milliseconds.
  if (n > 100000000000) return (n / 1000).round();
  return n.round();
}

/// Returns the first value found under any of [keys] (case-sensitive first,
/// then case-insensitive).
Object? pick(Map<String, Object?> json, List<String> keys) {
  for (final k in keys) {
    if (json.containsKey(k) && json[k] != null) return json[k];
  }
  final lower = {for (final e in json.entries) e.key.toLowerCase(): e.value};
  for (final k in keys) {
    final v = lower[k.toLowerCase()];
    if (v != null) return v;
  }
  return null;
}

/// Returns the first list found under any of [keys]; if none match, the first
/// list-valued property anywhere at the top level (DeyeCloud renames list
/// wrappers between endpoints). Never returns null.
List<Map<String, Object?>> firstList(Map<String, Object?> json, List<String> keys) {
  final direct = pick(json, keys);
  if (direct is List) return _mapList(direct);
  for (final v in json.values) {
    if (v is List && v.isNotEmpty && v.first is Map) return _mapList(v);
  }
  // One level deeper (e.g. {"data": {"list": [...]}}).
  for (final v in json.values) {
    if (v is Map) {
      final nested = firstList(asMap(v), keys);
      if (nested.isNotEmpty) return nested;
    }
  }
  return const [];
}

List<Map<String, Object?>> _mapList(List<Object?> list) => [
      for (final e in list)
        if (e is Map) asMap(e),
    ];

Map<String, Object?> asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return const {};
}

/// Formats a `yyyy-MM-dd` date for DeyeCloud history calls.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Formats a `yyyy-MM` month for DeyeCloud history calls.
String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
