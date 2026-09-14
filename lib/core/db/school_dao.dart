import 'dart:convert';

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
    String? caza,
    String? ownership,
    bool? connected,
    SolarStatus? solarStatus,
    bool? solarized,
    bool? hasAudit,
    String? search,
    bool masterOnly = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (region != null) {
      where.add('s.region = ?');
      args.add(region);
    }
    if (caza != null) {
      where.add('s.caza = ?');
      args.add(caza);
    }
    if (ownership != null) {
      where.add('s.ownership = ?');
      args.add(ownership);
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
    if (hasAudit != null) {
      const sum = 'COALESCE(ld.lighting_kwh,0) + COALESCE(ld.hvac_kwh,0) + COALESCE(ld.it_kwh,0) + COALESCE(ld.misc_kwh,0)';
      where.add(hasAudit ? '($sum) > 0' : '(ld.cerd IS NULL OR ($sum) <= 0)');
    }
    if (masterOnly) where.add('s.in_master = 1');
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      where.add('(s.name LIKE ? OR s.name_ar LIKE ? OR so.listed_name LIKE ? OR CAST(s.cerd AS TEXT) LIKE ? OR s.caza LIKE ? OR s.cadaster LIKE ? OR s.address LIKE ?)');
      args.addAll([q, q, q, q, q, q, q]);
    }
    final rows = await db.rawQuery('$_select ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY s.name', args);
    return rows.map(School.fromRow).toList();
  }

  /// Distinct cazas (districts) present in the dataset, with school counts.
  Future<List<(String, int)>> cazaCounts({String? region}) async {
    final rows = await db.rawQuery(
      'SELECT caza, COUNT(*) AS n FROM schools WHERE caza IS NOT NULL${region == null ? '' : ' AND region = ?'} GROUP BY caza ORDER BY caza',
      [?region],
    );
    return [for (final r in rows) (r['caza'] as String, (r['n'] as num).toInt())];
  }

  /// Distinct ownership values with school counts.
  Future<List<(String, int)>> ownershipCounts() async {
    final rows = await db.rawQuery('SELECT ownership, COUNT(*) AS n FROM schools WHERE ownership IS NOT NULL GROUP BY ownership ORDER BY n DESC');
    return [for (final r in rows) (r['ownership'] as String, (r['n'] as num).toInt())];
  }

  /// Internet-connectivity counts grouped by [column] ('region' or 'caza'):
  /// (group, schools, connected, students, connected students).
  Future<List<(String, int, int, int, int)>> connectivityBy(String column) async {
    assert(column == 'region' || column == 'caza');
    final rows = await db.rawQuery('''
      SELECT COALESCE($column, 'Unassigned') AS g,
             COUNT(*) AS n,
             SUM(connected) AS c,
             SUM(COALESCE(enrollment, 0)) AS st,
             SUM(CASE WHEN connected = 1 THEN COALESCE(enrollment, 0) ELSE 0 END) AS cst
      FROM schools WHERE in_master = 1 GROUP BY g ORDER BY n DESC''');
    return [
      for (final r in rows)
        (
          r['g'] as String,
          (r['n'] as num).toInt(),
          (r['c'] as num?)?.toInt() ?? 0,
          (r['st'] as num?)?.toInt() ?? 0,
          (r['cst'] as num?)?.toInt() ?? 0,
        ),
    ];
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

  // ----------------------------------------------------------- education

  /// One row of student/teacher aggregates. Pass `null` for the fleet.
  Future<Map<String, Object?>> educationTotals({String? region}) async {
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS schools,
        SUM(CASE WHEN ed.am_attendance IS NOT NULL THEN 1 ELSE 0 END) AS am_n,
        AVG(ed.am_attendance) AS am_mean,
        SUM(ed.am_attendance * COALESCE(s.students_am, s.enrollment, 0)) AS am_weighted,
        SUM(CASE WHEN ed.am_attendance IS NOT NULL THEN COALESCE(s.students_am, s.enrollment, 0) ELSE 0 END) AS am_students,
        SUM(CASE WHEN ed.pm_attendance IS NOT NULL THEN 1 ELSE 0 END) AS pm_n,
        AVG(ed.pm_attendance) AS pm_mean,
        SUM(ed.pm_attendance * COALESCE(s.students_pm, 0)) AS pm_weighted,
        SUM(CASE WHEN ed.pm_attendance IS NOT NULL THEN COALESCE(s.students_pm, 0) ELSE 0 END) AS pm_students,
        SUM(CASE WHEN ed.shift LIKE '%PM%' THEN 1 ELSE 0 END) AS second_shift,
        SUM(CASE WHEN ed.am_submitted = 1 THEN 1 ELSE 0 END) AS am_submitted,
        SUM(CASE WHEN ed.pm_submitted = 1 THEN 1 ELSE 0 END) AS pm_submitted,
        SUM(COALESCE(ed.pm_teachers, 0)) AS teachers,
        SUM(CASE WHEN ed.pm_teachers IS NOT NULL THEN 1 ELSE 0 END) AS teacher_schools,
        SUM(COALESCE(ed.pm_female_teachers, 0)) AS female,
        SUM(COALESCE(ed.pm_male_teachers, 0)) AS male,
        AVG(ed.student_teacher_ratio) AS ratio,
        AVG(ed.teaching_days) AS teaching_days,
        SUM(CASE WHEN ed.visited_third_party = 1 THEN 1 ELSE 0 END) AS visited,
        SUM(CASE WHEN ed.visited_by_bdo = 1 THEN 1 ELSE 0 END) AS visited_bdo
      FROM school_education ed
      JOIN schools s ON s.cerd = ed.cerd
      WHERE s.in_master = 1${region == null ? '' : ' AND s.region = ?'}''', [?region]);
    return rows.isEmpty ? const {} : rows.first;
  }

  /// Sum of the four teacher-attendance terms (index 0-3), fleet-wide.
  Future<List<int>> teacherAttendanceTerms() async {
    final rows = await db.rawQuery('SELECT pm_teacher_terms_json FROM school_education WHERE pm_teacher_terms_json IS NOT NULL');
    final out = <int>[0, 0, 0, 0];
    for (final r in rows) {
      final raw = r['pm_teacher_terms_json'] as String?;
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (var i = 0; i < out.length && i < list.length; i++) {
            final v = list[i];
            if (v is num) out[i] += v.toInt();
          }
        }
      } catch (_) {
        // A malformed row must not break the dashboard.
      }
    }
    return out;
  }

  /// Risk-level counts of [column] ('am_risk', 'pm_risk', 'pm_teacher_risk').
  Future<Map<String, int>> riskCounts(String column) async {
    assert(column == 'am_risk' || column == 'pm_risk' || column == 'pm_teacher_risk');
    final rows = await db.rawQuery('SELECT $column AS r, COUNT(*) AS n FROM school_education WHERE $column IS NOT NULL GROUP BY r');
    return {for (final r in rows) r['r'] as String: (r['n'] as num).toInt()};
  }

  /// Per-governorate education summary: (region, schools, second-shift schools,
  /// AM attendance mean, PM attendance mean, teachers).
  Future<List<(String, int, int, double?, double?, int)>> educationByRegion() async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(s.region, 'Unassigned') AS g,
             COUNT(*) AS n,
             SUM(CASE WHEN ed.shift LIKE '%PM%' THEN 1 ELSE 0 END) AS pm_n,
             AVG(ed.am_attendance) AS am_mean,
             AVG(ed.pm_attendance) AS pm_mean,
             SUM(COALESCE(ed.pm_teachers, 0)) AS teachers
      FROM school_education ed JOIN schools s ON s.cerd = ed.cerd
      WHERE s.in_master = 1 GROUP BY g ORDER BY n DESC''');
    return [
      for (final r in rows)
        (
          r['g'] as String,
          (r['n'] as num).toInt(),
          (r['pm_n'] as num?)?.toInt() ?? 0,
          (r['am_mean'] as num?)?.toDouble(),
          (r['pm_mean'] as num?)?.toDouble(),
          (r['teachers'] as num?)?.toInt() ?? 0,
        ),
    ];
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
