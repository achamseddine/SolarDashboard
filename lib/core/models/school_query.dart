import 'school.dart';
import 'school_insights.dart';

/// Sort keys of the school directory.
enum SchoolSort {
  name('Name'),
  cerd('CERD'),
  region('Governorate'),
  students('Students'),
  connectivity('Internet'),
  solarStatus('Solar status'),
  kwp('Installed kWp'),
  auditedLoad('Audited load'),
  attendance('Attendance');

  const SchoolSort(this.label);
  final String label;
}

/// Tri-state filter: null = any.
typedef Tri = bool?;

/// Filter + sort state of the school directory (all MEHE schools, not only
/// the ones with a monitored plant).
class SchoolQuery {
  const SchoolQuery({
    this.search = '',
    this.region,
    this.caza,
    this.ownership,
    this.connected,
    this.solarized,
    this.solarStatus,
    this.monitored,
    this.hasAudit,
    this.secondShift,
    this.sort = SchoolSort.name,
    this.ascending = true,
    this.inMasterOnly = false,
  });

  /// Builds the initial query from route parameters.
  factory SchoolQuery.fromRoute({String? query, String? region, String? caza, String? connected, String? solar, String? monitored, String? filter, String? master}) {
    Tri tri(String? v) => v == null || v.isEmpty ? null : (v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'yes');
    final f = (filter ?? '').trim().toLowerCase();
    return SchoolQuery(
      search: query?.trim() ?? '',
      region: (region ?? '').trim().isEmpty ? null : region!.trim(),
      caza: (caza ?? '').trim().isEmpty ? null : caza!.trim(),
      connected: f == 'notconnected' ? false : (f == 'connected' ? true : tri(connected)),
      solarized: f == 'solaronly' ? true : (f == 'nosolar' ? false : tri(solar)),
      monitored: f == 'unmonitored' ? false : tri(monitored),
      inMasterOnly: tri(master) ?? false,
    );
  }

  /// Restricts the list to the MEHE master list.
  ///
  /// The connectivity dashboards count master-list schools only, so a tile
  /// that opens the directory has to say so: without this the orphan
  /// connectivity records the page explicitly excludes from its figures come
  /// back in the list behind them.
  final bool inMasterOnly;

  final String search;
  final String? region;
  final String? caza;
  final String? ownership;

  /// On the internet-connectivity roll-out.
  final Tri connected;

  /// Solar system completed.
  final Tri solarized;
  final SolarStatus? solarStatus;

  /// Has a linked, monitored DeyeCloud plant.
  final Tri monitored;

  /// Has an energy-audit load estimate.
  final Tri hasAudit;

  /// Runs an afternoon (second) shift.
  final Tri secondShift;
  final SchoolSort sort;
  final bool ascending;

  bool get hasActiveFilter =>
      search.isNotEmpty ||
      region != null ||
      caza != null ||
      ownership != null ||
      connected != null ||
      solarized != null ||
      solarStatus != null ||
      monitored != null ||
      hasAudit != null ||
      secondShift != null;

  SchoolQuery copyWith({
    String? search,
    String? region,
    bool clearRegion = false,
    String? caza,
    bool clearCaza = false,
    String? ownership,
    bool clearOwnership = false,
    Tri connected,
    bool clearConnected = false,
    Tri solarized,
    bool clearSolarized = false,
    SolarStatus? solarStatus,
    bool clearSolarStatus = false,
    Tri monitored,
    bool clearMonitored = false,
    Tri hasAudit,
    bool clearAudit = false,
    Tri secondShift,
    bool clearSecondShift = false,
    SchoolSort? sort,
    bool? ascending,
  }) =>
      SchoolQuery(
        search: search ?? this.search,
        region: clearRegion ? null : (region ?? this.region),
        caza: clearCaza ? null : (caza ?? this.caza),
        ownership: clearOwnership ? null : (ownership ?? this.ownership),
        connected: clearConnected ? null : (connected ?? this.connected),
        solarized: clearSolarized ? null : (solarized ?? this.solarized),
        solarStatus: clearSolarStatus ? null : (solarStatus ?? this.solarStatus),
        monitored: clearMonitored ? null : (monitored ?? this.monitored),
        hasAudit: clearAudit ? null : (hasAudit ?? this.hasAudit),
        secondShift: clearSecondShift ? null : (secondShift ?? this.secondShift),
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
        inMasterOnly: inMasterOnly,
      );

