import '../../core/models/fleet_insights.dart';
import '../../core/models/school.dart';
import '../../core/models/station.dart';
import '../../core/sync/station_region.dart';

/// Sort keys of the schools table.
enum StationSort {
  name('Name'),
  cerd('CERD'),
  status('Status'),
  generationNow('Generation now'),
  soc('Battery SOC'),
  todayKwh('Today kWh'),
  yield7d('Yield 7 d'),
  availability('Availability 7 d'),
  lastUpdate('Last update');

  const StationSort(this.label);
  final String label;
}

/// Region options offered in the filter dropdown (governorates + unassigned).
const List<String> stationRegionOptions = [...LebanonRegions.all, LebanonRegions.unassigned];

/// In-memory filter + sort state of the schools list.
class StationFilter {
  const StationFilter({
    this.query = '',
    this.region,
    this.status,
    this.withAlarms = false,
    this.underPerforming = false,
    this.lowSoc = false,
    this.connected,
    this.linked,
    this.sort = StationSort.name,
    this.ascending = true,
  });

  /// Builds the initial filter from route query parameters
  /// (`connected` / `linked` accept `1`/`0`, `true`/`false`, `yes`/`no`).
  factory StationFilter.fromRoute({String? query, String? region, String? status, String? filter, String? connected, String? linked}) {
    final st = status == null || status.trim().isEmpty ? null : StationStatus.fromDb(status.trim());
    final reg = region == null || region.trim().isEmpty ? null : region.trim();
    final f = (filter ?? '').trim().toLowerCase();
    return StationFilter(
      query: query?.trim() ?? '',
      region: reg,
      status: st,
      withAlarms: f == 'alarms',
      underPerforming: f == 'underperforming',
      lowSoc: f == 'lowsoc',
      connected: _flag(connected),
      linked: _flag(linked),
    );
  }

  static bool? _flag(String? v) {
    switch ((v ?? '').trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      case '0':
      case 'false':
      case 'no':
        return false;
      default:
        return null;
    }
  }

  final String query;
  final String? region;
  final StationStatus? status;
  final bool withAlarms;
  final bool underPerforming;
  final bool lowSoc;

  /// Linked school is (not) on the internet-connectivity roll-out; null = any.
  final bool? connected;

  /// Plant is (not) matched to a MEHE school record; null = any.
  final bool? linked;
  final StationSort sort;
  final bool ascending;

  bool get hasActiveFilter => query.isNotEmpty || region != null || status != null || withAlarms || underPerforming || lowSoc || connected != null || linked != null;

  StationFilter copyWith({
    String? query,
    String? region,
    bool clearRegion = false,
    StationStatus? status,
    bool clearStatus = false,
    bool? withAlarms,
    bool? underPerforming,
    bool? lowSoc,
    bool? connected,
    bool clearConnected = false,
    bool? linked,
    bool clearLinked = false,
    StationSort? sort,
    bool? ascending,
  }) =>
      StationFilter(
        query: query ?? this.query,
        region: clearRegion ? null : (region ?? this.region),
        status: clearStatus ? null : (status ?? this.status),
        withAlarms: withAlarms ?? this.withAlarms,
        underPerforming: underPerforming ?? this.underPerforming,
        lowSoc: lowSoc ?? this.lowSoc,
        connected: clearConnected ? null : (connected ?? this.connected),
        linked: clearLinked ? null : (linked ?? this.linked),
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
      );

  /// Returns the stations matching this filter, sorted. [schools] maps a
  /// station id to its linked MEHE school (used by the connectivity and link
  /// filters, the CERD sort and the search).
  List<StationInsight> apply(List<StationInsight> all, {Map<int, School> schools = const {}}) {
    final q = query.trim().toLowerCase();
    final out = all.where((s) {
      final school = schools[s.id];
      if (region != null && s.region != region) return false;
      if (status != null && s.status != status) return false;
      if (withAlarms && s.activeAlerts == 0) return false;
      if (underPerforming && !s.isUnderPerformer) return false;
      if (lowSoc && (s.socNow == null || s.socNow! >= 20)) return false;
      if (linked != null && (school != null) != linked) return false;
      if (connected != null && (school?.connected ?? false) != connected) return false;
      if (q.isNotEmpty) {
        final hay = [
          s.name,
          s.station.address ?? '',
          s.region,
          s.station.caza ?? '',
          '${s.id}',
          if (school != null) ...[school.name, school.nameAr ?? '', '${school.cerd}', school.solar?.listedName ?? ''],
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    out.sort((a, b) => _compare(a, b, schools));
    return out;
  }

  int _compare(StationInsight a, StationInsight b, Map<int, School> schools) {
    final dir = ascending ? 1 : -1;
    int byName() => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int nullsLast(num? x, num? y) {
      if (x == null && y == null) return byName();
      if (x == null) return 1; // nulls always at the end regardless of direction
      if (y == null) return -1;
      final c = x.compareTo(y) * dir;
      return c != 0 ? c : byName();
    }

    switch (sort) {
      case StationSort.name:
        return byName() * dir;
      case StationSort.cerd:
        return nullsLast(schools[a.id]?.cerd, schools[b.id]?.cerd);
      case StationSort.status:
        final c = a.status.index.compareTo(b.status.index) * dir;
        return c != 0 ? c : byName();
      case StationSort.generationNow:
        return nullsLast(a.snapshot?.generationW, b.snapshot?.generationW);
      case StationSort.soc:
        return nullsLast(a.socNow, b.socNow);
      case StationSort.todayKwh:
        return nullsLast(a.todayGenKwh, b.todayGenKwh);
      case StationSort.yield7d:
        return nullsLast(a.yield7d, b.yield7d);
      case StationSort.availability:
        return nullsLast(a.availability7d, b.availability7d);
      case StationSort.lastUpdate:
        return nullsLast(a.latest?.dataTs ?? a.station.lastUpdateTs, b.latest?.dataTs ?? b.station.lastUpdateTs);
    }
  }
}
