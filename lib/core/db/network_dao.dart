import 'package:sqflite/sqflite.dart';

import '../models/gwn.dart';

/// Reads and writes the GWN Cloud tables: networks, their managed devices,
/// the daily counters every usage indicator is derived from, per-SSID traffic
/// and the cloud's alarms.
class NetworkDao {
  NetworkDao(this.db);

  final DatabaseExecutor db;

  // --------------------------------------------------------------- networks

  Future<List<GwnNetwork>> getNetworks() async {
    final rows = await db.query('gwn_networks', orderBy: 'name');
    return rows.map(GwnNetwork.fromRow).toList();
  }

  /// Upserts networks, preserving any link already resolved for them.
  Future<void> upsertNetworks(List<GwnNetwork> networks) async {
    if (networks.isEmpty) return;
    final existing = {
      for (final r in await db.query('gwn_networks', columns: ['id', 'cerd', 'link_confidence']))
        r['id'] as String: (r['cerd'] as int?, (r['link_confidence'] as num?)?.toDouble()),
    };
    final batch = db is Database ? (db as Database).batch() : null;
    for (final n in networks) {
      final keep = existing[n.id];
      final row = (n.cerd == null && keep != null ? n.withLink(keep.$1, keep.$2) : n).toRow();
      if (batch != null) {
        batch.insert('gwn_networks', row, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await db.insert('gwn_networks', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch?.commit(noResult: true);
  }

  Future<void> setLink(String networkId, int? cerd, double? confidence) => db.update(
        'gwn_networks',
        {'cerd': cerd, 'link_confidence': confidence},
        where: 'id = ?',
        whereArgs: [networkId],
      );

  // ---------------------------------------------------------------- devices

  Future<List<GwnDevice>> getDevices({String? networkId}) async {
    final rows = await db.query(
      'gwn_devices',
      where: networkId == null ? null : 'network_id = ?',
      whereArgs: networkId == null ? null : [networkId],
      orderBy: 'network_id, kind, name',
    );
    return rows.map(GwnDevice.fromRow).toList();
  }

  Future<void> upsertDevices(List<GwnDevice> devices) async {
    if (devices.isEmpty) return;
    await _replaceAll('gwn_devices', [for (final d in devices) d.toRow()]);
  }

  /// Drops devices no longer reported for the given networks, so a decommis-
  /// sioned AP stops counting against availability.
  Future<int> pruneDevices(String networkId, Set<String> keepMacs) async {
    if (keepMacs.isEmpty) return db.delete('gwn_devices', where: 'network_id = ?', whereArgs: [networkId]);
    final marks = List.filled(keepMacs.length, '?').join(',');
    return db.delete(
      'gwn_devices',
      where: 'network_id = ? AND mac NOT IN ($marks)',
      whereArgs: [networkId, ...keepMacs],
    );
  }

  // ------------------------------------------------------------ daily rows

  Future<List<GwnNetworkDay>> getDaily({String? networkId, String? fromDay, String? toDay}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (networkId != null) {
      where.add('network_id = ?');
      args.add(networkId);
    }
    if (fromDay != null) {
      where.add('day >= ?');
      args.add(fromDay);
    }
    if (toDay != null) {
      where.add('day <= ?');
      args.add(toDay);
    }
    final rows = await db.query(
      'gwn_network_daily',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'day',
    );
    return rows.map(GwnNetworkDay.fromRow).toList();
  }

  Future<void> upsertDaily(List<GwnNetworkDay> days) async {
    if (days.isEmpty) return;
    await _replaceAll('gwn_network_daily', [for (final d in days) d.toRow()]);
  }

  /// Folds one live observation into the day's row.
  ///
  /// The cloud exposes no history, so a day is built from repeated looks:
  /// the peak client count is the highest seen, traffic and AP counts take
  /// the latest reading, and uptime is the share of observations that found
  /// the network up. Replacing the row instead would keep only the last look
  /// and lose the day.
  Future<void> recordObservation(GwnNetworkDay seen, {required bool online}) async {
    final rows = await db.query(
      'gwn_network_daily',
      where: 'network_id = ? AND day = ?',
      whereArgs: [seen.networkId, seen.day],
      limit: 1,
    );
    final prev = rows.isEmpty ? null : GwnNetworkDay.fromRow(rows.first);

    int? maxOf(int? a, int? b) => a == null ? b : (b == null ? a : (a > b ? a : b));

    final merged = GwnNetworkDay(
      networkId: seen.networkId,
      day: seen.day,
      wanUpMinutes: seen.wanUpMinutes ?? prev?.wanUpMinutes,
      expectedMinutes: seen.expectedMinutes ?? prev?.expectedMinutes,
      rxBytes: seen.rxBytes ?? prev?.rxBytes,
      txBytes: seen.txBytes ?? prev?.txBytes,
      uniqueClients: maxOf(seen.uniqueClients, prev?.uniqueClients),
      peakClients: maxOf(seen.peakClients, prev?.peakClients),
      apsOnline: maxOf(seen.apsOnline, prev?.apsOnline),
      apsTotal: seen.apsTotal ?? prev?.apsTotal,
      activeAps: maxOf(seen.activeAps, prev?.activeAps),
      teachingHoursBytes: seen.teachingHoursBytes ?? prev?.teachingHoursBytes,
      observations: (prev?.observations ?? 0) + 1,
      onlineObservations: (prev?.onlineObservations ?? 0) + (online ? 1 : 0),
    );
    await db.insert('gwn_network_daily', merged.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GwnSsidDay>> getSsidDaily({String? fromDay, String? toDay}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (fromDay != null) {
      where.add('day >= ?');
      args.add(fromDay);
    }
    if (toDay != null) {
      where.add('day <= ?');
      args.add(toDay);
    }
    final rows = await db.query(
      'gwn_ssid_daily',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
    return rows.map(GwnSsidDay.fromRow).toList();
  }

  Future<void> upsertSsidDaily(List<GwnSsidDay> rows) async {
    if (rows.isEmpty) return;
    await _replaceAll('gwn_ssid_daily', [for (final r in rows) r.toRow()]);
  }

  // ----------------------------------------------------------------- alarms

  Future<List<GwnAlarm>> getAlarms({bool openOnly = false, int limit = 500}) async {
    final rows = await db.query(
      'gwn_alarms',
      where: openOnly ? 'end_ts IS NULL' : null,
      orderBy: 'start_ts DESC',
      limit: limit,
    );
    return rows.map(GwnAlarm.fromRow).toList();
  }

  Future<void> upsertAlarms(List<GwnAlarm> alarms) async {
    if (alarms.isEmpty) return;
    await _replaceAll('gwn_alarms', [for (final a in alarms) a.toRow()]);
  }

  /// Deletes daily rows and closed alarms older than [beforeDay] / [beforeTs].
  Future<void> prune({required String beforeDay, required int beforeTs}) async {
    await db.delete('gwn_network_daily', where: 'day < ?', whereArgs: [beforeDay]);
    await db.delete('gwn_ssid_daily', where: 'day < ?', whereArgs: [beforeDay]);
    await db.delete('gwn_alarms', where: 'end_ts IS NOT NULL AND end_ts < ?', whereArgs: [beforeTs]);
  }

  Future<void> _replaceAll(String table, List<Map<String, Object?>> rows) async {
    final batch = db is Database ? (db as Database).batch() : null;
    for (final r in rows) {
      if (batch != null) {
        batch.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await db.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch?.commit(noResult: true);
  }
}
