import 'dart:convert';

import '../api/json_utils.dart';

/// Solarisation status of a school in the UNICEF programme.
enum SolarStatus {
  completed('completed', 'Completed'),
  planned('planned', 'Planned'),
  onHold('on_hold', 'On hold'),
  unfunded('unfunded', 'Unfunded'),
  notSolarized('not_solarized', 'Not solarised');

  const SolarStatus(this.db, this.label);
  final String db;
  final String label;

  static SolarStatus? fromDb(String? v) {
    if (v == null) return null;
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }

  /// Planned, on hold and unfunded are all "in the pipeline".
  bool get isPipeline => this == planned || this == onHold || this == unfunded;
}

/// Risk levels used by the MEHE education dashboard.
enum RiskLevel {
  low('low', 'Low risk'),
  medium('medium', 'Medium risk'),
  high('high', 'High risk');

  const RiskLevel(this.db, this.label);
  final String db;
  final String label;

  static RiskLevel? fromDb(String? v) {
    if (v == null) return null;
    for (final r in values) {
      if (r.db == v) return r;
    }
    return null;
  }
}

/// Solar implementation record (from the programme tracker workbook).
class SchoolSolar {
  const SchoolSolar({
    required this.status,
    this.listedName,
    this.statusRaw,
    this.donor,
    this.donorGroup,
    this.project,
    this.costUsd,
    this.kwp,
    this.inverterKw,
    this.batteryKwh,
    this.enrollment2324,
    this.qaCostUsd,
    this.ledCostUsd,
    this.shift,
    this.language,
    this.contractor,
    this.consultant,
  });

  final SolarStatus status;

  /// School name as written in the solar tracker (often differs from MEHE's).
  final String? listedName;
  final String? statusRaw;
  final String? donor;
  final String? donorGroup;
  final String? project;
  final double? costUsd;
  final double? kwp;
  final double? inverterKw;
  final double? batteryKwh;
  final int? enrollment2324;
  final double? qaCostUsd;
  final double? ledCostUsd;
  final String? shift;
  final String? language;
  final String? contractor;
  final String? consultant;

  bool get isCompleted => status == SolarStatus.completed;

  static SchoolSolar fromJson(Map<String, Object?> j) {
    return SchoolSolar(
      status: SolarStatus.fromDb(asString(j['status'])) ?? SolarStatus.planned,
      listedName: asString(j['listedName']),
      statusRaw: asString(j['statusRaw']),
      donor: asString(j['donor']),
      donorGroup: asString(j['donorGroup']),
      project: asString(j['project']),
      costUsd: asDouble(j['costUsd']),
      kwp: asDouble(j['kwp']),
      inverterKw: asDouble(j['inverterKw']),
      batteryKwh: asDouble(j['batteryKwh']),
      enrollment2324: asInt(j['enrollment2324']),
      qaCostUsd: asDouble(j['qaCostUsd']),
      ledCostUsd: asDouble(j['ledCostUsd']),
      shift: asString(j['shift']),
      language: asString(j['language']),
      contractor: asString(j['contractor']),
      consultant: asString(j['consultant']),
    );
  }

  static SchoolSolar? fromRow(Map<String, Object?> r, {String prefix = 'sol_'}) {
    final status = SolarStatus.fromDb(r['${prefix}status'] as String?);
    if (status == null) return null;
    return SchoolSolar(
      status: status,
      listedName: r['${prefix}listed_name'] as String?,
      statusRaw: r['${prefix}status_raw'] as String?,
      donor: r['${prefix}donor'] as String?,
      donorGroup: r['${prefix}donor_group'] as String?,
      project: r['${prefix}project'] as String?,
      costUsd: asDouble(r['${prefix}cost_usd']),
      kwp: asDouble(r['${prefix}kwp']),
      inverterKw: asDouble(r['${prefix}inverter_kw']),
      batteryKwh: asDouble(r['${prefix}battery_kwh']),
      enrollment2324: asInt(r['${prefix}enrollment_2324']),
      qaCostUsd: asDouble(r['${prefix}qa_cost_usd']),
      ledCostUsd: asDouble(r['${prefix}led_cost_usd']),
      shift: r['${prefix}shift'] as String?,
      language: r['${prefix}language'] as String?,
      contractor: r['${prefix}contractor'] as String?,
      consultant: r['${prefix}consultant'] as String?,
    );
  }

