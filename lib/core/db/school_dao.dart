import 'package:sqflite/sqflite.dart';

import '../models/school.dart';
import 'app_database.dart';

/// Read/write access to the school dataset tables and plant ↔ school links.
class SchoolDao {
  SchoolDao(this.db);
  final Database db;

  static const _select = '''
    SELECT s.*,
      so.listed_name AS sol_listed_name, so.status AS sol_status, so.status_raw AS sol_status_raw,
      so.donor AS sol_donor, so.donor_group AS sol_donor_group, so.project AS sol_project,
      so.cost_usd AS sol_cost_usd, so.kwp AS sol_kwp, so.inverter_kw AS sol_inverter_kw, so.battery_kwh AS sol_battery_kwh,
      so.enrollment_2324 AS sol_enrollment_2324, so.qa_cost_usd AS sol_qa_cost_usd, so.led_cost_usd AS sol_led_cost_usd,
      so.shift AS sol_shift, so.language AS sol_language, so.contractor AS sol_contractor, so.consultant AS sol_consultant,
      ld.lighting_kwh AS ld_lighting_kwh, ld.hvac_kwh AS ld_hvac_kwh, ld.it_kwh AS ld_it_kwh, ld.misc_kwh AS ld_misc_kwh,
      ed.shift AS ed_shift, ed.am_submitted AS ed_am_submitted, ed.am_attendance AS ed_am_attendance, ed.am_absence10 AS ed_am_absence10,
      ed.pm_submitted AS ed_pm_submitted, ed.pm_attendance AS ed_pm_attendance, ed.pm_absence10 AS ed_pm_absence10,
      ed.am_risk AS ed_am_risk, ed.pm_risk AS ed_pm_risk, ed.pm_teachers AS ed_pm_teachers,
      ed.pm_teacher_terms_json AS ed_pm_teacher_terms_json, ed.student_teacher_ratio AS ed_student_teacher_ratio,
      ed.visited_third_party AS ed_visited_third_party, ed.pm_teacher_risk AS ed_pm_teacher_risk,
      ed.pm_female_teachers AS ed_pm_female_teachers, ed.pm_male_teachers AS ed_pm_male_teachers, ed.teaching_days AS ed_teaching_days,
      ed.visited_by_bdo AS ed_visited_by_bdo,
      ed.monthly_student_risk_json AS ed_monthly_student_risk_json, ed.monthly_teacher_risk_json AS ed_monthly_teacher_risk_json
    FROM schools s
    LEFT JOIN school_solar so ON so.cerd = s.cerd
    LEFT JOIN school_loads ld ON ld.cerd = s.cerd
    LEFT JOIN school_education ed ON ed.cerd = s.cerd
  ''';

  // ------------------------------------------------------------- dataset

