import 'package:sqflite/sqflite.dart';

/// Deletes old time-series rows in small chunks so the writer never blocks
/// the UI for long.
class Retention {
  Retention(this.db);
  final Database db;

  static const int chunk = 5000;

  /// Removes raw snapshots and device samples older than [snapshotDays],
  /// power buckets older than [bucketDays], recovered alerts older than
  /// [alertDays] and sync log rows beyond the newest [keepLogs].
  /// Daily/monthly energy, battery-day rows and status events are kept.
  Future<int> purge({int snapshotDays = 7, int bucketDays = 400, int alertDays = 365, int keepLogs = 500, int? now}) async {
    final n = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var deleted = 0;
    deleted += await _deleteChunked('station_snapshots', 'ts < ?', [n - snapshotDays * 86400]);
    deleted += await _deleteChunked('device_samples', 'ts < ?', [n - snapshotDays * 86400]);
    deleted += await _deleteChunked('power_buckets', 'bucket_ts < ?', [n - bucketDays * 86400]);
    deleted += await db.delete('alerts', where: "status = 'RECOVERED' AND COALESCE(end_ts, start_ts, first_seen_at) < ?", whereArgs: [n - alertDays * 86400]);
    deleted += await db.rawDelete('DELETE FROM sync_log WHERE id NOT IN (SELECT id FROM sync_log ORDER BY id DESC LIMIT ?)', [keepLogs]);
    return deleted;
  }

  Future<int> _deleteChunked(String table, String where, List<Object?> args) async {
    var total = 0;
    while (true) {
      final n = await db.rawDelete('DELETE FROM $table WHERE rowid IN (SELECT rowid FROM $table WHERE $where LIMIT $chunk)', args);
      total += n;
      if (n < chunk) break;
      await Future<void>.delayed(Duration.zero);
    }
    return total;
  }

  /// Runs the query planner statistics update (cheap; call after purges).
  Future<void> optimise() async {
    try {
      await db.execute('PRAGMA optimize');
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  /// Reclaims disk space (rewrites the file; call rarely, from Settings).
  Future<void> vacuum() async {
    await db.execute('VACUUM');
  }
}
