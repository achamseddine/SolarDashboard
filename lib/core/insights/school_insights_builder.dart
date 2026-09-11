import '../db/app_database.dart';
import '../models/fleet_insights.dart';
import '../models/school.dart';
import '../models/school_insights.dart';
import '../settings/app_settings.dart';
import '../sync/station_region.dart';
import '../utils/app_time.dart';

/// Joins the school dataset with plant links and the live fleet.
class SchoolInsightsBuilder {
  SchoolInsightsBuilder(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<SchoolInsights> build(AppSettings settings, FleetInsights fleet) async {
    final now = _clock();
    final yieldPerKwp = settings.specificYieldKwhPerKwp;
    final schools = await db.schools.getSchools();
    final links = await db.schools.getLinks();
    final today = AppTime.today();
    final yesterday = AppTime.addDays(today, -1);
    final d30 = AppTime.addDays(today, -30);
    final sums30 = await db.stations.dailySumsPerStation(d30, yesterday);
    final days30 = await db.stations.dailyDayCounts(d30, yesterday);
    final equipmentByCategory = await db.schools.equipmentByCategory();
    final topEquipmentRows = await db.schools.equipmentTotals(limit: 20);
    final ledRows = await db.db.rawQuery("SELECT SUM(annual_kwh) AS kwh FROM school_equipment WHERE category = 'Lighting' AND (LOWER(type) LIKE '%led%' OR LOWER(type) LIKE '%eco%' OR LOWER(type) LIKE '%econom%')");
    final ledKwh = (ledRows.first['kwh'] as num?)?.toDouble() ?? 0;

    final stationByCerd = <int, StationInsight>{};
    final linkByCerd = <int, StationSchoolLink>{};
    final byStationId = {for (final s in fleet.stations) s.id: s};
    for (final l in links.values) {
      final st = byStationId[l.stationId];
      if (st == null) continue; // archived or not yet synced
      // Prefer the strongest link when two plants claim the same school.
      final prev = linkByCerd[l.cerd];
      if (prev == null || l.confidence > prev.confidence) {
        linkByCerd[l.cerd] = l;
        stationByCerd[l.cerd] = st;
      }
    }

    final insights = <SchoolInsight>[];
    for (final school in schools) {
      final st = stationByCerd[school.cerd];
      final kwp = school.solar?.kwp ?? st?.kwp;
      final e30 = st == null ? null : sums30[st.id];
      insights.add(SchoolInsight(
        school: school,
        link: linkByCerd[school.cerd],
        station: st,
        expectedAnnualGenKwh: kwp == null || kwp <= 0 ? null : kwp * yieldPerKwp,
        measuredGenKwh30d: e30?.generationKwh,
        measuredConsKwh30d: e30?.consumptionKwh,
        measuredDays30d: st == null ? 0 : (days30[st.id] ?? 0),
      ));
    }

    // ----------------------------------------------------------- totals
    var publicSchools = 0, students = 0, solarized = 0, pipeline = 0, notSolarized = 0, connected = 0, solarizedConnected = 0, monitored = 0;
    var studentsSolarized = 0, studentsConnected = 0, auditedSchools = 0, solarizedAuditCount = 0, measuredSchools = 0;
    var installedKwp = 0.0, inverterKw = 0.0, batteryKwh = 0.0, investment = 0.0, led = 0.0, qa = 0.0;
    var auditedLoad = 0.0, solarizedLoad = 0.0, expectedGen = 0.0, gen30 = 0.0, cons30 = 0.0;
    final byStatus = <SolarStatus, int>{};
    final donor = <String, ProgrammeSlice>{};
    final project = <String, ProgrammeSlice>{};
    final contractor = <String, ProgrammeSlice>{};
    final ownershipAll = <String, int>{};
    final ownershipSolar = <String, int>{};
    final loadByCategory = <String, double>{'Lighting': 0, 'HVAC': 0, 'IT': 0, 'Miscellaneous': 0};
    final regionAcc = <String, _RegionAcc>{};

    for (final s in insights) {
      final sc = s.school;
      final region = s.region;
      final acc = regionAcc.putIfAbsent(region, () => _RegionAcc(region));
      if (sc.inMaster) {
        publicSchools++;
        students += sc.students ?? 0;
        acc.schools++;
        acc.students += sc.students ?? 0;
        final own = (sc.ownership ?? 'Unknown').trim();
        ownershipAll[own] = (ownershipAll[own] ?? 0) + 1;
      }
      if (sc.connected) {
        connected++;
        studentsConnected += sc.students ?? 0;
        acc.connected++;
      }
      final load = sc.annualLoadKwh;
      if (load != null) {
        auditedSchools++;
        auditedLoad += load;
        acc.load += load;
        for (final c in sc.loads!.categories) {
          loadByCategory[c.$1] = (loadByCategory[c.$1] ?? 0) + c.$2;
        }
      }
      final sol = sc.solar;
      if (sol != null) {
        byStatus[sol.status] = (byStatus[sol.status] ?? 0) + 1;
        if (sol.status.isPipeline) {
          pipeline++;
          acc.pipeline++;
        } else if (sol.status == SolarStatus.notSolarized) {
          notSolarized++;
        }
      }
      if (s.isSolarized) {
        solarized++;
        acc.solarized++;
        studentsSolarized += sc.students ?? 0;
        acc.studentsSolarized += sc.students ?? 0;
        installedKwp += sol!.kwp ?? 0;
        inverterKw += sol.inverterKw ?? 0;
        batteryKwh += sol.batteryKwh ?? 0;
        investment += sol.costUsd ?? 0;
        led += sol.ledCostUsd ?? 0;
        qa += sol.qaCostUsd ?? 0;
        acc.kwp += sol.kwp ?? 0;
        acc.cost += sol.costUsd ?? 0;
        if (s.expectedAnnualGenKwh != null) {
          expectedGen += s.expectedAnnualGenKwh!;
          acc.expectedGen += s.expectedAnnualGenKwh!;
        }
        if (load != null) {
          solarizedLoad += load;
          solarizedAuditCount++;
        }
        if (sc.connected) {
          solarizedConnected++;
          acc.solarizedConnected++;
        }
        if (s.isMonitored) {
          monitored++;
          acc.monitored++;
        }
        final own = (sc.ownership ?? 'Unknown').trim();
        if (sc.inMaster) ownershipSolar[own] = (ownershipSolar[own] ?? 0) + 1;
        final d = sol.donorGroup ?? sol.donor ?? 'Unknown';
        donor[d] = (donor[d] ?? ProgrammeSlice(label: d)).add(schools: 1, kwp: sol.kwp ?? 0, costUsd: sol.costUsd ?? 0, students: sc.students ?? 0);
        final p = sol.project ?? 'Unspecified';
        project[p] = (project[p] ?? ProgrammeSlice(label: p)).add(schools: 1, kwp: sol.kwp ?? 0, costUsd: sol.costUsd ?? 0, students: sc.students ?? 0);
        final c = sol.contractor ?? 'Unspecified';
        contractor[c] = (contractor[c] ?? ProgrammeSlice(label: c)).add(schools: 1, kwp: sol.kwp ?? 0, costUsd: sol.costUsd ?? 0, students: sc.students ?? 0);
      }
      if (s.measuredGenKwh30d != null && s.measuredDays30d > 0) {
        measuredSchools++;
        gen30 += s.measuredGenKwh30d!;
        cons30 += s.measuredConsKwh30d ?? 0;
      }
      final att = s.attendance;
      if (att != null && sc.inMaster) {
        if (s.isSolarized) {
          acc.attSolar.add(att);
        } else {
          acc.attOther.add(att);
        }
      }
    }

    // --------------------------------------------------------- education
    AttendanceComparison compare(String label, bool Function(SchoolInsight) inA, {bool pm = false}) {
      final a = <double>[], b = <double>[];
      var highA = 0, highB = 0;
      for (final s in insights) {
        final ed = s.school.education;
        if (ed == null || !s.school.inMaster) continue;
        final v = pm ? ed.pmAttendance : ed.amAttendance;
        final risk = pm ? ed.pmRisk : ed.amRisk;
        if (v == null) continue;
        if (inA(s)) {
          a.add(v);
          if (risk == RiskLevel.high) highA++;
        } else {
          b.add(v);
          if (risk == RiskLevel.high) highB++;
        }
      }
      return AttendanceComparison(label: label, meanA: _mean(a), countA: a.length, meanB: _mean(b), countB: b.length, highRiskA: highA, highRiskB: highB);
    }

    final attendance = [
      compare('Solarised vs not solarised (AM)', (s) => s.isSolarized),
      compare('Solarised vs not solarised (PM)', (s) => s.isSolarized, pm: true),
      compare('Connected vs not connected (AM)', (s) => s.isConnected),
      compare('Monitored plant vs no plant (AM)', (s) => s.isMonitored),
    ];

    // ------------------------------------------------------------ regions
    final regions = <RegionCoverage>[];
    for (final name in [...LebanonRegions.all, LebanonRegions.unassigned]) {
      final a = regionAcc[name];
      if (a == null || (a.schools == 0 && a.solarized == 0 && a.connected == 0)) continue;
      regions.add(RegionCoverage(
        name: name,
        schools: a.schools,
        students: a.students,
        solarized: a.solarized,
        pipeline: a.pipeline,
        connected: a.connected,
        solarizedConnected: a.solarizedConnected,
        monitored: a.monitored,
        kwp: a.kwp,
        costUsd: a.cost,
        annualLoadKwh: a.load,
        expectedGenKwh: a.expectedGen,
        studentsSolarized: a.studentsSolarized,
        attendanceSolarized: _mean(a.attSolar),
        attendanceOther: _mean(a.attOther),
      ));
    }

    List<ProgrammeSlice> sorted(Map<String, ProgrammeSlice> m) => m.values.toList()..sort((x, y) => y.kwp.compareTo(x.kwp) != 0 ? y.kwp.compareTo(x.kwp) : y.schools.compareTo(x.schools));
    final ownership = [for (final e in ownershipAll.entries) (e.key, e.value, ownershipSolar[e.key] ?? 0)]..sort((a, b) => b.$2.compareTo(a.$2));

    final linkMethods = <LinkMethod, int>{};
    for (final l in links.values) {
      if (byStationId.containsKey(l.stationId)) linkMethods[l.method] = (linkMethods[l.method] ?? 0) + 1;
    }
    final unlinked = [for (final s in fleet.stations) if (!links.containsKey(s.id)) s]..sort((a, b) => a.name.compareTo(b.name));

    return SchoolInsights(
      generatedAt: now,
      specificYieldKwhPerKwp: yieldPerKwp,
      schools: insights,
      regions: regions,
      byStatus: byStatus,
      byDonor: sorted(donor),
      byProject: sorted(project),
      byContractor: sorted(contractor),
      byOwnership: ownership,
      loadByCategory: loadByCategory,
      equipmentByCategory: equipmentByCategory,
      topEquipment: [for (final r in topEquipmentRows) EquipmentTotal(type: r.$1, category: r.$2, items: r.$3, annualKwh: r.$4)],
      attendance: attendance,
      linkMethods: linkMethods,
      unlinkedStations: unlinked,
      publicSchools: publicSchools,
      students: students,
      solarized: solarized,
      pipeline: pipeline,
      notSolarized: notSolarized,
      connected: connected,
      solarizedConnected: solarizedConnected,
      monitored: monitored,
      stations: fleet.stations.length,
      studentsSolarized: studentsSolarized,
      studentsConnected: studentsConnected,
      installedKwp: installedKwp,
      inverterKw: inverterKw,
      batteryKwh: batteryKwh,
      investmentUsd: investment,
      ledUsd: led,
      qaUsd: qa,
      auditedSchools: auditedSchools,
      auditedLoadKwh: auditedLoad,
      solarizedLoadKwh: solarizedLoad,
      solarizedAuditCount: solarizedAuditCount,
      expectedGenKwh: expectedGen,
      measuredGenKwh30d: gen30,
      measuredConsKwh30d: cons30,
      measuredSchools: measuredSchools,
      lightingKwh: loadByCategory['Lighting'] ?? 0,
      ledKwh: ledKwh,
    );
  }

  static double? _mean(List<double> v) => v.isEmpty ? null : v.fold(0.0, (a, b) => a + b) / v.length;
}

class _RegionAcc {
  _RegionAcc(this.name);
  final String name;
  int schools = 0, students = 0, solarized = 0, pipeline = 0, connected = 0, solarizedConnected = 0, monitored = 0, studentsSolarized = 0;
  double kwp = 0, cost = 0, load = 0, expectedGen = 0;
  final List<double> attSolar = [];
  final List<double> attOther = [];
}
