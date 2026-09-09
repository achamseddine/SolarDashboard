import '../../core/models/fleet_insights.dart';
import '../../core/models/station.dart';
import '../../core/sync/station_region.dart';

/// Sort keys of the schools table.
enum StationSort {
  name('Name'),
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
    this.sort = StationSort.name,
    this.ascending = true,
  });

  /// Builds the initial filter from route query parameters.
  factory StationFilter.fromRoute({String? query, String? region, String? status, String? filter}) {
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
    );
  }

  final String query;
  final String? region;
  final StationStatus? status;
  final bool withAlarms;
  final bool underPerforming;
  final bool lowSoc;
  final StationSort sort;
  final bool ascending;

  bool get hasActiveFilter => query.isNotEmpty || region != null || status != null || withAlarms || underPerforming || lowSoc;

  StationFilter copyWith({
    String? query,
    String? region,
    bool clearRegion = false,
    StationStatus? status,
    bool clearStatus = false,
    bool? withAlarms,
    bool? underPerforming,
    bool? lowSoc,
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
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
      );

  /// Returns the stations matching this filter, sorted.
  List<StationInsight> apply(List<StationInsight> all) {
    final q = query.trim().toLowerCase();
    final out = all.where((s) {
      if (region != null && s.region != region) return false;
      if (status != null && s.status != status) return false;
      if (withAlarms && s.activeAlerts == 0) return false;
      if (underPerforming && !s.isUnderPerformer) return false;
      if (lowSoc && (s.socNow == null || s.socNow! >= 20)) return false;
      if (q.isNotEmpty) {
        final hay = '${s.name} ${s.station.address ?? ''} ${s.region} ${s.station.caza ?? ''} ${s.id}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    out.sort(_comparator);
    return out;
  }

  int _comparator(StationInsight a, StationInsight b) {
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