  Map<String, Object?> toRow(int cerd) => {
        'cerd': cerd,
        'listed_name': listedName,
        'status': status.db,
        'status_raw': statusRaw,
        'donor': donor,
        'donor_group': donorGroup,
        'project': project,
        'cost_usd': costUsd,
        'kwp': kwp,
        'inverter_kw': inverterKw,
        'battery_kwh': batteryKwh,
        'enrollment_2324': enrollment2324,
        'qa_cost_usd': qaCostUsd,
        'led_cost_usd': ledCostUsd,
        'shift': shift,
        'language': language,
        'contractor': contractor,
        'consultant': consultant,
      };
}

/// Estimated annual electricity consumption by category (kWh/year), from the
/// MEHE energy audit.
class SchoolLoads {
  const SchoolLoads({this.lightingKwh = 0, this.hvacKwh = 0, this.itKwh = 0, this.miscKwh = 0});

  final double lightingKwh;
  final double hvacKwh;
  final double itKwh;
  final double miscKwh;

  double get totalKwh => lightingKwh + hvacKwh + itKwh + miscKwh;
  bool get isEmpty => totalKwh <= 0;

  /// (label, kWh) pairs in display order.
  List<(String, double)> get categories => [('Lighting', lightingKwh), ('HVAC', hvacKwh), ('IT', itKwh), ('Miscellaneous', miscKwh)];

  static SchoolLoads fromJson(Map<String, Object?> j) {
    return SchoolLoads(
      lightingKwh: asDouble(j['lightingKwh']) ?? 0,
      hvacKwh: asDouble(j['hvacKwh']) ?? 0,
      itKwh: asDouble(j['itKwh']) ?? 0,
      miscKwh: asDouble(j['miscKwh']) ?? 0,
    );
  }

  static SchoolLoads? fromRow(Map<String, Object?> r, {String prefix = 'ld_'}) {
    if (r['${prefix}lighting_kwh'] == null && r['${prefix}hvac_kwh'] == null && r['${prefix}it_kwh'] == null && r['${prefix}misc_kwh'] == null) return null;
    return SchoolLoads(
      lightingKwh: asDouble(r['${prefix}lighting_kwh']) ?? 0,
      hvacKwh: asDouble(r['${prefix}hvac_kwh']) ?? 0,
      itKwh: asDouble(r['${prefix}it_kwh']) ?? 0,
      miscKwh: asDouble(r['${prefix}misc_kwh']) ?? 0,
    );
  }

  Map<String, Object?> toRow(int cerd) => {'cerd': cerd, 'lighting_kwh': lightingKwh, 'hvac_kwh': hvacKwh, 'it_kwh': itKwh, 'misc_kwh': miscKwh};
}

/// One line of the equipment inventory of a school.
class SchoolEquipment {
  const SchoolEquipment({required this.cerd, required this.type, required this.category, this.watts = 0, this.count = 0, this.hoursPerDay = 0, this.annualKwh = 0});

  final int cerd;
  final String type;
  final String category;
  final double watts;
  final int count;
  final double hoursPerDay;
  final double annualKwh;

  /// Connected load of this line (kW).
  double get connectedKw => watts * count / 1000;

  static SchoolEquipment? fromJson(int cerd, Object? v) {
    if (v is! List || v.length < 6) return null;
    return SchoolEquipment(
      cerd: cerd,
      type: asString(v[0]) ?? 'Unknown',
      category: asString(v[1]) ?? 'Other',
      watts: asDouble(v[2]) ?? 0,
      count: asInt(v[3]) ?? 0,
      hoursPerDay: asDouble(v[4]) ?? 0,
      annualKwh: asDouble(v[5]) ?? 0,
    );
  }

  static SchoolEquipment fromRow(Map<String, Object?> r) => SchoolEquipment(
        cerd: asInt(r['cerd']) ?? 0,
        type: r['type'] as String? ?? 'Unknown',
        category: r['category'] as String? ?? 'Other',
        watts: asDouble(r['watts']) ?? 0,
        count: asInt(r['count']) ?? 0,
        hoursPerDay: asDouble(r['hours_per_day']) ?? 0,
        annualKwh: asDouble(r['annual_kwh']) ?? 0,
      );

  Map<String, Object?> toRow() => {'cerd': cerd, 'type': type, 'category': category, 'watts': watts, 'count': count, 'hours_per_day': hoursPerDay, 'annual_kwh': annualKwh};
}

/// Attendance and risk indicators from the MEHE education dashboard.
class SchoolEducation {
  const SchoolEducation({
    this.shift,
    this.amSubmitted,
    this.amAttendance,
    this.amAbsence10Rate,
    this.pmSubmitted,
    this.pmAttendance,
    this.pmAbsence10Rate,
    this.amRisk,
    this.pmRisk,
    this.pmTeachers,
    this.pmTeacherAttendanceTerms = const [],
    this.studentTeacherRatio,
    this.visitedThirdParty,
    this.pmTeacherRisk,
    this.pmFemaleTeachers,
    this.pmMaleTeachers,
    this.teachingDays,
    this.visitedByBdo,
    this.monthlyStudentRisk = const {},
    this.monthlyTeacherRisk = const {},
  });

