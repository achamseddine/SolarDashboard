import 'school.dart';

/// Education summary of one governorate.
class EducationRegion {
  const EducationRegion({
    required this.name,
    required this.schools,
    required this.secondShiftSchools,
    this.amAttendance,
    this.pmAttendance,
    this.teachers = 0,
  });

  final String name;
  final int schools;

  /// Schools that also run an afternoon (PM) shift.
  final int secondShiftSchools;
  final double? amAttendance;
  final double? pmAttendance;
  final int teachers;
}

/// Student and teacher indicators from the MEHE education dashboard extract,
/// aggregated over the schools in the bundled dataset.
class EducationInsights {
  const EducationInsights({
    required this.generatedAt,
    required this.byRegion,
    required this.studentRiskAm,
    required this.studentRiskPm,
    required this.teacherRisk,
    required this.teacherTerms,
    this.schools = 0,
    this.secondShiftSchools = 0,
    this.amSchools = 0,
    this.amAttendance,
    this.amAttendanceWeighted,
    this.amStudents = 0,
    this.amSubmitted = 0,
    this.pmSchools = 0,
    this.pmAttendance,
    this.pmAttendanceWeighted,
    this.pmStudents = 0,
    this.pmSubmitted = 0,
    this.teacherSchools = 0,
    this.teachers = 0,
    this.femaleTeachers = 0,
    this.maleTeachers = 0,
    this.studentTeacherRatio,
    this.teachingDays,
    this.visitedThirdParty = 0,
    this.visitedByBdo = 0,
    this.hasAbsenceRates = false,
  });

  final DateTime generatedAt;
  final List<EducationRegion> byRegion;

  /// Risk-level counts (only a minority of schools carry a rating).
  final Map<RiskLevel, int> studentRiskAm;
  final Map<RiskLevel, int> studentRiskPm;
  final Map<RiskLevel, int> teacherRisk;

  /// Teachers whose attendance was reported in each of the four terms.
  final List<int> teacherTerms;

  final int schools;
  final int secondShiftSchools;

  /// Schools with a morning attendance figure.
  final int amSchools;

  /// Mean attendance across schools (0–1).
  final double? amAttendance;

  /// Attendance weighted by students, so big schools count more (0–1).
  final double? amAttendanceWeighted;
  final int amStudents;
  final int amSubmitted;
  final int pmSchools;
  final double? pmAttendance;
  final double? pmAttendanceWeighted;
  final int pmStudents;
  final int pmSubmitted;

  /// Schools with a teacher record (all of them run a PM shift).
  final int teacherSchools;
  final int teachers;
  final int femaleTeachers;
  final int maleTeachers;
  final double? studentTeacherRatio;
  final double? teachingDays;
  final int visitedThirdParty;
  final int visitedByBdo;

  /// The extract carries the "10+ days of non-justified absences" columns.
  /// They are empty in the bundled workbook, so the app says so instead of
  /// showing a zero.
  final bool hasAbsenceRates;

  int get riskRatedAm => studentRiskAm.values.fold(0, (a, b) => a + b);
  int get riskRatedPm => studentRiskPm.values.fold(0, (a, b) => a + b);
  int get riskRatedTeachers => teacherRisk.values.fold(0, (a, b) => a + b);
  int get highRiskStudents => (studentRiskAm[RiskLevel.high] ?? 0) + (studentRiskPm[RiskLevel.high] ?? 0);
  int get highRiskTeachers => teacherRisk[RiskLevel.high] ?? 0;

  /// Share of the four terms' reported teachers over the teacher headcount.
  double? get termReportingShare {
    if (teachers <= 0 || teacherTerms.isEmpty) return null;
    final mean = teacherTerms.fold(0, (a, b) => a + b) / teacherTerms.length;
    return mean / teachers;
  }

  double? get femaleShare => teachers <= 0 ? null : femaleTeachers / teachers;
  double? get visitedShare => schools <= 0 ? null : visitedThirdParty / schools;
  double? get secondShiftShare => schools <= 0 ? null : secondShiftSchools / schools;
}
