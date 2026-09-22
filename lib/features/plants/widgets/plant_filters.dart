import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';

/// The counter row of the DeyeCloud overview page, used here as table filters.
///
/// Every counter is computed over *all* plants of the account — the list is
/// never narrowed by governorate, school link or location type.
enum PlantCounter {
  total,
  online,
  offline,
  alarm,
  stale,
  unknown,
  partialOffline,
  withAlerts,
  noAlerts;

  /// The plant status this counter mirrors, for the five status counters.
  StationStatus? get status => switch (this) {
        PlantCounter.online => StationStatus.online,
        PlantCounter.offline => StationStatus.offline,
        PlantCounter.alarm => StationStatus.alarm,
        PlantCounter.stale => StationStatus.stale,
        PlantCounter.unknown => StationStatus.unknown,
        _ => null,
      };

  String get label => switch (this) {
        PlantCounter.total => 'Total',
        PlantCounter.partialOffline => 'Partial offline',
        PlantCounter.withAlerts => 'With alerts',
        PlantCounter.noAlerts => 'No alerts',
        _ => status!.label,
      };

  IconData get icon => switch (this) {
        PlantCounter.total => Icons.solar_power_outlined,
        PlantCounter.partialOffline => Icons.cloud_queue,
        PlantCounter.withAlerts => Icons.warning_amber_rounded,
        PlantCounter.noAlerts => Icons.verified_outlined,
        _ => AppColors.stationStatusIcon(status!),
      };

  Color get color => switch (this) {
        PlantCounter.total => AppColors.unicefCyan,
        PlantCounter.partialOffline => AppColors.warning,
        PlantCounter.withAlerts => AppColors.critical,
        PlantCounter.noAlerts => AppColors.good,
        _ => AppColors.stationStatus(status!),
      };

  /// Tooltip explaining what the counter means in DeyeCloud terms.
  String get hint => switch (this) {
        PlantCounter.total => 'Every plant of the account, whatever its location',
        PlantCounter.online => 'Communicating and reporting live data',
        PlantCounter.offline => 'No communication with the cloud',
        PlantCounter.alarm => 'Reporting, with an alarm state',
        PlantCounter.stale => 'Last data older than the stale threshold',
        PlantCounter.unknown => 'No status reported yet',
        PlantCounter.partialOffline => 'Plant reporting, but some of its devices are offline',
        PlantCounter.withAlerts => 'At least one active alarm',
        PlantCounter.noAlerts => 'No active alarm',
      };

  bool matches(StationInsight s) => switch (this) {
        PlantCounter.total => true,
        PlantCounter.partialOffline => s.isPartiallyOffline,
        PlantCounter.withAlerts => s.activeAlerts > 0,
        PlantCounter.noAlerts => s.activeAlerts == 0,
        _ => s.status == status,
      };

  /// Counter asked for by a deep link (`?status=offline`, `?filter=alarms`).
  static PlantCounter fromRoute({String? status, String? filter}) {
    final f = (filter ?? '').toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    switch (f) {
      case 'alarms':
      case 'alerts':
      case 'withalerts':
        return PlantCounter.withAlerts;
      case 'noalerts':
        return PlantCounter.noAlerts;
      case 'partial':
      case 'partialoffline':
        return PlantCounter.partialOffline;
    }
    final s = (status ?? '').toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    for (final c in PlantCounter.values) {
      if (c.status != null && (c.name.toLowerCase() == s || c.status!.label.toLowerCase().replaceAll(' ', '') == s)) return c;
    }
    return PlantCounter.total;
  }
}

/// How many plants each counter holds (always over the whole fleet).
Map<PlantCounter, int> countPlants(List<StationInsight> all) => {
      for (final c in PlantCounter.values) c: all.where(c.matches).length,
    };

/// Sortable table columns.
enum PlantSort { name, status, alerts, capacity, powerNow, dailyKwh, soc, lastData }

/// Search + counter + sort + paging state of the plants table.
@immutable
class PlantQuery {
  const PlantQuery({
    this.query = '',
    this.counter = PlantCounter.total,
    this.sort = PlantSort.name,
    this.ascending = true,
    this.pageSize = 50,
    this.page = 0,
  });