  final String? shift;
  final bool? amSubmitted;

  /// Morning-shift attendance rate 0–1.
  final double? amAttendance;
  final double? amAbsence10Rate;
  final bool? pmSubmitted;

  /// Afternoon (second) shift attendance rate 0–1.
  final double? pmAttendance;
  final double? pmAbsence10Rate;
  final RiskLevel? amRisk;
  final RiskLevel? pmRisk;
  final int? pmTeachers;
  final List<int?> pmTeacherAttendanceTerms;
  final double? studentTeacherRatio;
  final bool? visitedThirdParty;
  final RiskLevel? pmTeacherRisk;
  final int? pmFemaleTeachers;
  final int? pmMaleTeachers;
  final int? teachingDays;
  final bool? visitedByBdo;
  final Map<String, RiskLevel> monthlyStudentRisk;
  final Map<String, RiskLevel> monthlyTeacherRisk;

  bool get hasSecondShift => (shift ?? '').toUpperCase().contains('PM');

  /// Highest student risk across shifts (null when not assessed).
  RiskLevel? get studentRisk {
    final a = amRisk, b = pmRisk;
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  static Map<String, RiskLevel> _riskMap(Object? v) {
    final out = <String, RiskLevel>{};
    for (final e in asMap(v).entries) {
      final r = RiskLevel.fromDb(asString(e.value));
      if (r != null) out[e.key] = r;
    }
    return out;
  }

  static Object? _decode(String? v) {
    if (v == null || v.isEmpty) return null;
    try {
      return jsonDecode(v);
    } catch (_) {
      return null;
    }
  }

  static SchoolEducation fromJson(Map<String, Object?> j) {
    final terms = j['pmTeacherAttendanceTerms'];
    return SchoolEducation(
      shift: asString(j['shift']),
      amSubmitted: asBool(j['amSubmitted']),
      amAttendance: asDouble(j['amAttendance']),
      amAbsence10Rate: asDouble(j['amAbsence10Rate']),
      pmSubmitted: asBool(j['pmSubmitted']),
      pmAttendance: asDouble(j['pmAttendance']),
      pmAbsence10Rate: asDouble(j['pmAbsence10Rate']),
      amRisk: RiskLevel.fromDb(asString(j['amRisk'])),
      pmRisk: RiskLevel.fromDb(asString(j['pmRisk'])),
      pmTeachers: asInt(j['pmTeachers']),
      pmTeacherAttendanceTerms: terms is List ? [for (final t in terms) asInt(t)] : const [],
      studentTeacherRatio: asDouble(j['studentTeacherRatio']),
      visitedThirdParty: asBool(j['visitedThirdParty']),
      pmTeacherRisk: RiskLevel.fromDb(asString(j['pmTeacherRisk'])),
      pmFemaleTeachers: asInt(j['pmFemaleTeachers']),
      pmMaleTeachers: asInt(j['pmMaleTeachers']),
      teachingDays: asInt(j['teachingDays']),
      visitedByBdo: asBool(j['visitedByBdo']),
      monthlyStudentRisk: _riskMap(j['monthlyStudentRisk']),
      monthlyTeacherRisk: _riskMap(j['monthlyTeacherRisk']),
    );
  }

  static SchoolEducation? fromRow(Map<String, Object?> r, {String prefix = 'ed_'}) {
    if (r['${prefix}shift'] == null && r['${prefix}am_attendance'] == null && r['${prefix}pm_attendance'] == null) return null;
    final terms = _decode(r['${prefix}pm_teacher_terms_json'] as String?);
    return SchoolEducation(
      shift: r['${prefix}shift'] as String?,
      amSubmitted: _boolCol(r['${prefix}am_submitted']),
      amAttendance: asDouble(r['${prefix}am_attendance']),
      amAbsence10Rate: asDouble(r['${prefix}am_absence10']),
      pmSubmitted: _boolCol(r['${prefix}pm_submitted']),
      pmAttendance: asDouble(r['${prefix}pm_attendance']),
      pmAbsence10Rate: asDouble(r['${prefix}pm_absence10']),
      amRisk: RiskLevel.fromDb(r['${prefix}am_risk'] as String?),
      pmRisk: RiskLevel.fromDb(r['${prefix}pm_risk'] as String?),
      pmTeachers: asInt(r['${prefix}pm_teachers']),
      pmTeacherAttendanceTerms: terms is List ? [for (final t in terms) asInt(t)] : const [],
      studentTeacherRatio: asDouble(r['${prefix}student_teacher_ratio']),
      visitedThirdParty: _boolCol(r['${prefix}visited_third_party']),
      pmTeacherRisk: RiskLevel.fromDb(r['${prefix}pm_teacher_risk'] as String?),
      pmFemaleTeachers: asInt(r['${prefix}pm_female_teachers']),
      pmMaleTeachers: asInt(r['${prefix}pm_male_teachers']),
      teachingDays: asInt(r['${prefix}teaching_days']),
      visitedByBdo: _boolCol(r['${prefix}visited_by_bdo']),
      monthlyStudentRisk: _riskMap(_decode(r['${prefix}monthly_student_risk_json'] as String?)),
      monthlyTeacherRisk: _riskMap(_decode(r['${prefix}monthly_teacher_risk_json'] as String?)),
    );
  }

  static bool? _boolCol(Object? v) => v == null ? null : (v is num ? v != 0 : v.toString() == '1' || v.toString() == 'true');
  static int? _boolInt(bool? v) => v == null ? null : (v ? 1 : 0);

  Map<String, Object?> toRow(int cerd) => {
        'cerd': cerd,
        'shift': shift,
        'am_submitted': _boolInt(amSubmitted),
        'am_attendance': amAttendance,
        'am_absence10': amAbsence10Rate,
        'pm_submitted': _boolInt(pmSubmitted),
        'pm_attendance': pmAttendance,
        'pm_absence10': pmAbsence10Rate,
        'am_risk': amRisk?.db,
        'pm_risk': pmRisk?.db,
        'pm_teachers': pmTeachers,
        'pm_teacher_terms_json': pmTeacherAttendanceTerms.isEmpty ? null : jsonEncode(pmTeacherAttendanceTerms),
        'student_teacher_ratio': studentTeacherRatio,
        'visited_third_party': _boolInt(visitedThirdParty),
        'pm_teacher_risk': pmTeacherRisk?.db,
        'pm_female_teachers': pmFemaleTeachers,
        'pm_male_teachers': pmMaleTeachers,
        'teaching_days': teachingDays,
        'visited_by_bdo': _boolInt(visitedByBdo),
        'monthly_student_risk_json': monthlyStudentRisk.isEmpty ? null : jsonEncode({for (final e in monthlyStudentRisk.entries) e.key: e.value.db}),
        'monthly_teacher_risk_json': monthlyTeacherRisk.isEmpty ? null : jsonEncode({for (final e in monthlyTeacherRisk.entries) e.key: e.value.db}),
      };
}

/// A public school (MEHE master record) with the programme data attached.
/// Identified by its CERD number, which every source workbook shares.
class School {
  const School({
    required this.cerd,
    required this.name,
    this.inMaster = true,
    this.nameAr,
    this.region,
    this.caza,
    this.cadaster,
    this.casCode,
    this.ownership,
    this.capacity,
    this.lat,
    this.lng,
    this.address,
    this.phone,
    this.studentsAm,
    this.studentsPm,
    this.enrollment,
    this.pmCerd,
    this.connected = false,
    this.solar,
    this.loads,
    this.education,
  });

