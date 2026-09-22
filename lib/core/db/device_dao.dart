import 'package:sqflite/sqflite.dart';

import '../api/json_utils.dart';
import '../models/device.dart';
import 'app_database.dart';

class DeviceDao {
  DeviceDao(this.db);
  final Database db;

  Future<void> upsertDevices(List<Device> devices, {int? now}) async {
    if (devices.isEmpty) return;
    final ts = now ?? nowEpoch();
    await db.transaction((txn) async {
      final existing = <String, Map<String, Object?>>{};
      for (final chunk in chunked(devices.map((d) => d.deviceSn).toList(), 500)) {
        final rows = await txn.query('devices',
            columns: ['device_sn', 'connect_status', 'collection_ts', 'station_id'],
            where: 'device_sn IN (${placeholders(chunk.length)})',
            whereArgs: chunk);
        for (final r in rows) {
          existing[r['device_sn'] as String] = r;
        }
      }
      final batch = txn.batch();
      for (final d in devices) {
        final prev = existing[d.deviceSn];
        var merged = d.copyWith(lastSeenAt: ts, archived: false);
        if (prev != null) {
          merged = merged.copyWith(
            status: d.status == DeviceStatus.unknown ? DeviceStatus.fromDb(prev['connect_status'] as String?) : d.status,
            collectionTs: d.collectionTs ?? asInt(prev['collection_ts']),
            stationId: d.stationId ?? asInt(prev['station_id']),
          );
        }
        batch.insert('devices', merged.toRow(now: ts), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> archiveNotSeen(Set<String> seenSns, {Set<int>? onlyStations}) async {
    if (seenSns.isEmpty) return 0;
    var n = 0;
    await db.transaction((txn) async {
      final rows = await txn.query('devices', columns: ['device_sn', 'station_id'], where: 'archived = 0');
      final toArchive = <String>[
        for (final r in rows)
          if (!seenSns.contains(r['device_sn'] as String) && (onlyStations == null || onlyStations.contains(asInt(r['station_id'])))) r['device_sn'] as String,
      ];
      for (final chunk in chunked(toArchive, 500)) {
        n += await txn.update('devices', {'archived': 1}, where: 'device_sn IN (${placeholders(chunk.length)})', whereArgs: chunk);
      }
    });
    return n;
  }

  Future<List<Device>> allDevices({String? deviceType, bool includeArchived = false}) async {
    final where = <String>[if (!includeArchived) 'archived = 0', if (deviceType != null) 'device_type = ?'];
    final rows = await db.query('devices',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: [?deviceType], orderBy: 'station_id, device_type, device_sn');
    return rows.map(Device.fromRow).toList();
  }

  Future<List<Device>> devicesForStation(int stationId, {bool includeArchived = false}) async {
    final rows = await db.query('devices',
        where: 'station_id = ?${includeArchived ? '' : ' AND archived = 0'}', whereArgs: [stationId], orderBy: 'device_type, device_sn');
    return rows.map(Device.fromRow).toList();
  }

  Future<Device?> getDevice(String sn) async {
    final rows = await db.query('devices', where: 'device_sn = ?', whereArgs: [sn], limit: 1);
    return rows.isEmpty ? null : Device.fromRow(rows.first);
  }

  Future<int> countDevices() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM devices WHERE archived = 0')) ?? 0;

  /// Device counts by type and status: `{INVERTER: {ONLINE: 10, OFFLINE: 2}}`.
  Future<Map<String, Map<DeviceStatus, int>>> countsByTypeAndStatus() async {
    final rows = await db.rawQuery('SELECT device_type, connect_status, COUNT(*) n FROM devices WHERE archived = 0 GROUP BY device_type, connect_status');
    final out = <String, Map<DeviceStatus, int>>{};
    for (final r in rows) {
      final type = (r['device_type'] as String?) ?? 'UNKNOWN';
      out.putIfAbsent(type, () => {})[DeviceStatus.fromDb(r['connect_status'] as String?)] = asInt(r['n']) ?? 0;
    }
    return out;
  }

  /// Per-station device counts: (total, offline) over non-archived devices.
  /// A station whose plant is online while some of its devices are offline is
  /// "partially offline" — the same status the DeyeCloud console shows.
  Future<Map<int, (int, int)>> deviceHealthPerStation() async {
    final rows = await db.rawQuery('''
      SELECT station_id,
             COUNT(*) AS n,
             SUM(CASE WHEN UPPER(COALESCE(connect_status, '')) IN ('OFFLINE', '3', 'DISCONNECTED') THEN 1 ELSE 0 END) AS off
      FROM devices WHERE archived = 0 AND station_id IS NOT NULL GROUP BY station_id''');
    return {
      for (final r in rows)
        (r['station_id'] as num).toInt(): ((r['n'] as num).toInt(), (r['off'] as num?)?.toInt() ?? 0),
    };
  }

  /// Stores `/device/latest` results: the full reading set in `device_latest`
  /// (replaced), status/collection time on `devices`, and one whitelisted
  /// numeric sample per device in `device_samples` (ignored when the
  /// (sn, ts) pair already exists). Returns the number of samples written.
  Future<int> applyLatest(List<DeviceLatest> latest) async {
    if (latest.isEmpty) return 0;
    var written = 0;
    for (final chunk in chunked(latest, 300)) {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final l in chunk) {
          batch.insert('device_latest', l.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
          batch.update(
            'devices',
            {
              if (l.status != DeviceStatus.unknown) 'connect_status': l.status.db,
              if (l.collectionTs != null) 'collection_ts': l.collectionTs,
              if (l.stationId != null) 'station_id': l.stationId,
            },
            where: 'device_sn = ?',
            whereArgs: [l.deviceSn],
          );
          final sample = DeviceSample.fromLatest(l);
          if (sample != null && !sample.isEmpty) {
            batch.insert('device_samples', sample.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        final results = await batch.commit(continueOnError: true);
        for (var i = 0; i < results.length; i++) {
          // Every third op is the sample insert; rowid > 0 means inserted.
          if (i % 3 == 2 && results[i] is int && (results[i] as int) > 0) written++;
        }
      });
    }
    return written;
  }

  Future<DeviceLatest?> latestForDevice(String sn) async {
    final rows = await db.query('device_latest', where: 'device_sn = ?', whereArgs: [sn], limit: 1);
    return rows.isEmpty ? null : DeviceLatest.fromRow(rows.first);
  }

  Future<List<DeviceLatest>> latestForStation(int stationId) async {
    final rows = await db.rawQuery('''
      SELECT l.* FROM device_latest l JOIN devices d ON d.device_sn = l.device_sn
      WHERE d.station_id = ? AND d.archived = 0 ORDER BY d.device_type, d.device_sn
    ''', [stationId]);
    return rows.map(DeviceLatest.fromRow).toList();
  }

  /// Newest reading set of every non-archived device, keyed by serial.
  Future<Map<String, DeviceLatest>> allLatest() async {
    final rows = await db.rawQuery('SELECT l.* FROM device_latest l JOIN devices d ON d.device_sn = l.device_sn WHERE d.archived = 0');
    return {for (final r in rows) r['device_sn'] as String: DeviceLatest.fromRow(r)};
  }

  Future<List<DeviceSample>> sampleSeries(String deviceSn, int fromTs, int toTs) async {
    final rows = await db.query('device_samples', where: 'device_sn = ? AND ts >= ? AND ts <= ?', whereArgs: [deviceSn, fromTs, toTs], orderBy: 'ts');
    return rows.map(DeviceSample.fromRow).toList();
  }

  /// Samples of all devices of a station in a range (ordered by device, ts).
  Future<List<DeviceSample>> samplesForStation(int stationId, int fromTs, int toTs) async {
    final rows = await db.rawQuery('''
      SELECT s.* FROM device_samples s JOIN devices d ON d.device_sn = s.device_sn
      WHERE d.station_id = ? AND s.ts >= ? AND s.ts <= ? ORDER BY s.device_sn, s.ts
    ''', [stationId, fromTs, toTs]);
    return rows.map(DeviceSample.fromRow).toList();
  }

  /// Samples of every device in a range, with the owning station id.
  Future<List<(int, DeviceSample)>> samplesBetween(int fromTs, int toTs) async {
    final rows = await db.rawQuery('''
      SELECT s.*, d.station_id AS sid FROM device_samples s JOIN devices d ON d.device_sn = s.device_sn
      WHERE s.ts >= ? AND s.ts <= ? AND d.station_id IS NOT NULL ORDER BY d.station_id, s.device_sn, s.ts
    ''', [fromTs, toTs]);
    return [for (final r in rows) (r['sid'] as int, DeviceSample.fromRow(r))];
  }

  Future<int> countSamples() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM device_samples')) ?? 0;
}
