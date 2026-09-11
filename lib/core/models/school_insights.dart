import 'fleet_insights.dart';
import 'school.dart';

/// One school seen through every source: MEHE master data, programme
/// tracker, energy audit, education dashboard and (when linked) the live
/// DeyeCloud plant.
class SchoolInsight {
  const SchoolInsight({
    required this.school,
    this.link,
    this.station,
    this.expectedAnnualGenKwh,
    this.measuredGenKwh30d,
    this.measuredConsKwh30d,
    this.measuredDays30d = 0,
  });

  final School school;
  final StationSchoolLink? link;

  /// Linked plant (null for schools without a monitored plant).
  final StationInsight? station;

  /// Installed kWp × specific yield (kWh/year); null without a size.
  final double? expectedAnnualGenKwh;

  /// Measured PV generation / consumption over the last 30 days (kWh).
  final double? measuredGenKwh30d;
  final double? measuredConsKwh30d;
  final int measuredDays30d;

  int get cerd => school.cerd;
  String get name => school.name;
  String get region => school.region ?? 'Unassigned';
  bool get isMonitored => station != null;
  bool get isSolarized => school.isSolarized;
  bool get isConnected => school.connected;
  double? get annualLoadKwh => school.annualLoadKwh;
  double? get kwp => school.solar?.kwp ?? station?.kwp;
  int? get students => school.students;

  /// Expected generation ÷ audited load (1.0 = sized to cover the audit).
  double? get sizingRatio => expectedAnnualGenKwh == null || annualLoadKwh == null || annualLoadKwh! <= 0 ? null : expectedAnnualGenKwh! / annualLoadKwh!;

  /// Measured 30-day generation scaled to a month ÷ monthly audited load.
  double? get measuredCoverage {
    if (measuredGenKwh30d == null || measuredDays30d == 0 || annualLoadKwh == null || annualLoadKwh! <= 0) return null;
    final monthly = measuredGenKwh30d! / measuredDays30d * 30;
    return monthly / (annualLoadKwh! / 12);
  }

  /// Measured consumption scaled to a year ÷ audited annual load.
  double? get auditAccuracy {
    if (measuredConsKwh30d == null || measuredDays30d == 0 || annualLoadKwh == null || annualLoadKwh! <= 0) return null;
    return (measuredConsKwh30d! / measuredDays30d * 365) / annualLoadKwh!;
  }

  /// Attendance of the morning shift (0–1).
  double? get attendance => school.education?.amAttendance;

  /// Plant is down while the school is not on the connectivity list — a
  /// likely cause of the outage is the logger's internet connection.
  bool get downWithoutConnectivity => station != null && station!.isDown && !school.connected;
}

/// Governorate roll-up of the programme.
class RegionCoverage {
  const RegionCoverage({
    required this.name,
    this.schools = 0,
    this.students = 0,
    this.solarized = 0,
    this.pipeline = 0,
    this.connected = 0,
    this.solarizedConnected = 0,
    this.monitored = 0,
    this.kwp = 0,
    this.costUsd = 0,
    this.annualLoadKwh = 0,
    this.expectedGenKwh = 0,
    this.studentsSolarized = 0,
    this.attendanceSolarized,
    this.attendanceOther,
  });

  final String name;
  final int schools;
  final int students;
  final int solarized;
  final int pipeline;
  final int connected;
  final int solarizedConnected;
  final int monitored;
  final double kwp;
  final double costUsd;
  final double annualLoadKwh;
  final double expectedGenKwh;
  final int studentsSolarized;
  final double? attendanceSolarized;
  final double? attendanceOther;

  int get notSolarized => schools - solarized - pipeline;
  double get solarizedShare => schools == 0 ? 0 : solarized / schools;
  double get connectedShare => schools == 0 ? 0 : connected / schools;
}

/// A named slice (donor, project, contractor, ownership…).
class ProgrammeSlice {
  const ProgrammeSlice({required this.label, this.schools = 0, this.kwp = 0, this.costUsd = 0, this.students = 0});
  final String label;
  final int schools;
  final double kwp;
  final double costUsd;
  final int students;

  ProgrammeSlice add({int schools = 0, double kwp = 0, double costUsd = 0, int students = 0}) =>
      ProgrammeSlice(label: label, schools: this.schools + schools, kwp: this.kwp + kwp, costUsd: this.costUsd + costUsd, students: this.students + students);
}

/// Attendance comparison between two groups of schools.
class AttendanceComparison {
  const AttendanceComparison({required this.label, this.meanA, this.countA = 0, this.meanB, this.countB = 0, this.highRiskA = 0, this.highRiskB = 0});
  final String label;
  final double? meanA;
  final int countA;
  final double? meanB;
  final int countB;
  final int highRiskA;
  final int highRiskB;
}

/// One inventory line aggregated over the fleet.
class EquipmentTotal {
  const EquipmentTotal({required this.type, required this.category, required this.items, required this.annualKwh});
  final String type;
  final String category;
  final int items;
  final double annualKwh;
}

