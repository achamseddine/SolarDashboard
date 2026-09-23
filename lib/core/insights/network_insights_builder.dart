import 'dart:math' as math;

import '../models/gwn.dart';
import '../models/network_insights.dart';
import '../models/school.dart';

/// Turns the stored GWN rows into the indicator framework: the per-school
/// record, the Technology Adoption Index with its components, the
/// infrastructure × adoption matrix and the portfolio headline figures.
///
/// Indicators the account cannot supply (speed tests, ISP contracts, learning
/// platforms, helpdesk, UPS telemetry) are reported as missing sources rather
/// than scored as zero, so a school is never marked down for data nobody
/// collected.
class NetworkInsightsBuilder {
  const NetworkInsightsBuilder({this.thresholds = const NetworkThresholds()});

  final NetworkThresholds thresholds;

  /// Framework weights, section 9.
  static const wInfrastructure = 0.15;
  static const wInternet = 0.15;
  static const wQuality = 0.10;
  static const wWifi = 0.15;
  static const wRegularity = 0.15;
  static const wTeacher = 0.15;
  static const wStudent = 0.10;
  static const wLearning = 0.05;

  /// Indicators in the framework that need a source the app is not connected
  /// to. Shown in the UI so an empty tile explains itself.
  static const missingSources = <({String indicator, String source})>[
    (indicator: 'Download and upload speed, latency, packet loss, jitter', source: 'Independent internet monitoring or scheduled speed tests'),
    (indicator: 'Contracted bandwidth, actual vs contracted, ISP SLA compliance', source: 'ISP contract and package data'),
    (indicator: 'Learning-platform users, active teachers and students, sessions', source: 'Madristi / Learning Passport platform analytics'),
    (indicator: 'Incidents, mean time to repair, repeat faults', source: 'Helpdesk and maintenance records'),
    (indicator: 'UPS availability, battery state, load, backup time, power events', source: 'UPS telemetry where SNMP has been installed'),
    (indicator: 'Configuration compliance', source: 'An expected VLAN / SSID / firewall baseline to compare against'),
  ];

