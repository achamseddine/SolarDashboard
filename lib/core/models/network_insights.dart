import 'gwn.dart';

/// The thresholds the indicator framework deliberately leaves to agreement:
/// what counts as meaningful connectivity, a day of activity, and sustained
/// adoption. Kept in one place so a policy change is one edit.
class NetworkThresholds {
  const NetworkThresholds({
    this.uptimeTarget = 0.95,
    this.apAvailabilityTarget = 0.90,
    this.activeDayClients = 10,
    this.activeDayMegabytes = 200,
    this.activeUseShare = 0.25,
    this.regularUseShare = 0.60,
    this.highAdoptionIndex = 70,
    this.lowAdoptionIndex = 40,
    this.infrastructureHealthy = 70,
  });

  /// Connected minutes / expected minutes a school must reach.
  final double uptimeTarget;

  /// Share of installed APs that must be online.
  final double apAvailabilityTarget;

  /// Clients on a day for it to count as a day with digital activity.
  final int activeDayClients;

  /// …and the traffic it must also carry.
  final int activeDayMegabytes;

  /// Share of school days with activity for a school to count as actively
  /// using technology at all.
  final double activeUseShare;

  /// Share of school days with activity that counts as regular use.
  final double regularUseShare;

  /// Adoption index at or above which a school is "high adoption".
  final double highAdoptionIndex;

  /// …and below which it is "low / no adoption".
  final double lowAdoptionIndex;

  /// Infrastructure score at or above which infrastructure counts as healthy.
  final double infrastructureHealthy;
}

/// One weighted component of the Technology Adoption Index (section 9).
///
/// [score] is null when the app has no source for it; the index is then
/// renormalised over the components it does have, and the UI says which
/// weight is missing rather than scoring a school on data it never saw.
class IndexComponent {
  const IndexComponent(this.label, this.weight, this.score, {this.missingSource});

  final String label;

  /// Framework weight, 0–1.
  final double weight;

  /// 0–100, or null when unavailable.
  final double? score;

  /// What would have to be connected to fill it in.
  final String? missingSource;

  bool get isAvailable => score != null;
}

/// Where a school sits in the infrastructure × adoption matrix (section 10).
enum AdoptionQuadrant {
  active('Digitally active', 'Infrastructure healthy and technology in regular use'),
  adoptionSupport('Adoption support needed', 'Infrastructure is healthy but use stays low'),
  constrained('Infrastructure constrains use', 'Demand exists but the network cannot carry it'),
  technical('Technical intervention needed', 'Infrastructure is unhealthy and use is low'),
  unknown('Not enough data', 'Too few reporting days to place this school');

  const AdoptionQuadrant(this.label, this.description);
  final String label;
  final String description;
}

/// Every framework indicator the app can compute for one school.
class SchoolNetwork {
  const SchoolNetwork({
    required this.networkId,
    required this.name,
    this.cerd,
    this.region,
    this.caza,
    this.students,
    this.teachers,
    // Infrastructure health (section 2)
    this.gatewayOnline,
    this.switchesTotal = 0,
    this.switchesOnline = 0,
    this.apsTotal = 0,
    this.apsOnline = 0,
    this.poePortsFailed = 0,
    this.portsError = 0,
    this.firmwareTotal = 0,
    this.firmwareCompliant = 0,
    this.cpuMax,
    this.memoryMax,
    // Internet (section 3)
    this.uptimeShare,
    this.downtimeHours,
    this.daysReported = 0,
    this.daysSinceOutage,
    // Wi-Fi and usage (section 4)
    this.avgDailyClients,
    this.peakClients,
    this.avgDailyBytes,
    this.totalBytes,
    this.activeApShare,
    // Adoption (section 5)
    this.daysWithActivity = 0,
    this.schoolDays = 0,
    this.usageGrowth,
    this.teachingHoursShare,
    // Support (section 7)
    this.openAlarms = 0,
    this.openCriticalAlarms = 0,
    this.seenOnline = false,
    this.hasUsageEvidence = false,
    this.usageScore,
    required this.components,
    required this.index,
    required this.availableWeight,
    required this.quadrant,
  });

  final String networkId;
  final String name;
  final int? cerd;
  final String? region;
  final String? caza;
  final int? students;
  final int? teachers;

  final bool? gatewayOnline;
  final int switchesTotal;
  final int switchesOnline;
  final int apsTotal;
  final int apsOnline;
  final int poePortsFailed;
  final int portsError;
  final int firmwareTotal;
  final int firmwareCompliant;
  final double? cpuMax;
  final double? memoryMax;

  final double? uptimeShare;
  final double? downtimeHours;
  final int daysReported;
  final int? daysSinceOutage;

  final double? avgDailyClients;
  final int? peakClients;
  final double? avgDailyBytes;
  final int? totalBytes;
  final double? activeApShare;