/// Programme-level insights joining the school dataset with the live fleet.
class SchoolInsights {
  const SchoolInsights({
    required this.generatedAt,
    required this.specificYieldKwhPerKwp,
    required this.schools,
    required this.regions,
    required this.byStatus,
    required this.byDonor,
    required this.byProject,
    required this.byContractor,
    required this.byOwnership,
    required this.loadByCategory,
    required this.equipmentByCategory,
    required this.topEquipment,
    required this.attendance,
    required this.linkMethods,
    required this.unlinkedStations,
    this.publicSchools = 0,
    this.students = 0,
    this.solarized = 0,
    this.pipeline = 0,
    this.notSolarized = 0,
    this.connected = 0,
    this.solarizedConnected = 0,
    this.monitored = 0,
    this.stations = 0,
    this.studentsSolarized = 0,
    this.studentsConnected = 0,
    this.installedKwp = 0,
    this.inverterKw = 0,
    this.batteryKwh = 0,
    this.investmentUsd = 0,
    this.ledUsd = 0,
    this.qaUsd = 0,
    this.auditedSchools = 0,
    this.auditedLoadKwh = 0,
    this.solarizedLoadKwh = 0,
    this.solarizedAuditCount = 0,
    this.expectedGenKwh = 0,
    this.measuredGenKwh30d = 0,
    this.measuredConsKwh30d = 0,
    this.measuredSchools = 0,
    this.lightingKwh = 0,
    this.ledKwh = 0,
  });

  final DateTime generatedAt;
  final double specificYieldKwhPerKwp;

  /// Every school in the dataset (1 row per CERD), joined to its plant.
  final List<SchoolInsight> schools;
  final List<RegionCoverage> regions;
  final Map<SolarStatus, int> byStatus;
  final List<ProgrammeSlice> byDonor;
  final List<ProgrammeSlice> byProject;
  final List<ProgrammeSlice> byContractor;

  /// Ownership → (all schools, solarised schools).
  final List<(String, int, int)> byOwnership;

  /// Audited annual load per category (kWh/year), Sheet2 of the audit.
  final Map<String, double> loadByCategory;

  /// Inventory annual kWh per category (Sheet1 of the audit).
  final Map<String, double> equipmentByCategory;
  final List<EquipmentTotal> topEquipment;
  final List<AttendanceComparison> attendance;
  final Map<LinkMethod, int> linkMethods;

  /// Plants in the account that could not be matched to a school.
  final List<StationInsight> unlinkedStations;

  final int publicSchools;
  final int students;
  final int solarized;
  final int pipeline;
  final int notSolarized;
  final int connected;
  final int solarizedConnected;

  /// Solarised schools with a linked (monitored) plant.
  final int monitored;
  final int stations;
  final int studentsSolarized;
  final int studentsConnected;
  final double installedKwp;
  final double inverterKw;
  final double batteryKwh;
  final double investmentUsd;
  final double ledUsd;
  final double qaUsd;
  final int auditedSchools;
  final double auditedLoadKwh;
  final double solarizedLoadKwh;
  final int solarizedAuditCount;

  /// Expected annual generation of the solarised fleet (kWp × yield).
  final double expectedGenKwh;
  final double measuredGenKwh30d;
  final double measuredConsKwh30d;
  final int measuredSchools;
  final double lightingKwh;
  final double ledKwh;

  int get solarizedUnconnected => solarized - solarizedConnected;
  int get solarizedUnmonitored => solarized - monitored;
  double get solarizedShare => publicSchools == 0 ? 0 : solarized / publicSchools;
  double get connectedShare => publicSchools == 0 ? 0 : connected / publicSchools;
  double? get costPerKwp => installedKwp <= 0 ? null : investmentUsd / installedKwp;
  double? get costPerStudent => studentsSolarized <= 0 ? null : investmentUsd / studentsSolarized;
  double? get kwpPerHundredStudents => studentsSolarized <= 0 ? null : installedKwp / studentsSolarized * 100;

  /// Expected generation ÷ audited load of the solarised, audited schools.
  double? get fleetSizingRatio => solarizedLoadKwh <= 0 ? null : expectedGenKwh / solarizedLoadKwh;

  /// Share of lighting energy already on LED (audit inventory).
  double? get ledShare => lightingKwh <= 0 ? null : ledKwh / lightingKwh;

  Iterable<SchoolInsight> get monitoredSchools => schools.where((s) => s.isMonitored);
  Iterable<SchoolInsight> get solarizedSchools => schools.where((s) => s.isSolarized);

  /// Solarised schools with no plant in the DeyeCloud account.
  List<SchoolInsight> get unmonitoredSolarized => [for (final s in schools) if (s.isSolarized && !s.isMonitored) s];

  /// Monitored plants that are down at schools without internet connectivity.
  List<SchoolInsight> get downWithoutConnectivity => [for (final s in schools) if (s.downWithoutConnectivity) s];

  /// Highest audited loads among schools not yet solarised — candidates for
  /// the next phase.
  List<SchoolInsight> get solarCandidates {
    final out = [for (final s in schools) if (!s.isSolarized && s.school.solarStatus == null && (s.annualLoadKwh ?? 0) > 0 && s.school.inMaster) s];
    out.sort((a, b) => b.annualLoadKwh!.compareTo(a.annualLoadKwh!));
    return out;
  }

  /// Solarised, audited schools whose system covers less than 60 % of the audit.
  List<SchoolInsight> get undersized {
    final out = [for (final s in schools) if (s.isSolarized && s.sizingRatio != null && s.sizingRatio! < 0.6) s];
    out.sort((a, b) => a.sizingRatio!.compareTo(b.sizingRatio!));
    return out;
  }

  /// Monitored schools ranked by measured coverage of the audited load.
  List<SchoolInsight> get byMeasuredCoverage {
    final out = [for (final s in schools) if (s.measuredCoverage != null) s];
    out.sort((a, b) => b.measuredCoverage!.compareTo(a.measuredCoverage!));
    return out;
  }

  SchoolInsight? forStation(int stationId) {
    for (final s in schools) {
      if (s.station?.id == stationId) return s;
    }
    return null;
  }

  SchoolInsight? forCerd(int cerd) {
    for (final s in schools) {
      if (s.cerd == cerd) return s;
    }
    return null;
  }
}
