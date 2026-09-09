import 'package:intl/intl.dart';

/// Number / unit formatting shared by all screens.
class Fmt {
  Fmt._();

  static final NumberFormat _int = NumberFormat('#,##0');
  static final NumberFormat _one = NumberFormat('#,##0.0');
  static final NumberFormat _two = NumberFormat('#,##0.00');

  static String int_(num? v) => v == null ? '–' : _int.format(v);
  static String one(num? v) => v == null ? '–' : _one.format(v);
  static String two(num? v) => v == null ? '–' : _two.format(v);

  /// Watts → `812 W`, `4.3 kW`, `1.20 MW`.
  static String power(double? w, {bool signed = false}) {
    if (w == null) return '–';
    final sign = signed && w > 0 ? '+' : '';
    final a = w.abs();
    if (a >= 1e6) return '$sign${_two.format(w / 1e6)} MW';
    if (a >= 1e3) return '$sign${_one.format(w / 1e3)} kW';
    return '$sign${_int.format(w)} W';
  }

  /// kWh → `12.5 kWh`, `3.42 MWh`, `1.20 GWh`.
  static String energy(double? kwh) {
    if (kwh == null) return '–';
    final a = kwh.abs();
    if (a >= 1e6) return '${_two.format(kwh / 1e6)} GWh';
    if (a >= 1e3) return '${_two.format(kwh / 1e3)} MWh';
    return '${_one.format(kwh)} kWh';
  }

  /// kWp → `8.2 kWp`, `1.35 MWp`.
  static String capacity(double? kwp) {
    if (kwp == null) return '–';
    if (kwp.abs() >= 1e3) return '${_two.format(kwp / 1e3)} MWp';
    return '${_one.format(kwp)} kWp';
  }

  static String percent(double? v, {int decimals = 0}) {
    if (v == null || v.isNaN) return '–';
    return '${v.toStringAsFixed(decimals)} %';
  }

  /// Ratio 0..1 → percent.
  static String ratio(double? v, {int decimals = 0}) => v == null || v.isNaN ? '–' : percent(v * 100, decimals: decimals);

  static String co2(double? kg) {
    if (kg == null) return '–';
    if (kg.abs() >= 1e3) return '${_one.format(kg / 1e3)} t CO₂';
    return '${_int.format(kg)} kg CO₂';
  }

  static String litres(double? l) {
    if (l == null) return '–';
    if (l.abs() >= 1e3) return '${_one.format(l / 1e3)} kL';
    return '${_int.format(l)} L';
  }

  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _shortDate = DateFormat('d MMM');
  static final DateFormat _month = DateFormat('MMM yyyy');

  static DateTime fromEpoch(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000);

  static String dateTime(int? ts) => ts == null ? '–' : _dateTime.format(fromEpoch(ts));
  static String date(int? ts) => ts == null ? '–' : _date.format(fromEpoch(ts));
  static String time(int? ts) => ts == null ? '–' : _time.format(fromEpoch(ts));
  static String shortDate(DateTime d) => _shortDate.format(d);
  static String month(DateTime d) => _month.format(d);

  /// `yyyy-MM-dd` → `12 Mar`.
  static String shortDay(String ymd) {
    final d = DateTime.tryParse(ymd);
    return d == null ? ymd : _shortDate.format(d);
  }

  /// `yyyy-MM` → `Mar 2025`.
  static String monthLabel(String ym) {
    final d = DateTime.tryParse('$ym-01');
    return d == null ? ym : _month.format(d);
  }

  /// "3 min ago", "2 h ago", "5 d ago".
  static String ago(int? ts, {DateTime? now}) {
    if (ts == null) return 'never';
    final n = now ?? DateTime.now();
    final d = n.difference(fromEpoch(ts));
    if (d.isNegative) return 'just now';
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  static String duration(Duration? d) {
    if (d == null) return '–';
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    if (d.inHours < 24) return '${d.inHours} h ${d.inMinutes % 60} min';
    return '${d.inDays} d ${d.inHours % 24} h';
  }
}