  final int daysWithActivity;
  final int schoolDays;
  final double? usageGrowth;
  final double? teachingHoursShare;

  final int openAlarms;
  final int openCriticalAlarms;

  /// At least one observation found this school's network up. Knowable from
  /// a single look, unlike a percentage.
  final bool seenOnline;

  /// At least one day carried a client count or traffic figure, so the
  /// adoption indicators are judging something that was measured.
  final bool hasUsageEvidence;

  /// How much the network is actually used, 0–100: Wi-Fi utilisation and
  /// regularity only. The framework's "low / no adoption" means healthy
  /// infrastructure with weak use, so it reads this rather than the index —
  /// which, with the platform components unavailable, is half infrastructure
  /// and would rate an unused school around 60.
  final double? usageScore;

  final List<IndexComponent> components;

  /// Technology Adoption Index, 0–100, over the available components.
  final double? index;

  /// Share of the framework's weight the index could actually be computed on.
  final double availableWeight;

  final AdoptionQuadrant quadrant;

  double? get apAvailability => apsTotal == 0 ? null : apsOnline / apsTotal;
  double? get switchAvailability => switchesTotal == 0 ? null : switchesOnline / switchesTotal;
  double? get firmwareCompliance => firmwareTotal == 0 ? null : firmwareCompliant / firmwareTotal;
  double? get activityShare => schoolDays == 0 ? null : daysWithActivity / schoolDays;

  /// A school has a working LAN when its gateway answers and the agreed share
  /// of its APs is up.
  bool get lanOperational {
    if (gatewayOnline != true) return false;
    final ap = apAvailability;
    return ap == null || ap >= 0.5;
  }

  bool get hasFault => gatewayOnline == false || openCriticalAlarms > 0 || poePortsFailed > 0 || portsError > 0;

  double? scoreOf(String label) => components.where((c) => c.label == label).firstOrNull?.score;
}

/// Portfolio roll-up: the executive headline indicators (section 1), the
/// matrix (section 10) and the lists a manager acts on.
class NetworkInsights {
  const NetworkInsights({
    required this.schools,
    required this.publicSchools,
    required this.networks,
    required this.unlinkedNetworks,
    required this.connected,
    required this.lanOperational,
    required this.meaningfullyConnected,
    required this.activelyUsing,
    required this.highAdoption,
    required this.lowAdoption,
    required this.technicalIntervention,
    required this.adoptionSupport,
    required this.avgUptime,
    required this.activeUsers,
    required this.openCriticalIncidents,
    required this.devicesByKind,
    required this.devicesOnlineByKind,
    required this.quadrants,
    required this.byRegion,
    required this.dailyClients,
    required this.dailyBytes,
    required this.dailyUptime,
    required this.ssidTraffic,
    required this.thresholds,
    required this.lastSyncTs,
    required this.missingSources,
    required this.days,
  });

  /// Schools with a GWN network the app could compute indicators for.
  final List<SchoolNetwork> schools;

  /// Public schools in the MEHE master list — the framework's denominator.
  final int publicSchools;

  /// Networks in the GWN account.
  final int networks;

  /// …of which none could be matched to a school.
  final int unlinkedNetworks;

  final int connected;
  final int lanOperational;
  final int meaningfullyConnected;
  final int activelyUsing;
  final int highAdoption;
  final int lowAdoption;
  final int technicalIntervention;
  final int adoptionSupport;
  final double? avgUptime;
  final int activeUsers;
  final int openCriticalIncidents;

  final Map<GwnDeviceKind, int> devicesByKind;
  final Map<GwnDeviceKind, int> devicesOnlineByKind;

  final Map<AdoptionQuadrant, int> quadrants;

  /// Per governorate: schools, connected, active, mean index.
  final List<RegionNetwork> byRegion;

  /// Portfolio series over the window, oldest first.
  final List<({String day, int clients})> dailyClients;
  final List<({String day, int bytes})> dailyBytes;
  final List<({String day, double uptime})> dailyUptime;

  /// Traffic per SSID over the window, largest first.
  final List<({String ssid, int bytes, int clients})> ssidTraffic;

  final NetworkThresholds thresholds;
  final int? lastSyncTs;

  /// Framework indicators the app has no source for, with what they need.
  final List<({String indicator, String source})> missingSources;

  /// Days in the reporting window.
  final int days;

  double get connectedShare => publicSchools == 0 ? 0 : connected / publicSchools;
  double get activeShare => publicSchools == 0 ? 0 : activelyUsing / publicSchools;
  bool get isEmpty => networks == 0;
}

/// One governorate's network roll-up.
class RegionNetwork {
  const RegionNetwork({
    required this.region,
    required this.schools,
    required this.connected,
    required this.active,
    required this.meanIndex,
    required this.meanUptime,
  });

  final String region;
  final int schools;
  final int connected;
  final int active;
  final double? meanIndex;
  final double? meanUptime;
}