  final int cerd;
  final String name;

  /// False for schools that only appear in a secondary workbook.
  final bool inMaster;
  final String? nameAr;

  /// Governorate, normalised to the app's nine regions.
  final String? region;

  /// District, normalised to the geoBoundaries names used for plants.
  final String? caza;
  final String? cadaster;
  final int? casCode;
  final String? ownership;
  final int? capacity;
  final double? lat;
  final double? lng;
  final String? address;
  final String? phone;
  final int? studentsAm;
  final int? studentsPm;
  final int? enrollment;

  /// CERD number of the afternoon (second-shift) school hosted here.
  final int? pmCerd;

  /// Listed in the internet-connectivity roll-out (534 schools).
  final bool connected;
  final SchoolSolar? solar;
  final SchoolLoads? loads;
  final SchoolEducation? education;

  bool get hasLocation => lat != null && lng != null;
  bool get isSolarized => solar?.isCompleted ?? false;
  SolarStatus? get solarStatus => solar?.status;

  /// Students: MEHE enrolment, else the solar tracker's 2023-24 figure.
  int? get students => enrollment ?? solar?.enrollment2324;
  double? get annualLoadKwh => loads == null || loads!.isEmpty ? null : loads!.totalKwh;

  static School? fromJson(Map<String, Object?> j) {
    final cerd = asInt(j['cerd']);
    if (cerd == null) return null;
    return School(
      cerd: cerd,
      name: asString(j['name']) ?? asString(j['nameAr']) ?? 'School $cerd',
      inMaster: asBool(j['inMaster']) ?? false,
      nameAr: asString(j['nameAr']),
      region: asString(j['region']),
      caza: asString(j['caza']),
      cadaster: asString(j['cadaster']),
      casCode: asInt(j['casCode']),
      ownership: asString(j['ownership']),
      capacity: asInt(j['capacity']),
      lat: asDouble(j['lat']),
      lng: asDouble(j['lng']),
      address: asString(j['address']),
      phone: asString(j['phone']),
      studentsAm: asInt(j['studentsAm']),
      studentsPm: asInt(j['studentsPm']),
      enrollment: asInt(j['enrollment']),
      pmCerd: asInt(j['pmCerd']),
      connected: asBool(j['connected']) ?? false,
      solar: j['solar'] == null ? null : SchoolSolar.fromJson(asMap(j['solar'])),
      loads: j['loads'] == null ? null : SchoolLoads.fromJson(asMap(j['loads'])),
      education: j['education'] == null ? null : SchoolEducation.fromJson(asMap(j['education'])),
    );
  }