  final String query;
  final PlantCounter counter;
  final PlantSort sort;
  final bool ascending;

  /// Rows per page; `null` shows every matching plant on one page.
  final int? pageSize;

  /// Zero-based page index.
  final int page;

  /// Page sizes offered by the pager ("All" is the `null` entry).
  static const List<int?> pageSizes = [25, 50, 100, null];

  PlantQuery copyWith({
    String? query,
    PlantCounter? counter,
    PlantSort? sort,
    bool? ascending,
    int? pageSize,
    bool allRows = false,
    int? page,
  }) =>
      PlantQuery(
        query: query ?? this.query,
        counter: counter ?? this.counter,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
        pageSize: allRows ? null : (pageSize ?? this.pageSize),
        page: page ?? this.page,
      );

  bool get isFiltered => counter != PlantCounter.total || query.trim().isNotEmpty;

  /// Search + counter filter, then sort. Never drops a plant for a missing
  /// region, school link or address.
  List<StationInsight> apply(List<StationInsight> all) {
    final needle = query.trim().toLowerCase();
    final rows = <StationInsight>[
      for (final s in all)
        if (counter.matches(s) && (needle.isEmpty || _haystack(s).contains(needle))) s,
    ];
    rows.sort(compare);
    return rows;
  }

  static String _haystack(StationInsight s) => [
        s.name,
        '${s.id}',
        s.region,
        s.station.caza ?? '',
        s.station.address ?? '',
      ].join(' ').toLowerCase();

  /// Comparator for the active column; plants without the value sort last in
  /// both directions.
  int compare(StationInsight a, StationInsight b) {
    switch (sort) {
      case PlantSort.name:
        final r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return ascending ? r : -r;
      case PlantSort.status:
        final r = a.status.index.compareTo(b.status.index);
        return r != 0 ? (ascending ? r : -r) : a.name.compareTo(b.name);
      case PlantSort.alerts:
        return _num(a.activeAlerts, b.activeAlerts);
      case PlantSort.capacity:
        return _num(a.kwp, b.kwp);
      case PlantSort.powerNow:
        return _num(a.snapshot?.generationW, b.snapshot?.generationW);
      case PlantSort.dailyKwh:
        return _num(a.todayGenKwh, b.todayGenKwh);
      case PlantSort.soc:
        return _num(a.socNow, b.socNow);
      case PlantSort.lastData:
        return _num(lastDataTs(a), lastDataTs(b));
    }
  }

  int _num(num? a, num? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final r = a.compareTo(b);
    return ascending ? r : -r;
  }

  static int? lastDataTs(StationInsight s) => s.latest?.dataTs ?? s.station.lastUpdateTs;
}

/// One page of the filtered, sorted plant list.
@immutable
class PlantPage {
  const PlantPage({
    required this.rows,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.from,
    required this.to,
  });

  /// Cuts [matched] into the page asked for, clamping the index.
  factory PlantPage.of(List<StationInsight> matched, {int? pageSize, int page = 0}) {
    final total = matched.length;
    if (pageSize == null || pageSize <= 0 || total == 0) {
      return PlantPage(rows: matched, page: 0, pageCount: 1, total: total, from: total == 0 ? 0 : 1, to: total);
    }
    final pageCount = (total - 1) ~/ pageSize + 1;
    final p = page.clamp(0, pageCount - 1);
    final start = p * pageSize;
    final end = math.min(start + pageSize, total);
    return PlantPage(rows: matched.sublist(start, end), page: p, pageCount: pageCount, total: total, from: start + 1, to: end);
  }

  final List<StationInsight> rows;
  final int page;
  final int pageCount;
  final int total;

  /// 1-based index of the first / last row shown (0 when nothing matches).
  final int from;
  final int to;

  bool get hasPrevious => page > 0;
  bool get hasNext => page + 1 < pageCount;
  String get rangeLabel => total == 0 ? 'No plants to show' : 'Showing $from–$to of $total plants';
  String get pageLabel => 'Page ${page + 1} of $pageCount';
}