  NetworkInsights build({
    required List<GwnNetwork> networks,
    required List<GwnDevice> devices,
    required List<GwnNetworkDay> days,
    required List<GwnSsidDay> ssidDays,
    required List<GwnAlarm> alarms,
    required Map<int, School> schoolsByCerd,
    required int publicSchools,
    int? lastSyncTs,
    int windowDays = 30,
  }) {
    final devicesByNetwork = <String, List<GwnDevice>>{};
    for (final d in devices) {
      devicesByNetwork.putIfAbsent(d.networkId, () => []).add(d);
    }
    final daysByNetwork = <String, List<GwnNetworkDay>>{};
    for (final d in days) {
      daysByNetwork.putIfAbsent(d.networkId, () => []).add(d);
    }
    for (final list in daysByNetwork.values) {
      list.sort((a, b) => a.day.compareTo(b.day));
    }
    final alarmsByNetwork = <String, List<GwnAlarm>>{};
    for (final a in alarms) {
      alarmsByNetwork.putIfAbsent(a.networkId, () => []).add(a);
    }

    final schools = <SchoolNetwork>[];
    for (final n in networks) {
      schools.add(_school(
        network: n,
        devices: devicesByNetwork[n.id] ?? const [],
        days: daysByNetwork[n.id] ?? const [],
        alarms: alarmsByNetwork[n.id] ?? const [],
        school: n.cerd == null ? null : schoolsByCerd[n.cerd],
      ));
    }
    schools.sort((a, b) => a.name.compareTo(b.name));

    // ---------------------------------------------------------- headline
    final t = thresholds;
    var connected = 0, lan = 0, meaningful = 0, active = 0, high = 0, low = 0, technical = 0, support = 0;
    var activeUsers = 0;
    final uptimes = <double>[];
    final quadrants = {for (final q in AdoptionQuadrant.values) q: 0};
    for (final s in schools) {
      if ((s.uptimeShare ?? 0) > 0) connected++;
      if (s.lanOperational) lan++;
      final ap = s.apAvailability;
      if ((s.uptimeShare ?? 0) >= t.uptimeTarget && (ap == null || ap >= t.apAvailabilityTarget)) meaningful++;
      if ((s.activityShare ?? 0) >= t.activeUseShare) active++;
      if ((s.index ?? 0) >= t.highAdoptionIndex) high++;
      if (s.index != null && s.index! < t.lowAdoptionIndex) low++;
      if (s.hasFault) technical++;
      if (s.quadrant == AdoptionQuadrant.adoptionSupport) support++;
      if (s.uptimeShare != null) uptimes.add(s.uptimeShare!);
      activeUsers += (s.avgDailyClients ?? 0).round();
      quadrants[s.quadrant] = (quadrants[s.quadrant] ?? 0) + 1;
    }

    // ------------------------------------------------------------ devices
    final byKind = <GwnDeviceKind, int>{};
    final onlineByKind = <GwnDeviceKind, int>{};
    for (final d in devices) {
      byKind[d.kind] = (byKind[d.kind] ?? 0) + 1;
      if (d.isOnline) onlineByKind[d.kind] = (onlineByKind[d.kind] ?? 0) + 1;
    }

    // ----------------------------------------------------- portfolio series
    final clientsByDay = <String, int>{};
    final bytesByDay = <String, int>{};
    final upByDay = <String, List<double>>{};
    for (final d in days) {
      if (d.uniqueClients != null) clientsByDay[d.day] = (clientsByDay[d.day] ?? 0) + d.uniqueClients!;
      final b = d.totalBytes;
      if (b != null) bytesByDay[d.day] = (bytesByDay[d.day] ?? 0) + b;
      final u = d.uptimeShare;
      if (u != null) upByDay.putIfAbsent(d.day, () => []).add(u);
    }
    final dayKeys = {...clientsByDay.keys, ...bytesByDay.keys, ...upByDay.keys}.toList()..sort();

    // ---------------------------------------------------------------- SSID
    final ssidBytes = <String, int>{};
    final ssidClients = <String, int>{};
    for (final s in ssidDays) {
      ssidBytes[s.ssid] = (ssidBytes[s.ssid] ?? 0) + (s.bytes ?? 0);
      ssidClients[s.ssid] = math.max(ssidClients[s.ssid] ?? 0, s.clients ?? 0);
    }
    final ssidTraffic = ssidBytes.entries
        .map((e) => (ssid: e.key, bytes: e.value, clients: ssidClients[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    // -------------------------------------------------------------- regions
    final regionRows = <String, List<SchoolNetwork>>{};
    for (final s in schools) {
      regionRows.putIfAbsent(s.region ?? 'Unassigned', () => []).add(s);
    }
    final byRegion = regionRows.entries.map((e) {
      final rows = e.value;
      final idx = rows.map((r) => r.index).whereType<double>().toList();
      final ups = rows.map((r) => r.uptimeShare).whereType<double>().toList();
      return RegionNetwork(
        region: e.key,
        schools: rows.length,
        connected: rows.where((r) => (r.uptimeShare ?? 0) > 0).length,
        active: rows.where((r) => (r.activityShare ?? 0) >= t.activeUseShare).length,
        meanIndex: idx.isEmpty ? null : idx.reduce((a, b) => a + b) / idx.length,
        meanUptime: ups.isEmpty ? null : ups.reduce((a, b) => a + b) / ups.length,
      );
    }).toList()
      ..sort((a, b) => b.schools.compareTo(a.schools));

    return NetworkInsights(
      schools: schools,
      publicSchools: publicSchools,
      networks: networks.length,
      unlinkedNetworks: networks.where((n) => n.cerd == null).length,
      connected: connected,
      lanOperational: lan,
      meaningfullyConnected: meaningful,
      activelyUsing: active,
      highAdoption: high,
      lowAdoption: low,
      technicalIntervention: technical,
      adoptionSupport: support,
      avgUptime: uptimes.isEmpty ? null : uptimes.reduce((a, b) => a + b) / uptimes.length,
      activeUsers: activeUsers,
      openCriticalIncidents: alarms.where((a) => a.isOpen && a.level == GwnAlarmLevel.critical).length,
      devicesByKind: byKind,
      devicesOnlineByKind: onlineByKind,
      quadrants: quadrants,
      byRegion: byRegion,
      dailyClients: [for (final d in dayKeys) (day: d, clients: clientsByDay[d] ?? 0)],
      dailyBytes: [for (final d in dayKeys) (day: d, bytes: bytesByDay[d] ?? 0)],
      dailyUptime: [
        for (final d in dayKeys)
          if (upByDay[d] != null && upByDay[d]!.isNotEmpty)
            (day: d, uptime: upByDay[d]!.reduce((a, b) => a + b) / upByDay[d]!.length),
      ],
      ssidTraffic: ssidTraffic,
      thresholds: t,
      lastSyncTs: lastSyncTs,
      missingSources: missingSources,
      days: windowDays,
    );
  }

  // ------------------------------------------------------------ one school

  SchoolNetwork _school({
    required GwnNetwork network,
    required List<GwnDevice> devices,
    required List<GwnNetworkDay> days,
    required List<GwnAlarm> alarms,
    required School? school,
  }) {
    final aps = devices.where((d) => d.kind == GwnDeviceKind.accessPoint).toList();
    final switches = devices.where((d) => d.kind == GwnDeviceKind.networkSwitch).toList();
    final gateways = devices.where((d) => d.kind == GwnDeviceKind.router).toList();

    final apsOnline = aps.where((d) => d.isOnline).length;
    final switchesOnline = switches.where((d) => d.isOnline).length;
    final gatewayOnline = gateways.isEmpty ? null : gateways.any((d) => d.isOnline);

    // Firmware compliance: the most common firmware in the account counts as
    // approved until a baseline is configured.
    final firmwares = devices.map((d) => d.firmware).whereType<String>().toList();
    final approved = _mode(firmwares);
    final firmwareCompliant = approved == null ? 0 : firmwares.where((f) => f == approved).length;

    final poeFailed = devices.map((d) => d.poePortsFailed ?? 0).fold<int>(0, (a, b) => a + b);
    final portsError = devices.map((d) => d.portsError ?? 0).fold<int>(0, (a, b) => a + b);
    final cpuMax = _maxOf(devices.map((d) => d.cpuPercent));
    final memMax = _maxOf(devices.map((d) => d.memoryPercent));

    // ------------------------------------------------------------ internet
    final upShares = days.map((d) => d.uptimeShare).whereType<double>().toList();
    final uptime = upShares.isEmpty ? null : upShares.reduce((a, b) => a + b) / upShares.length;
    final downMinutes = days.fold<int>(0, (a, d) {
      final exp = d.expectedMinutes, up = d.wanUpMinutes;
      return exp == null || up == null ? a : a + math.max(0, exp - up);
    });
    int? sinceOutage;
    for (var i = days.length - 1; i >= 0; i--) {
      if ((days[i].uptimeShare ?? 1) < 1) break;
      sinceOutage = days.length - i;
    }

    // --------------------------------------------------------------- usage
    final clientDays = days.map((d) => d.uniqueClients).whereType<int>().toList();
    final byteDays = days.map((d) => d.totalBytes).whereType<int>().toList();
    final avgClients = clientDays.isEmpty ? null : clientDays.reduce((a, b) => a + b) / clientDays.length;
    final avgBytes = byteDays.isEmpty ? null : byteDays.reduce((a, b) => a + b) / byteDays.length;
    final peak = days.map((d) => d.peakClients).whereType<int>().fold<int?>(null, (m, v) => m == null || v > m ? v : m);
    final totalBytes = byteDays.isEmpty ? null : byteDays.reduce((a, b) => a + b);
    final apShares = days
        .where((d) => (d.apsTotal ?? 0) > 0 && d.activeAps != null)
        .map((d) => d.activeAps! / d.apsTotal!)
        .toList();
    final activeApShare = apShares.isEmpty ? null : apShares.reduce((a, b) => a + b) / apShares.length;

    final activeDays = days.where(_isActiveDay).length;
    final teachingBytes = days.map((d) => d.teachingHoursBytes).whereType<int>().fold<int>(0, (a, b) => a + b);
    final teachingShare = teachingBytes == 0 || (totalBytes ?? 0) == 0 ? null : teachingBytes / totalBytes!;

    // Usage growth: the second half of the window against the first.
    double? growth;
    if (days.length >= 4) {
      final half = days.length ~/ 2;
      final older = days.take(half).map((d) => d.totalBytes ?? 0).fold<int>(0, (a, b) => a + b);
      final newer = days.skip(half).map((d) => d.totalBytes ?? 0).fold<int>(0, (a, b) => a + b);
      if (older > 0) growth = (newer - older) / older;
    }

    // -------------------------------------------------------------- scores
    final infraParts = <double>[
      if (gatewayOnline != null) gatewayOnline ? 1 : 0,
      if (aps.isNotEmpty) apsOnline / aps.length,
      if (switches.isNotEmpty) switchesOnline / switches.length,
    ];
    final infra = infraParts.isEmpty ? null : 100 * infraParts.reduce((a, b) => a + b) / infraParts.length;

    final internet = uptime == null ? null : 100 * uptime;

    final wifiParts = <double>[
      ?activeApShare,
      if (avgClients != null) math.min(1.0, avgClients / math.max(1, 2 * thresholds.activeDayClients)),
    ];
    final wifi = wifiParts.isEmpty ? null : 100 * wifiParts.reduce((a, b) => a + b) / wifiParts.length;

    final regularity = days.isEmpty ? null : 100 * activeDays / days.length;

    final components = <IndexComponent>[
      IndexComponent('Infrastructure availability', wInfrastructure, infra),
      IndexComponent('Internet reliability', wInternet, internet),
      const IndexComponent('Connectivity quality', wQuality, null, missingSource: 'speed, latency and packet-loss tests'),
      IndexComponent('Wi-Fi utilisation', wWifi, wifi),
      IndexComponent('Regularity of usage', wRegularity, regularity),
      const IndexComponent('Teacher / platform adoption', wTeacher, null, missingSource: 'learning-platform analytics'),
      const IndexComponent('Student / platform adoption', wStudent, null, missingSource: 'learning-platform analytics'),
      const IndexComponent('Digital-learning application usage', wLearning, null, missingSource: 'learning-platform analytics'),
    ];
    final available = components.where((c) => c.isAvailable).toList();
    final availableWeight = available.fold<double>(0, (a, c) => a + c.weight);
    final index = availableWeight == 0
        ? null
        : available.fold<double>(0, (a, c) => a + c.weight * c.score!) / availableWeight;

    // The matrix axes stay independent: infrastructure on one, usage on the
    // other, so a healthy school with no use is told apart from a used school
    // with a broken network.
    final usageParts = <double>[?wifi, ?regularity];
    final usage = usageParts.isEmpty ? null : usageParts.reduce((a, b) => a + b) / usageParts.length;
    final quadrant = infra == null || usage == null
        ? AdoptionQuadrant.unknown
        : infra >= thresholds.infrastructureHealthy
            ? (usage >= thresholds.lowAdoptionIndex ? AdoptionQuadrant.active : AdoptionQuadrant.adoptionSupport)
            : (usage >= thresholds.lowAdoptionIndex ? AdoptionQuadrant.constrained : AdoptionQuadrant.technical);

    return SchoolNetwork(
      networkId: network.id,
      name: school?.name ?? network.name,
      cerd: network.cerd,
      region: school?.region,
      caza: school?.caza,
      students: school?.students,
      teachers: school?.education?.pmTeachers,
      gatewayOnline: gatewayOnline,
      switchesTotal: switches.length,
      switchesOnline: switchesOnline,
      apsTotal: aps.length,
      apsOnline: apsOnline,
      poePortsFailed: poeFailed,
      portsError: portsError,
      firmwareTotal: firmwares.length,
      firmwareCompliant: firmwareCompliant,
      cpuMax: cpuMax,
      memoryMax: memMax,
      uptimeShare: uptime,
      downtimeHours: days.isEmpty ? null : downMinutes / 60,
      daysReported: days.length,
      daysSinceOutage: sinceOutage,
      avgDailyClients: avgClients,
      peakClients: peak,
      avgDailyBytes: avgBytes,
      totalBytes: totalBytes,
      activeApShare: activeApShare,
      daysWithActivity: activeDays,
      schoolDays: days.length,
      usageGrowth: growth,
      teachingHoursShare: teachingShare,
      openAlarms: alarms.where((a) => a.isOpen).length,
      openCriticalAlarms: alarms.where((a) => a.isOpen && a.level == GwnAlarmLevel.critical).length,
      components: components,
      index: index,
      availableWeight: availableWeight,
      quadrant: quadrant,
    );
  }

  /// A day counts as digital activity when it carried both the agreed number
  /// of clients and the agreed traffic.
  bool _isActiveDay(GwnNetworkDay d) {
    final clients = d.uniqueClients;
    final bytes = d.totalBytes;
    if (clients == null || bytes == null) return false;
    return clients >= thresholds.activeDayClients && bytes >= thresholds.activeDayMegabytes * 1024 * 1024;
  }

  static double? _maxOf(Iterable<double?> xs) {
    double? m;
    for (final x in xs) {
      if (x != null && (m == null || x > m)) m = x;
    }
    return m;
  }

  static String? _mode(List<String> xs) {
    if (xs.isEmpty) return null;
    final counts = <String, int>{};
    for (final x in xs) {
      counts[x] = (counts[x] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