  /// From a row of the `schools` table LEFT JOINed with the satellite
  /// tables (column prefixes `sol_`, `ld_`, `ed_`).
  static School fromRow(Map<String, Object?> r) => School(
        cerd: asInt(r['cerd']) ?? 0,
        name: r['name'] as String? ?? '',
        inMaster: (asInt(r['in_master']) ?? 0) != 0,
        nameAr: r['name_ar'] as String?,
        region: r['region'] as String?,
        caza: r['caza'] as String?,
        cadaster: r['cadaster'] as String?,
        casCode: asInt(r['cas_code']),
        ownership: r['ownership'] as String?,
        capacity: asInt(r['capacity']),
        lat: asDouble(r['lat']),
        lng: asDouble(r['lng']),
        address: r['address'] as String?,
        phone: r['phone'] as String?,
        studentsAm: asInt(r['students_am']),
        studentsPm: asInt(r['students_pm']),
        enrollment: asInt(r['enrollment']),
        pmCerd: asInt(r['pm_cerd']),
        connected: (asInt(r['connected']) ?? 0) != 0,
        solar: SchoolSolar.fromRow(r),
        loads: SchoolLoads.fromRow(r),
        education: SchoolEducation.fromRow(r),
      );

  Map<String, Object?> toRow() => {
        'cerd': cerd,
        'in_master': inMaster ? 1 : 0,
        'name': name,
        'name_ar': nameAr,
        'region': region,
        'caza': caza,
        'cadaster': cadaster,
        'cas_code': casCode,
        'ownership': ownership,
        'capacity': capacity,
        'lat': lat,
        'lng': lng,
        'address': address,
        'phone': phone,
        'students_am': studentsAm,
        'students_pm': studentsPm,
        'enrollment': enrollment,
        'pm_cerd': pmCerd,
        'connected': connected ? 1 : 0,
      };
}

/// How a plant was matched to a school.
enum LinkMethod {
  manual('manual', 'Set by hand'),
  cerd('cerd', 'CERD number in plant name'),
  nameLocation('name_location', 'Name and location'),
  name('name', 'Name'),
  location('location', 'Location');

  const LinkMethod(this.db, this.label);
  final String db;
  final String label;

  static LinkMethod fromDb(String? v) => values.firstWhere((m) => m.db == v, orElse: () => LinkMethod.name);
}

/// Plant (DeyeCloud station) ↔ school (CERD) link.
class StationSchoolLink {
  const StationSchoolLink({required this.stationId, required this.cerd, required this.method, required this.confidence, this.updatedAt = 0});

  final int stationId;
  final int cerd;
  final LinkMethod method;

  /// 0–1; 1 for manual links.
  final double confidence;
  final int updatedAt;

  bool get isManual => method == LinkMethod.manual;

  static StationSchoolLink fromRow(Map<String, Object?> r) => StationSchoolLink(
        stationId: asInt(r['station_id']) ?? 0,
        cerd: asInt(r['cerd']) ?? 0,
        method: LinkMethod.fromDb(r['method'] as String?),
        confidence: asDouble(r['confidence']) ?? 0,
        updatedAt: asInt(r['updated_at']) ?? 0,
      );

  Map<String, Object?> toRow() => {'station_id': stationId, 'cerd': cerd, 'method': method.db, 'confidence': confidence, 'updated_at': updatedAt};
}
