import 'package:sqflite/sqflite.dart';

import '../models/sync.dart';

class SyncDao {
  SyncDao(this.db);
  final Database db;

  Future<int> logStart(String kind, {int? now}) =>
      db.insert('sync_log', {'kind': kind, 'started_at': now ?? _now()});

  Future<void> logFinish(int id, {required bool ok, int? items, String? message, int? now}) async {
    await db.update('sync_log', {'finished_at': now ?? _now(), 'ok': ok ? 1 : 0, 'items': items, 'message': message}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SyncLogEntry>> recentLogs({int limit = 50}) async {
    final rows = await db.query('sync_log', orderBy: 'id DESC', limit: limit);
    return rows.map(SyncLogEntry.fromRow).toList();
  }

  Future<SyncLogEntry?> lastSuccessful(String kind) async {
    final rows = await db.query('sync_log', where: 'kind = ? AND ok = 1', whereArgs: [kind], orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : SyncLogEntry.fromRow(rows.first);
  }

  Future<void> pruneLogs({int keep = 500}) async {
    await db.rawDelete('DELETE FROM sync_log WHERE id NOT IN (SELECT id FROM sync_log ORDER BY id DESC LIMIT ?)', [keep]);
  }

  Future<String?> metaGet(String key) async {
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> metaSet(String key, String? value) async {
    await db.insert('sync_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String?>> metaWithPrefix(String prefix) async {
    final rows = await db.query('sync_meta', where: 'key LIKE ?', whereArgs: ['$prefix%']);
    return {for (final r in rows) r['key'] as String: r['value'] as String?};
  }

  Future<void> metaDeletePrefix(String prefix) async {
    await db.delete('sync_meta', where: 'key LIKE ?', whereArgs: ['$prefix%']);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