  /// Replaces the whole dataset (all five tables) in one transaction.
  Future<void> replaceDataset({
    required List<School> schools,
    required List<SchoolEquipment> equipment,
  }) async {
    await db.transaction((txn) async {
      for (final t in AppDatabase.datasetTables) {
        await txn.delete(t);
      }
      var batch = txn.batch();
      var n = 0;
      Future<void> flush() async {
        await batch.commit(noResult: true);
        batch = txn.batch();
        n = 0;
      }

      for (final s in schools) {
        batch.insert('schools', s.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        if (s.solar != null) batch.insert('school_solar', s.solar!.toRow(s.cerd), conflictAlgorithm: ConflictAlgorithm.replace);
        if (s.loads != null) batch.insert('school_loads', s.loads!.toRow(s.cerd), conflictAlgorithm: ConflictAlgorithm.replace);
        if (s.education != null) batch.insert('school_education', s.education!.toRow(s.cerd), conflictAlgorithm: ConflictAlgorithm.replace);
        if (++n >= 200) await flush();
      }
      for (final e in equipment) {
        batch.insert('school_equipment', e.toRow());
        if (++n >= 400) await flush();
      }
      await flush();
    });
  }

  Future<int> countSchools() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM schools')) ?? 0;

  Future<List<School>> getSchools({
    String? region,
    bool? connected,
    SolarStatus? solarStatus,
    bool? solarized,
    String? search,
    bool masterOnly = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (region != null) {
      where.add('s.region = ?');
      args.add(region);
    }
    if (connected != null) {
      where.add('s.connected = ?');
      args.add(connected ? 1 : 0);
    }
    if (solarStatus != null) {
      where.add('so.status = ?');
      args.add(solarStatus.db);
    }
    if (solarized != null) {
      where.add(solarized ? "so.status = 'completed'" : "(so.status IS NULL OR so.status <> 'completed')");
    }
    if (masterOnly) where.add('s.in_master = 1');
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      where.add('(s.name LIKE ? OR s.name_ar LIKE ? OR so.listed_name LIKE ? OR CAST(s.cerd AS TEXT) LIKE ? OR s.caza LIKE ?)');
      args.addAll([q, q, q, q, q]);
    }
    final rows = await db.rawQuery('$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY s.name', args);
    return rows.map(School.fromRow).toList();
  }

  Future<School?> getSchool(int cerd) async {
    final rows = await db.rawQuery('$_select WHERE s.cerd = ?', [cerd]);
    return rows.isEmpty ? null : School.fromRow(rows.first);
  }

  Future<Map<int, School>> getSchoolsByCerd(Iterable<int> cerds) async {
    final out = <int, School>{};
    for (final chunk in chunked(cerds.toSet().toList(), 400)) {
      final rows = await db.rawQuery('$_select WHERE s.cerd IN (${placeholders(chunk.length)})', chunk);
      for (final r in rows) {
        final s = School.fromRow(r);
        out[s.cerd] = s;
      }
    }
    return out;
  }

  Future<List<SchoolEquipment>> equipmentFor(int cerd) async {
    final rows = await db.query('school_equipment', where: 'cerd = ?', whereArgs: [cerd], orderBy: 'annual_kwh DESC');
    return rows.map(SchoolEquipment.fromRow).toList();
  }

  /// Fleet-wide equipment totals: (type, category, items, annual kWh).
  Future<List<(String, String, int, double)>> equipmentTotals({int limit = 25}) async {
    final rows = await db.rawQuery('''
      SELECT LOWER(TRIM(type)) AS t, category, SUM(count) AS n, SUM(annual_kwh) AS kwh
      FROM school_equipment GROUP BY t, category ORDER BY kwh DESC LIMIT ?''', [limit]);
    return [for (final r in rows) (r['t'] as String, r['category'] as String, (r['n'] as num?)?.toInt() ?? 0, (r['kwh'] as num?)?.toDouble() ?? 0)];
  }

  /// Annual kWh per equipment category across the whole dataset.
  Future<Map<String, double>> equipmentByCategory() async {
    final rows = await db.rawQuery('SELECT category, SUM(annual_kwh) AS kwh FROM school_equipment GROUP BY category');
    return {for (final r in rows) r['category'] as String: (r['kwh'] as num?)?.toDouble() ?? 0};
  }

  // --------------------------------------------------------------- links

  Future<void> upsertLinks(List<StationSchoolLink> links) async {
    if (links.isEmpty) return;
    final batch = db.batch();
    for (final l in links) {
      batch.insert(AppDatabase.linksTable, l.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setLink(StationSchoolLink link) => upsertLinks([link]);

  Future<void> deleteLink(int stationId) async {
    await db.delete(AppDatabase.linksTable, where: 'station_id = ?', whereArgs: [stationId]);
  }

  /// Removes automatic links (manual ones are kept).
  Future<int> deleteAutoLinks() => db.delete(AppDatabase.linksTable, where: 'method <> ?', whereArgs: [LinkMethod.manual.db]);

  Future<Map<int, StationSchoolLink>> getLinks() async {
    final rows = await db.query(AppDatabase.linksTable);
    return {for (final r in rows) (r['station_id'] as num).toInt(): StationSchoolLink.fromRow(r)};
  }

  Future<StationSchoolLink?> linkForStation(int stationId) async {
    final rows = await db.query(AppDatabase.linksTable, where: 'station_id = ?', whereArgs: [stationId]);
    return rows.isEmpty ? null : StationSchoolLink.fromRow(rows.first);
  }

  Future<List<StationSchoolLink>> linksForSchool(int cerd) async {
    final rows = await db.query(AppDatabase.linksTable, where: 'cerd = ?', whereArgs: [cerd]);
    return rows.map(StationSchoolLink.fromRow).toList();
  }

  /// Station id → linked school, for every linked plant.
  Future<Map<int, School>> linkedSchools() async {
    final links = await getLinks();
    final schools = await getSchoolsByCerd(links.values.map((l) => l.cerd));
    return {for (final e in links.entries) if (schools[e.value.cerd] != null) e.key: schools[e.value.cerd]!};
  }
}
