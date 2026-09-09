import 'package:sqflite/sqflite.dart';

/// Deletes old time-series rows in small chunks so the writer never blocks
/// the UI for long.
class Retention {
  Retention(this.db);
  final Database db;

  /// Removes raw snapshots and device samples older than [snapshotDays],
  /// power buckets older than [bucketDays], recovered alerts older than
  /// [alertDays] and sync log rows beyond the newest [keepLogs].
  /// Daily/monthly energy, battery-day rows and status events are kept.
  Future<int> purge({int snapshotDays = 7, int bucketDays = 400, int alertDays = 365, int keepLogs = 500, int? now}) async {
    final n = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var deleted = 0;
    deleted += await _deleteChunked('station_snapshots', 'ts', n - snapshotDays * 86400);
    deleted += await _deleteChunked('device_samples', 'ts', n - snapshotDays * 86400);
    deleted += await _deleteChunked('power_buckets', 'bucket_ts', n - bucketDays * 86400);
    deleted += await db.delete('alerts', where: "status = 'RECOVERED' AND COALESCE(end_ts, start_ts, first_seen_at) < ?", whereArgs: [n - alertDays * 86400]);
    deleted += await db.rawDelete('DELETE FROM sync_log WHERE id NOT IN (SELECT id FROM sync_log ORDER BY id DESC LIMIT ?)', [keepLogs]);
    return deleted;
  }

  /// Deletes rows with `column < cutoff` in bounded time bands so each
  /// statement touches a limited number of rows. Works for WITHOUT ROWID
  /// tables (no rowid available) and needs no row-value syntax.
  Future<int> _deleteChunked(String table, String column, int cutoff, {int bandSeconds = 6 * 3600}) async {
    final minRow = await db.rawQuery('SELECT MIN($column) AS m FROM $table WHERE $column < ?', [cutoff]);
    final min = minRow.isEmpty ? null : minRow.first['m'] as int?;
    if (min == null) return 0;
    var total = 0;
    var from = min;
    while (from < cutoff) {
      final to = from + bandSeconds < cutoff ? from + bandSeconds : cutoff;
      total += await db.rawDelete('DELETE FROM $table WHERE $column >= ? AND $column < ?', [from, to]);
      from = to;
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
