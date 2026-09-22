import 'package:sqflite/sqflite.dart';

import '../api/json_utils.dart';
import '../models/station.dart';
import 'app_database.dart';

/// One day of fleet-wide energy (sum over stations).
class FleetEnergyDay {
  const FleetEnergyDay({
    required this.day,
    required this.stations,
    this.generationKwh = 0,
    this.consumptionKwh = 0,
    this.gridImportKwh = 0,
    this.gridExportKwh = 0,
    this.chargeKwh = 0,
    this.dischargeKwh = 0,
  });

  final String day;
  final int stations;
  final double generationKwh;
  final double consumptionKwh;
  final double gridImportKwh;
  final double gridExportKwh;
  final double chargeKwh;
  final double dischargeKwh;

  double get selfConsumedKwh => (generationKwh - gridExportKwh).clamp(0, double.infinity);
  double? get selfSufficiency => consumptionKwh < 1 ? null : ((consumptionKwh - gridImportKwh) / consumptionKwh).clamp(0, 1);
}

class StationDao {
  StationDao(this.db);
  final Database db;

  // ---------------------------------------------------------------- stations

  /// Inserts new stations and updates existing ones. Locally derived columns
  /// (`region`, `caza`, derived status, battery capacity override) are
  /// preserved when the incoming value is unknown. Marks all as seen now.
  Future<void> upsertStations(List<Station> stations, {int? now}) async {
    if (stations.isEmpty) return;
    final ts = now ?? nowEpoch();
    await db.transaction((txn) async {
      final existing = <int, Map<String, Object?>>{};
      for (final chunk in chunked(stations.map((s) => s.id).toList(), 500)) {
        final rows = await txn.query('stations',
            columns: ['id', 'region', 'caza', 'connection_status', 'last_update_ts', 'battery_capacity_kwh'],
            where: 'id IN (${placeholders(chunk.length)})',
            whereArgs: chunk);
        for (final r in rows) {
          existing[r['id'] as int] = r;
        }
      }
      final batch = txn.batch();
      for (final s in stations) {
        final prev = existing[s.id];
        var merged = s.copyWith(lastSeenAt: ts, archived: false);
        if (prev != null) {
          final prevTs = asInt(prev['last_update_ts']);
          merged = merged.copyWith(
            region: s.region ?? prev['region'] as String?,
            caza: s.caza ?? prev['caza'] as String?,
            status: StationStatus.fromDb(prev['connection_status'] as String?),
            lastUpdateTs: _maxTs(s.lastUpdateTs, prevTs),
            batteryCapacityKwh: s.batteryCapacityKwh ?? asDouble(prev['battery_capacity_kwh']),
          );
        }
        batch.insert('stations', merged.toRow(now: ts), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Marks stations that were not part of a fully successful list sweep as
  /// archived (never deleted). Returns the number archived.
  Future<int> archiveNotSeen(Set<int> seenIds) async {
    if (seenIds.isEmpty) return 0;
    var n = 0;
    await db.transaction((txn) async {
      final rows = await txn.query('stations', columns: ['id'], where: 'archived = 0');
      final toArchive = [for (final r in rows) if (!seenIds.contains(r['id'] as int)) r['id'] as int];
      for (final chunk in chunked(toArchive, 500)) {
        n += await txn.update('stations', {'archived': 1}, where: 'id IN (${placeholders(chunk.length)})', whereArgs: chunk);
      }
    });
    return n;
  }

  Future<List<Station>> getStations({
    String? region,
    StationStatus? status,
    String? search,
    bool includeArchived = false,
    String orderBy = 'name COLLATE NOCASE',
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('archived = 0');
    if (region != null) {
      if (region == LebanonRegionsUnassigned.value) {
        where.add('region IS NULL');
      } else {
        where.add('region = ?');
        args.add(region);
      }
    }
    if (status != null) {
      where.add('connection_status = ?');
      args.add(status.db);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR address LIKE ? OR CAST(id AS TEXT) LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await db.query('stations', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: orderBy);
    return rows.map(Station.fromRow).toList();
  }

  Future<Station?> getStation(int id) async {
    final rows = await db.query('stations', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Station.fromRow(rows.first);
  }

  Future<List<int>> getStationIds({bool includeArchived = false}) async {
    final rows = await db.query('stations', columns: ['id'], where: includeArchived ? null : 'archived = 0', orderBy: 'id');
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<int> countStations({bool includeArchived = false}) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stations${includeArchived ? '' : ' WHERE archived = 0'}')) ?? 0;

  /// Bulk derived-status update: id → (status, lastUpdateTs).
  Future<void> updateStatuses(Map<int, (StationStatus, int?)> updates) async {
    if (updates.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      updates.forEach((id, v) {
        batch.update('stations', {'connection_status': v.$1.db, 'last_update_ts': ?v.$2}, where: 'id = ?', whereArgs: [id]);
      });
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateRegion(int id, {String? region, String? caza}) async {
    await db.update('stations', {'region': region, 'caza': caza}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateRegions(Map<int, (String?, String?)> regions) async {
    if (regions.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      regions.forEach((id, v) => batch.update('stations', {'region': v.$1, 'caza': v.$2}, where: 'id = ?', whereArgs: [id]));
      await batch.commit(noResult: true);
    });
  }

  Future<void> setBatteryCapacity(int id, double? kwh) async {
    await db.update('stations', {'battery_capacity_kwh': kwh}, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ latest

  /// Upserts `station_latest` rows. A row with older data than the stored one
  /// only refreshes `fetched_at` and error fields; today's counters are kept
  /// when the incoming row has none.
  Future<void> upsertLatest(List<StationLatest> rows) async {
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final existing = <int, StationLatest>{};
      for (final chunk in chunked(rows.map((r) => r.stationId).toList(), 500)) {
        final found = await txn.query('station_latest', where: 'station_id IN (${placeholders(chunk.length)})', whereArgs: chunk);
        for (final r in found) {
          existing[r['station_id'] as int] = StationLatest.fromRow(r);
        }
      }
      final batch = txn.batch();
      for (final r in rows) {
        final prev = existing[r.stationId];
        var merged = r;
        if (prev != null) {
          final incomingNewer = r.dataTs != null && (prev.dataTs == null || r.dataTs! >= prev.dataTs!);
          merged = StationLatest(
            stationId: r.stationId,
            dataTs: incomingNewer ? r.dataTs : prev.dataTs,
            fetchedAt: r.fetchedAt,
            source: incomingNewer ? r.source : prev.source,
            snapshot: incomingNewer ? (r.snapshot ?? prev.snapshot) : prev.snapshot,
            today: r.today.isEmpty ? prev.today : r.today,
            lastErrorAt: r.lastErrorAt,
            lastErrorMsg: r.lastErrorMsg,
            raw: incomingNewer ? (r.raw ?? prev.raw) : prev.raw,
          );
        }
        batch.insert('station_latest', merged.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<StationLatest?> getLatest(int stationId) async {
    final rows = await db.query('station_latest', where: 'station_id = ?', whereArgs: [stationId], limit: 1);
    return rows.isEmpty ? null : StationLatest.fromRow(rows.first);
  }

  Future<Map<int, StationLatest>> allLatest() async {
    final rows = await db.query('station_latest');
    return {for (final r in rows) r['station_id'] as int: StationLatest.fromRow(r)};
  }

  /// Records an API failure for a station without touching its data.
  Future<void> recordError(int stationId, String message, {int? now}) async {
    final ts = now ?? nowEpoch();
    final updated = await db.update('station_latest', {'last_error_at': ts, 'last_error_msg': message}, where: 'station_id = ?', whereArgs: [stationId]);
    if (updated == 0) {
      await db.insert('station_latest', StationLatest(stationId: stationId, fetchedAt: ts, lastErrorAt: ts, lastErrorMsg: message).toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // --------------------------------------------------------------- snapshots

  /// Stores snapshots keyed on (station_id, ts). Rich sources (`station`,
  /// `device`) replace an existing row at the same timestamp so the
  /// opportunistic `list` values or a `history` frame never hide the full
  /// power flow; `list`/`history` rows never overwrite. Returns rows written.
  Future<int> insertSnapshots(List<StationSnapshot> snaps) async {
    if (snaps.isEmpty) return 0;
    var written = 0;
    for (final chunk in chunked(snaps, 500)) {
      await db.transaction((txn) async {
        final batch = txn.batch();
        final seen = <String>{};
        var ops = 0;
        for (final s in chunk) {
          if (s.isEmpty) continue;
          final k = '${s.stationId}:${s.ts}';
          if (!seen.add(k)) continue;
          final rich = s.source == SnapshotSource.station || s.source == SnapshotSource.device || s.source == SnapshotSource.demo;
          batch.insert('station_snapshots', s.toRow(), conflictAlgorithm: rich ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore);
          ops++;
        }
        if (ops == 0) return;
        final results = await batch.commit(continueOnError: true);
        for (final r in results) {
          if (r is int && r > 0) written++;
        }
      });
    }
    return written;
  }

  Future<StationSnapshot?> latestSnapshot(int stationId) async {
    final rows = await db.query('station_snapshots', where: 'station_id = ?', whereArgs: [stationId], orderBy: 'ts DESC', limit: 1);
    return rows.isEmpty ? null : StationSnapshot.fromRow(rows.first);
  }

  Future<List<StationSnapshot>> snapshotsBetween(int stationId, int fromTs, int toTs) async {
    final rows = await db.query('station_snapshots',
        where: 'station_id = ? AND ts >= ? AND ts <= ?', whereArgs: [stationId, fromTs, toTs], orderBy: 'ts');
    return rows.map(StationSnapshot.fromRow).toList();
  }

  /// Number of snapshots per station within a time range.
  /// Mean generation (W) per hour of the local day for every station, as a
  /// compact trend series. One query for the whole fleet — the plants list
  /// draws 200+ sparklines and cannot afford a query per row.
  Future<Map<int, List<double>>> generationTrends(int fromTs, int toTs, {int buckets = 24}) async {
    final span = (toTs - fromTs).clamp(1, 86400 * 2);
    final width = (span / buckets).ceil().clamp(1, span);
    final rows = await db.rawQuery('''
      SELECT station_id, ((ts - ?) / ?) AS b, AVG(generation_w) AS w
      FROM station_snapshots
      WHERE ts >= ? AND ts <= ? AND generation_w IS NOT NULL
      GROUP BY station_id, b ORDER BY station_id, b''', [fromTs, width, fromTs, toTs]);
    final out = <int, List<double>>{};
    for (final r in rows) {
      final id = (r['station_id'] as num).toInt();
      final b = ((r['b'] as num?)?.toInt() ?? 0).clamp(0, buckets - 1);
      final list = out.putIfAbsent(id, () => List<double>.filled(buckets, 0));
      list[b] = (r['w'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  Future<Map<int, int>> snapshotCounts(int fromTs, int toTs) async {
    final rows = await db.rawQuery('SELECT station_id, COUNT(*) n FROM station_snapshots WHERE ts >= ? AND ts <= ? GROUP BY station_id', [fromTs, toTs]);
    return {for (final r in rows) r['station_id'] as int: asInt(r['n']) ?? 0};
  }

  Future<int> countSnapshots() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM station_snapshots')) ?? 0;

  // ----------------------------------------------------------------- buckets

  Future<void> upsertBuckets(List<PowerBucket> buckets) async {
    if (buckets.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final b in buckets) {
        batch.insert('power_buckets', b.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Buckets for the fleet (`region == ''`) or one governorate.
  Future<List<PowerBucket>> bucketsBetween(int fromTs, int toTs, {String region = ''}) async {
    final rows = await db.query('power_buckets',
        where: 'region = ? AND bucket_ts >= ? AND bucket_ts <= ?', whereArgs: [region, fromTs, toTs], orderBy: 'bucket_ts');
    return rows.map(PowerBucket.fromRow).toList();
  }

  // ------------------------------------------------------------------ energy

  /// Upserts daily rows. Rules: a `history` row always replaces a `counter`
  /// row; a `counter` row never replaces a `history` row; a `counter` row only
  /// replaces a `counter` row when its generation is not lower (counter
  /// resets around midnight would otherwise wipe the day).
  Future<int> upsertDaily(List<StationEnergy> rows) async {
    if (rows.isEmpty) return 0;
    var written = 0;
    await db.transaction((txn) async {
      final existing = <String, StationEnergy>{};
      for (final chunk in chunked(rows, 300)) {
        final where = chunk.map((_) => '(station_id = ? AND day = ?)').join(' OR ');
        final args = <Object?>[for (final r in chunk) ...[r.stationId, r.period]];
        final found = await txn.query('station_daily', where: where, whereArgs: args);
        for (final r in found) {
          final e = StationEnergy.fromRow(r);
          existing['${e.stationId}:${e.period}'] = e;
        }
      }
      final batch = txn.batch();
      for (final r in rows) {
        final prev = existing['${r.stationId}:${r.period}'];
        if (prev != null) {
          if (r.source == EnergySource.counter && prev.source == EnergySource.history) continue;
          if (r.source == EnergySource.counter && prev.source == EnergySource.counter && (r.generationKwh ?? 0) < (prev.generationKwh ?? 0) - 0.01) continue;
        }
        final merged = r.copyWith(completenessPct: r.completenessPct ?? prev?.completenessPct, fullPowerHours: r.fullPowerHours ?? prev?.fullPowerHours);
        batch.insert('station_daily', merged.toRow(monthly: false), conflictAlgorithm: ConflictAlgorithm.replace);
        written++;
      }
      await batch.commit(noResult: true);
    });
    return written;
  }

  Future<void> upsertMonthly(List<StationEnergy> rows) async {
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert('station_monthly', r.toRow(monthly: true), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateCompleteness(Map<int, double> pctByStation, String day) async {
    if (pctByStation.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      pctByStation.forEach((id, pct) => batch.update('station_daily', {'completeness_pct': pct}, where: 'station_id = ? AND day = ?', whereArgs: [id, day]));
      await batch.commit(noResult: true);
    });
  }

  Future<List<StationEnergy>> dailyBetween(int stationId, String fromDay, String toDay) async {
    final rows = await db.query('station_daily',
        where: 'station_id = ? AND day >= ? AND day <= ?', whereArgs: [stationId, fromDay, toDay], orderBy: 'day');
    return rows.map(StationEnergy.fromRow).toList();
  }

  Future<List<StationEnergy>> monthlyBetween(int stationId, String fromMonth, String toMonth) async {
    final rows = await db.query('station_monthly',
        where: 'station_id = ? AND month >= ? AND month <= ?', whereArgs: [stationId, fromMonth, toMonth], orderBy: 'month');
    return rows.map(StationEnergy.fromRow).toList();
  }

  /// Days that already have a history row for a station in a range.
  Future<Set<String>> daysWithHistory(int stationId, String fromDay, String toDay) async {
    final rows = await db.query('station_daily',
        columns: ['day'], where: "station_id = ? AND day >= ? AND day <= ? AND source = 'history'", whereArgs: [stationId, fromDay, toDay]);
    return rows.map((r) => r['day'] as String).toSet();
  }

  /// All stations' energy for one day (for rankings / specific yield).
  Future<Map<int, StationEnergy>> dailyForDay(String day) async {
    final rows = await db.query('station_daily', where: 'day = ?', whereArgs: [day]);
    return {for (final r in rows) r['station_id'] as int: StationEnergy.fromRow(r)};
  }

  /// Per-station sums over a day range (also counts days with data).
  Future<Map<int, StationEnergy>> dailySumsPerStation(String fromDay, String toDay) async {
    final rows = await db.rawQuery('''
      SELECT station_id, COUNT(*) n, SUM(generation_kwh) g, SUM(consumption_kwh) c, SUM(grid_export_kwh) ge, SUM(grid_import_kwh) gi,
             SUM(charge_kwh) ch, SUM(discharge_kwh) dc, SUM(full_power_hours) fph, AVG(completeness_pct) cp
      FROM station_daily WHERE day >= ? AND day <= ? GROUP BY station_id
    ''', [fromDay, toDay]);
    return {
      for (final r in rows)
        r['station_id'] as int: StationEnergy(
          stationId: r['station_id'] as int,
          period: '$fromDay..$toDay',
          generationKwh: asDouble(r['g']),
          consumptionKwh: asDouble(r['c']),
          gridExportKwh: asDouble(r['ge']),
          gridImportKwh: asDouble(r['gi']),
          chargeKwh: asDouble(r['ch']),
          dischargeKwh: asDouble(r['dc']),
          fullPowerHours: asDouble(r['fph']),
          completenessPct: asDouble(r['cp']),
        ),
    };
  }

  /// Number of days with data per station in a range.
  Future<Map<int, int>> dailyDayCounts(String fromDay, String toDay) async {
    final rows = await db.rawQuery('SELECT station_id, COUNT(*) n FROM station_daily WHERE day >= ? AND day <= ? GROUP BY station_id', [fromDay, toDay]);
    return {for (final r in rows) r['station_id'] as int: asInt(r['n']) ?? 0};
  }

  /// Fleet totals per day.
  Future<List<FleetEnergyDay>> fleetDailySeries(String fromDay, String toDay, {List<int>? stationIds}) async {
    final idFilter = stationIds == null || stationIds.isEmpty ? '' : 'AND station_id IN (${stationIds.join(',')})';
    final rows = await db.rawQuery('''
      SELECT day, COUNT(*) n, SUM(generation_kwh) g, SUM(consumption_kwh) c, SUM(grid_import_kwh) gi, SUM(grid_export_kwh) ge,
             SUM(charge_kwh) ch, SUM(discharge_kwh) dc
      FROM station_daily WHERE day >= ? AND day <= ? $idFilter GROUP BY day ORDER BY day
    ''', [fromDay, toDay]);
    return rows.map(_energyDay).toList();
  }

  /// Fleet totals per month (from `station_monthly`).
  Future<List<FleetEnergyDay>> fleetMonthlySeries(String fromMonth, String toMonth) async {
    final rows = await db.rawQuery('''
      SELECT month AS day, COUNT(*) n, SUM(generation_kwh) g, SUM(consumption_kwh) c, SUM(grid_import_kwh) gi, SUM(grid_export_kwh) ge,
             SUM(charge_kwh) ch, SUM(discharge_kwh) dc
      FROM station_monthly WHERE month >= ? AND month <= ? GROUP BY month ORDER BY month
    ''', [fromMonth, toMonth]);
    return rows.map(_energyDay).toList();
  }

  /// Lifetime totals from monthly rows.
  Future<FleetEnergyDay> lifetimeTotals() async {
    final rows = await db.rawQuery('''
      SELECT 'all' AS day, COUNT(DISTINCT station_id) n, SUM(generation_kwh) g, SUM(consumption_kwh) c, SUM(grid_import_kwh) gi, SUM(grid_export_kwh) ge,
             SUM(charge_kwh) ch, SUM(discharge_kwh) dc FROM station_monthly
    ''');
    return rows.isEmpty ? const FleetEnergyDay(day: 'all', stations: 0) : _energyDay(rows.first);
  }

  FleetEnergyDay _energyDay(Map<String, Object?> r) => FleetEnergyDay(
        day: r['day'] as String,
        stations: asInt(r['n']) ?? 0,
        generationKwh: asDouble(r['g']) ?? 0,
        consumptionKwh: asDouble(r['c']) ?? 0,
        gridImportKwh: asDouble(r['gi']) ?? 0,
        gridExportKwh: asDouble(r['ge']) ?? 0,
        chargeKwh: asDouble(r['ch']) ?? 0,
        dischargeKwh: asDouble(r['dc']) ?? 0,
      );

  // ----------------------------------------------------------- status events

  /// Records the derived status of many stations at [ts]. A new event row is
  /// opened only when the status changed; the previous open event is closed.
  Future<int> recordStatuses(Map<int, StationStatus> statuses, {required int ts, String source = 'derived'}) async {
    if (statuses.isEmpty) return 0;
    var transitions = 0;
    await db.transaction((txn) async {
      final open = <int, Map<String, Object?>>{};
      final rows = await txn.query('station_status_events', where: 'end_ts IS NULL');
      for (final r in rows) {
        open[r['station_id'] as int] = r;
      }
      final batch = txn.batch();
      statuses.forEach((id, status) {
        final cur = open[id];
        if (cur != null && StationStatus.fromDb(cur['status'] as String?) == status) return;
        if (cur != null) {
          batch.update('station_status_events', {'end_ts': ts}, where: 'station_id = ? AND start_ts = ?', whereArgs: [id, cur['start_ts']]);
        }
        batch.insert('station_status_events', StatusEvent(stationId: id, status: status, startTs: ts, source: source).toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        transitions++;
      });
      await batch.commit(noResult: true);
    });
    return transitions;
  }

  /// Open (current) status event per station.
  Future<Map<int, StatusEvent>> currentStatusEvents() async {
    final rows = await db.query('station_status_events', where: 'end_ts IS NULL');
    return {for (final r in rows) r['station_id'] as int: StatusEvent.fromRow(r)};
  }

  /// Events overlapping [fromTs, toTs] (all stations or one).
  Future<List<StatusEvent>> statusEventsBetween(int fromTs, int toTs, {int? stationId}) async {
    final rows = await db.query('station_status_events',
        where: '${stationId == null ? '' : 'station_id = ? AND '}start_ts <= ? AND (end_ts IS NULL OR end_ts >= ?)',
        whereArgs: [?stationId, toTs, fromTs],
        orderBy: 'station_id, start_ts');
    return rows.map(StatusEvent.fromRow).toList();
  }

  // ----------------------------------------------------------- battery daily

  Future<void> upsertBatteryDays(List<BatteryDay> rows) async {
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert('station_battery_daily', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<BatteryDay>> batteryDaysBetween(int stationId, String fromDay, String toDay) async {
    final rows = await db.query('station_battery_daily',
        where: 'station_id = ? AND day >= ? AND day <= ?', whereArgs: [stationId, fromDay, toDay], orderBy: 'day');
    return rows.map(BatteryDay.fromRow).toList();
  }

  Future<Map<int, BatteryDay>> batteryDayForAll(String day) async {
    final rows = await db.query('station_battery_daily', where: 'day = ?', whereArgs: [day]);
    return {for (final r in rows) r['station_id'] as int: BatteryDay.fromRow(r)};
  }

  static int? _maxTs(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }
}

/// Sentinel used to filter stations without a resolved region.
class LebanonRegionsUnassigned {
  static const value = 'Unassigned';
}