  /// Applies the filters and the sort to [all].
  List<SchoolInsight> apply(List<SchoolInsight> all) {
    final q = search.trim().toLowerCase();
    final out = <SchoolInsight>[];
    for (final s in all) {
      final sc = s.school;
      if (!sc.inMaster && inMasterOnly) continue;
      if (!sc.inMaster && region == null && caza == null && q.isEmpty && !sc.connected && sc.solar == null) continue;
      if (region != null && s.region != region) continue;
      if (caza != null && sc.caza != caza) continue;
      if (ownership != null && sc.ownership != ownership) continue;
      if (connected != null && sc.connected != connected) continue;
      if (solarized != null && s.isSolarized != solarized) continue;
      if (solarStatus != null && sc.solarStatus != solarStatus) continue;
      if (monitored != null && s.isMonitored != monitored) continue;
      if (hasAudit != null && ((sc.annualLoadKwh ?? 0) > 0) != hasAudit) continue;
      if (secondShift != null && (sc.studentsPm != null && sc.studentsPm! > 0) != secondShift) continue;
      if (q.isNotEmpty) {
        final hay = '${sc.name} ${sc.nameAr ?? ''} ${sc.solar?.listedName ?? ''} ${sc.cerd} ${sc.caza ?? ''} ${sc.cadaster ?? ''} ${s.region} ${sc.address ?? ''}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(s);
    }
    out.sort(_comparator);
    return out;
  }

  int _comparator(SchoolInsight a, SchoolInsight b) {
    final dir = ascending ? 1 : -1;
    int byName() => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    int nullsLast(num? x, num? y) {
      if (x == null && y == null) return byName();
      if (x == null) return 1;
      if (y == null) return -1;
      final c = x.compareTo(y) * dir;
      return c != 0 ? c : byName();
    }

    switch (sort) {
      case SchoolSort.name:
        return byName() * dir;
      case SchoolSort.cerd:
        return a.cerd.compareTo(b.cerd) * dir;
      case SchoolSort.region:
        final c = a.region.compareTo(b.region) * dir;
        return c != 0 ? c : byName();
      case SchoolSort.students:
        return nullsLast(a.students, b.students);
      case SchoolSort.connectivity:
        final c = (a.isConnected ? 1 : 0).compareTo(b.isConnected ? 1 : 0) * dir;
        return c != 0 ? c : byName();
      case SchoolSort.solarStatus:
        final c = (a.school.solarStatus?.index ?? 99).compareTo(b.school.solarStatus?.index ?? 99) * dir;
        return c != 0 ? c : byName();
      case SchoolSort.kwp:
        return nullsLast(a.kwp, b.kwp);
      case SchoolSort.auditedLoad:
        return nullsLast(a.annualLoadKwh, b.annualLoadKwh);
      case SchoolSort.attendance:
        return nullsLast(a.attendance, b.attendance);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SchoolQuery &&
      other.search == search &&
      other.region == region &&
      other.caza == caza &&
      other.ownership == ownership &&
      other.connected == connected &&
      other.solarized == solarized &&
      other.solarStatus == solarStatus &&
      other.monitored == monitored &&
      other.hasAudit == hasAudit &&
      other.secondShift == secondShift &&
      other.sort == sort &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(search, region, caza, ownership, connected, solarized, solarStatus, monitored, hasAudit, secondShift, sort, ascending);
}
