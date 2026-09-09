import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Timezone helpers. All timestamps in the database are epoch seconds (UTC);
/// calendar days are computed in the plant's zone (Asia/Beirut by default)
/// so daily totals line up with what DeyeCloud shows.
class AppTime {
  AppTime._();

  static bool _initialised = false;
  static const String defaultZone = 'Asia/Beirut';

  static void ensureInitialised() {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    _initialised = true;
  }

  static tz.Location get beirut => location(defaultZone);

  /// Resolves an IANA name, falling back to Asia/Beirut, then UTC.
  static tz.Location location(String? name) {
    ensureInitialised();
    if (name != null && name.isNotEmpty) {
      try {
        return tz.getLocation(name);
      } catch (_) {}
    }
    try {
      return tz.getLocation(defaultZone);
    } catch (_) {
      return tz.UTC;
    }
  }

  static tz.TZDateTime fromEpoch(int epochSeconds, [tz.Location? loc]) =>
      tz.TZDateTime.fromMillisecondsSinceEpoch(loc ?? beirut, epochSeconds * 1000);

  static tz.TZDateTime now([tz.Location? loc]) => tz.TZDateTime.now(loc ?? beirut);

  /// `yyyy-MM-dd` of [epochSeconds] in [loc].
  static String dayOf(int epochSeconds, [tz.Location? loc]) => formatDay(fromEpoch(epochSeconds, loc));

  /// `yyyy-MM` of [epochSeconds] in [loc].
  static String monthOf(int epochSeconds, [tz.Location? loc]) => formatMonth(fromEpoch(epochSeconds, loc));

  static String today([tz.Location? loc]) => formatDay(now(loc));

  static String formatDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String formatMonth(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// Epoch seconds at local midnight starting [day] (`yyyy-MM-dd`).
  static int dayStart(String day, [tz.Location? loc]) {
    final p = day.split('-').map(int.parse).toList();
    return tz.TZDateTime(loc ?? beirut, p[0], p[1], p.length > 2 ? p[2] : 1).millisecondsSinceEpoch ~/ 1000;
  }

  /// Epoch seconds at local midnight *after* [day].
  static int dayEnd(String day, [tz.Location? loc]) {
    final p = day.split('-').map(int.parse).toList();
    return tz.TZDateTime(loc ?? beirut, p[0], p[1], p[2] + 1).millisecondsSinceEpoch ~/ 1000;
  }

  /// Adds [days] to a `yyyy-MM-dd` string.
  static String addDays(String day, int days) {
    final p = day.split('-').map(int.parse).toList();
    return formatDay(DateTime.utc(p[0], p[1], p[2] + days));
  }

  /// Adds [months] to a `yyyy-MM` string.
  static String addMonths(String month, int months) {
    final p = month.split('-').map(int.parse).toList();
    return formatMonth(DateTime.utc(p[0], p[1] + months));
  }

  /// Local wall-clock components → epoch seconds in [loc].
  static int fromLocalParts(int y, int m, int d, [int h = 0, int mi = 0, int s = 0, tz.Location? loc]) =>
      tz.TZDateTime(loc ?? beirut, y, m, d, h, mi, s).millisecondsSinceEpoch ~/ 1000;

  /// Hour of day (0-23) of [epochSeconds] in [loc].
  static int hourOf(int epochSeconds, [tz.Location? loc]) => fromEpoch(epochSeconds, loc).hour;
}
