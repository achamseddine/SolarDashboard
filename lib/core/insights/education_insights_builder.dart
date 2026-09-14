import '../db/app_database.dart';
import '../models/education_insights.dart';
import '../models/school.dart';

/// Builds [EducationInsights] with SQL aggregates over `school_education`.
class EducationInsightsBuilder {
  EducationInsightsBuilder(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<EducationInsights> build() async {
    final t = await db.schools.educationTotals();
    final terms = await db.schools.teacherAttendanceTerms();
    final regions = await db.schools.educationByRegion();
    final amRisk = await db.schools.riskCounts('am_risk');
    final pmRisk = await db.schools.riskCounts('pm_risk');
    final teacherRisk = await db.schools.riskCounts('pm_teacher_risk');

    int i(String k) => (t[k] as num?)?.toInt() ?? 0;
    double? d(String k) => (t[k] as num?)?.toDouble();
    double? weighted(String sum, String students) {
      final s = d(sum), n = d(students);
      return s == null || n == null || n <= 0 ? null : s / n;
    }

    Map<RiskLevel, int> risk(Map<String, int> raw) {
      final out = <RiskLevel, int>{};
      raw.forEach((k, v) {
        final level = RiskLevel.fromDb(k);
        if (level != null) out[level] = v;
      });
      return out;
    }

    return EducationInsights(
      generatedAt: _clock(),
      byRegion: [
        for (final r in regions)
          EducationRegion(name: r.$1, schools: r.$2, secondShiftSchools: r.$3, amAttendance: r.$4, pmAttendance: r.$5, teachers: r.$6),
      ],
      studentRiskAm: risk(amRisk),
      studentRiskPm: risk(pmRisk),
      teacherRisk: risk(teacherRisk),
      teacherTerms: terms,
      schools: i('schools'),
      secondShiftSchools: i('second_shift'),
      amSchools: i('am_n'),
      amAttendance: d('am_mean'),
      amAttendanceWeighted: weighted('am_weighted', 'am_students'),
      amStudents: i('am_students'),
      amSubmitted: i('am_submitted'),
      pmSchools: i('pm_n'),
      pmAttendance: d('pm_mean'),
      pmAttendanceWeighted: weighted('pm_weighted', 'pm_students'),
      pmStudents: i('pm_students'),
      pmSubmitted: i('pm_submitted'),
      teacherSchools: i('teacher_schools'),
      teachers: i('teachers'),
      femaleTeachers: i('female'),
      maleTeachers: i('male'),
      studentTeacherRatio: d('ratio'),
      teachingDays: d('teaching_days'),
      visitedThirdParty: i('visited'),
      visitedByBdo: i('visited_bdo'),
      hasAbsenceRates: await _hasAbsenceRates(),
    );
  }

  /// The bundled extract leaves the "10+ days of non-justified absences"
  /// columns empty; check rather than assume.
  Future<bool> _hasAbsenceRates() async {
    final rows = await db.db.rawQuery('SELECT COUNT(*) AS n FROM school_education WHERE am_absence10 IS NOT NULL OR pm_absence10 IS NOT NULL');
    return ((rows.first['n'] as num?)?.toInt() ?? 0) > 0;
  }
}
