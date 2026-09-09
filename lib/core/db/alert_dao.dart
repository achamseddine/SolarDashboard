import 'package:sqflite/sqflite.dart';

import '../api/json_utils.dart';
import '../models/alert.dart';
import 'app_database.dart';

class AlertNameCount {
  const AlertNameCount(this.name, this.count);
  final String name;
  final int count;
}

class StationAlertCount {
  const StationAlertCount(this.stationId, this.stationName, this.count, this.highest);
  final int stationId;
  final String? stationName;
  final int count;
  final AlertLevel highest;
}

class AlertDao {
  AlertDao(this.db);
  final Database db;

  /// Inserts new alerts and updates existing ones, keeping the local
  /// `acknowledged` flag and `first_seen_at`. Returns the number of new rows.
  Future<int> upsertAlerts(List<SolarAlert> alerts) async {
    if (alerts.isEmpty) return 0;
    var inserted = 0;
    await db.transaction((txn) async {
      final existing = <String, Map<String, Object?>>{};
      for (final chunk in chunked(alerts.map((a) => a.id).toList(), 500)) {
        final rows = await txn.query('alerts',
            columns: ['id', 'acknowledged', 'first_seen_at', 'status', 'end_ts'],
            where: 'id IN (${placeholders(chunk.length)})',
            whereArgs: chunk);
        for (final r in rows) {
          existing[r['id'] as String] = r;
        }
      }
      final batch = txn.batch();
      for (final a in alerts) {
        final prev = existing[a.id];
        final row = a.toRow();
        if (prev == null) {
          inserted++;
        } else {
          row['acknowledged'] = prev['acknowledged'];
          row['first_seen_at'] = prev['first_seen_at'];
          // Never re-open an alert the cloud already reported as recovered.
          if ((prev['status'] as String?) == 'RECOVERED' && a.status == AlertStatus.active) {
            row['status'] = 'RECOVERED';
            row['end_ts'] = prev['end_ts'];
          }
        }
        batch.insert('alerts', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    return inserted;
  }

  Future<List<SolarAlert>> activeAlerts({AlertLevel? minLevel, int? stationId, bool includeAcknowledged = true, int limit = 2000}) async {
    final where = <String>['status = ?'];
    final args = <Object?>['ACTIVE'];
    if (minLevel != null) {
      where.add('level >= ?');
      args.add(minLevel.value);
    }
    if (stationId != null) {
      where.add('station_id = ?');
      args.add(stationId);
    }
    if (!includeAcknowledged) where.add('acknowledged = 0');
    final rows = await db.query('alerts', where: where.join(' AND '), whereArgs: args, orderBy: 'level DESC, start_ts DESC', limit: limit);
    return rows.map(SolarAlert.fromRow).toList();
  }

  Future<List<SolarAlert>> alerts({
    AlertStatus? status,
    AlertLevel? level,
    AlertSource? source,
    int? stationId,
    String? search,
    int? sinceTs,
    bool unacknowledgedOnly = false,
    int limit = 500,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status.db);
    }
    if (level != null) {
      where.add('level = ?');
      args.add(level.value);
    }
    if (source != null) {
      where.add('source = ?');
      args.add(source.db);
    }
    if (stationId != null) {
      where.add('station_id = ?');
      args.add(stationId);
    }
    if (sinceTs != null) {
      where.add('COALESCE(start_ts, first_seen_at) >= ?');
      args.add(sinceTs);
    }
    if (unacknowledgedOnly) where.add('acknowledged = 0');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR code LIKE ? OR station_name LIKE ? OR device_sn LIKE ? OR description LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q, q, q]);
    }
    final rows = await db.query('alerts',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: "CASE status WHEN 'ACTIVE' THEN 0 ELSE 1 END, level DESC, COALESCE(start_ts, first_seen_at) DESC",
        limit: limit,
        offset: offset);
    return rows.map(SolarAlert.fromRow).toList();
  }

  Future<List<SolarAlert>> alertsForStation(int stationId, {int limit = 200}) async {
    final rows = await db.query('alerts',
        where: 'station_id = ?', whereArgs: [stationId], orderBy: "CASE status WHEN 'ACTIVE' THEN 0 ELSE 1 END, level DESC, start_ts DESC", limit: limit);
    return rows.map(SolarAlert.fromRow).toList();
  }

  /// Ids of active alerts of a station from one source (for lifecycle).
  Future<List<SolarAlert>> activeForStation(int stationId, {AlertSource? source}) async {
    final rows = await db.query('alerts',
        where: "station_id = ? AND status = 'ACTIVE'${source == null ? '' : ' AND source = ?'}", whereArgs: [stationId, ?source?.db]);
    return rows.map(SolarAlert.fromRow).toList();
  }

  /// All active derived alerts keyed by id.
  Future<Map<String, SolarAlert>> activeDerived() async {
    final rows = await db.query('alerts', where: "status = 'ACTIVE' AND source = 'derived'");
    return {for (final r in rows) r['id'] as String: SolarAlert.fromRow(r)};
  }

  /// Oldest start of active cloud alerts per station (query-window lower bound).
  Future<Map<int, int>> oldestActiveStartPerStation() async {
    final rows = await db.rawQuery("SELECT station_id, MIN(COALESCE(start_ts, first_seen_at)) t FROM alerts WHERE status = 'ACTIVE' AND source = 'cloud' AND station_id IS NOT NULL GROUP BY station_id");
    return {for (final r in rows) r['station_id'] as int: asInt(r['t']) ?? 0};
  }

  Future<void> acknowledge(String id, {bool acknowledged = true}) async {
    await db.update('alerts', {'acknowledged': acknowledged ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> acknowledgeAll({int? stationId}) async {
    await db.update('alerts', {'acknowledged': 1},
        where: stationId == null ? 'status = ?' : 'status = ? AND station_id = ?', whereArgs: stationId == null ? ['ACTIVE'] : ['ACTIVE', stationId]);
  }

  /// Marks alerts as recovered at [endTs].
  Future<void> markRecovered(Iterable<String> ids, {required int endTs}) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    for (final chunk in chunked(list, 500)) {
      await db.update('alerts', {'status': 'RECOVERED', 'end_ts': endTs},
          where: "status = 'ACTIVE' AND id IN (${placeholders(chunk.length)})", whereArgs: chunk);
    }
  }

  /// Active alarm counts by level.
  Future<Map<AlertLevel, int>> activeCountsByLevel() async {
    final rows = await db.rawQuery("SELECT level, COUNT(*) n FROM alerts WHERE status = 'ACTIVE' GROUP BY level");
    return {for (final r in rows) AlertLevel.fromValue(asInt(r['level'])): asInt(r['n']) ?? 0};
  }

  /// Active alarm count per station: stationId → count.
  Future<Map<int, int>> activeCountPerStation() async {
    final rows = await db.rawQuery("SELECT station_id, COUNT(*) n FROM alerts WHERE status = 'ACTIVE' AND station_id IS NOT NULL GROUP BY station_id");
    return {for (final r in rows) r['station_id'] as int: asInt(r['n']) ?? 0};
  }

  /// Highest active level per station.
  Future<Map<int, AlertLevel>> highestActiveLevelPerStation() async {
    final rows = await db.rawQuery("SELECT station_id, MAX(level) l FROM alerts WHERE status = 'ACTIVE' AND station_id IS NOT NULL GROUP BY station_id");
    return {for (final r in rows) r['station_id'] as int: AlertLevel.fromValue(asInt(r['l']))};
  }

  Future<List<AlertNameCount>> topActiveNames({int limit = 8}) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(name, code, 'Unknown') n, COUNT(*) c FROM alerts WHERE status = 'ACTIVE' GROUP BY n ORDER BY c DESC LIMIT ?
    ''', [limit]);
    return rows.map((r) => AlertNameCount(r['n'] as String, asInt(r['c']) ?? 0)).toList();
  }

  Future<List<StationAlertCount>> stationsWithMostAlerts({int limit = 10}) async {
    final rows = await db.rawQuery('''
      SELECT a.station_id, COALESCE(s.name, a.station_name) sname, COUNT(*) c, MAX(a.level) lvl
      FROM alerts a LEFT JOIN stations s ON s.id = a.station_id
      WHERE a.status = 'ACTIVE' AND a.station_id IS NOT NULL
      GROUP BY a.station_id ORDER BY c DESC, lvl DESC LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => StationAlertCount(r['station_id'] as int, r['sname'] as String?, asInt(r['c']) ?? 0, AlertLevel.fromValue(asInt(r['lvl']))))
        .toList();
  }

  /// New alarms per local day for the last [days] days (trend chart).
  Future<Map<String, int>> newAlertsPerDay({int days = 14, int? now}) async {
    final since = (now ?? nowEpoch()) - days * 86400;
    final rows = await db.rawQuery('''
      SELECT date(COALESCE(start_ts, first_seen_at), 'unixepoch', 'localtime') d, COUNT(*) n
      FROM alerts WHERE COALESCE(start_ts, first_seen_at) >= ? GROUP BY d ORDER BY d
    ''', [since]);
    return {for (final r in rows) r['d'] as String: asInt(r['n']) ?? 0};
  }

  /// Mean/median time-to-recovery (seconds) of alarms recovered in the last [days].
  Future<(double?, double?)> recoveryStats({int days = 30, int? now}) async {
    final since = (now ?? nowEpoch()) - days * 86400;
    final rows = await db.rawQuery('''
      SELECT (end_ts - start_ts) d FROM alerts
      WHERE status = 'RECOVERED' AND end_ts IS NOT NULL AND start_ts IS NOT NULL AND end_ts >= start_ts AND end_ts >= ?
      ORDER BY d
    ''', [since]);
    if (rows.isEmpty) return (null, null);
    final ds = rows.map((r) => asDouble(r['d']) ?? 0).toList();
    final mean = ds.reduce((a, b) => a + b) / ds.length;
    final median = ds[ds.length ~/ 2];
    return (mean, median);
  }

  /// Active alarms open for more than [days] days.
  Future<int> countOpenLongerThan({int days = 7, int? now}) async {
    final cutoff = (now ?? nowEpoch()) - days * 86400;
    return Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM alerts WHERE status = 'ACTIVE' AND COALESCE(start_ts, first_seen_at) < ?", [cutoff])) ?? 0;
  }

  Future<int> countAlerts({bool activeOnly = false}) async =>
      Sqflite.firstIntValue(await db.rawQuery(activeOnly ? "SELECT COUNT(*) FROM alerts WHERE status = 'ACTIVE'" : 'SELECT COUNT(*) FROM alerts')) ?? 0;
}
