import '../utils/format.dart';
import 'network_insights.dart';

/// One named slice of the monitored schools.
///
/// Every number-bearing tile on the network dashboards is a count over the
/// same list of schools, so the predicate lives here once and both the tile
/// and the list it opens read it. A drill-down that disagrees with the number
/// it was opened from is worse than no drill-down at all, and the only way to
/// keep them agreeing as the framework's rules change is to have one rule.
enum NetworkSchoolFilter {
  all(
    'Networks in the account',
    'Every network read from the GWN Cloud account. Each one becomes a school record here, whether or not its name carried a CERD number the app could match.',
  ),
  connected(
    'Schools connected',
    'Seen online at least once since the app started watching. One look is enough to say a school is connected — it is not enough to say how reliably.',
  ),
  lanOperational(
    'LAN operational',
    'The gateway answers and at least half the installed access points are up. Where the account exposes no gateway, the access points alone decide.',
  ),
  meaningfullyConnected(
    'Meaningfully connected',
    'Uptime at or above the agreed target across a day of checks, with the access points available too. Speed, latency and packet loss are not measured, so this is reliability only.',
  ),
  activelyUsing(
    'Actively using technology',
    'Carried both the agreed client count and the agreed traffic on at least the agreed share of the days that were measured.',
  ),
  highAdoption(
    'High digital adoption',
    'Sustained use: Wi-Fi utilisation and regularity together at or above the high-adoption mark. Only schools where use was actually measured can appear.',
  ),
  lowAdoption(
    'Low / no adoption',
    'Use was measured and came back weak. Schools nobody has measured yet are deliberately absent — an unmeasured school is not a school that failed.',
  ),
  technicalIntervention(
    'Technical intervention',
    'A fault a technician can act on: the gateway is down, most access points are down, PoE or LAN ports have failed, or a critical alarm is open.',
  ),
  adoptionSupport(
    'Adoption support',
    'The infrastructure is healthy and the network still goes largely unused — a training and leadership question rather than a maintenance one.',
  ),
  uptimeMeasured(
    'Average network uptime',
    'Schools checked often enough in a day for a share to mean anything. The headline is the mean of their uptimes; a school checked once carries no share and is not counted.',
  ),
  clientsMeasured(
    'Active client devices',
    'Schools where the cloud reported a client count. The headline adds their daily means — devices, not people: a phone that randomises its address counts more than once.',
  ),
  openIncidents(
    'Open critical incidents',
    'Schools carrying at least one unresolved critical alarm. The headline counts the alarms, so a school with three appears here once.',
  ),
  unmatched(
    'Networks not matched to a school',
    'The network name carried no CERD number the app could match to the MEHE master list, so the school behind it is unknown and its governorate and enrolment are missing.',
  ),
  gatewayOffline(
    'Gateways offline',
    'A gateway is reported for the school and at least one of them is not answering. A school with a second gateway still up belongs here — the dead one is still a site visit.',
  ),
  apsOffline(
    'Access points down',
    'At least one installed access point is not reporting. The whole school need not be down for this to matter — a dead access point is a classroom without Wi-Fi.',
  ),
  switchesOffline(
    'Switches offline',
    'At least one installed switch is not reporting.',
  ),
  poeFailed(
    'PoE ports failed',
    'Ports that should be powering an access point or a camera and are not. Usually the cause of an access point that went dark.',
  ),
  portErrors(
    'LAN ports with errors',
    'Ports reporting errors — commonly a damaged cable or a failing patch panel port, and a slow network long before it is a dead one.',
  ),
  firmwareOutdated(
    'Devices off the firmware baseline',
    'Devices not on the release most of the account runs, which stands in for an approved baseline until one is configured.',
  );

  const NetworkSchoolFilter(this.label, this.what);

  /// Headline label this slice belongs to.
  final String label;

  /// What the number actually says, in the operator's terms.
  final String what;

  /// Whether one school belongs in this slice.
  bool matches(SchoolNetwork s, NetworkThresholds t) => switch (this) {
        all => true,
        connected => s.seenOnline,
        lanOperational => s.lanOperational,
        meaningfullyConnected => s.uptimeShare != null &&
            s.uptimeShare! >= t.uptimeTarget &&
            (s.apAvailability == null || s.apAvailability! >= t.apAvailabilityTarget),
        activelyUsing => (s.activityShare ?? 0) >= t.activeUseShare,
        highAdoption => s.usageScore != null && s.usageScore! >= t.highAdoptionIndex,
        lowAdoption => s.usageScore != null && s.usageScore! < t.lowAdoptionIndex,
        technicalIntervention => s.hasFault,
        adoptionSupport => s.quadrant == AdoptionQuadrant.adoptionSupport,
        uptimeMeasured => s.uptimeShare != null,
        clientsMeasured => s.avgDailyClients != null,
        openIncidents => s.openCriticalAlarms > 0,
        unmatched => s.cerd == null,
        gatewayOffline => s.gatewaysTotal > 0 && s.gatewaysOnline < s.gatewaysTotal,
        apsOffline => s.apsTotal > 0 && s.apsOnline < s.apsTotal,
        switchesOffline => s.switchesTotal > 0 && s.switchesOnline < s.switchesTotal,
        poeFailed => s.poePortsFailed > 0,
        portErrors => s.portsError > 0,
        firmwareOutdated => s.firmwareTotal > 0 && s.firmwareCompliant < s.firmwareTotal,
      };

  /// The figure worth reading beside each school in this slice — the one the
  /// tile was counting, not a generic status.
  ({String value, String hint}) metric(SchoolNetwork s) => switch (this) {
        gatewayOffline => (value: '${s.gatewaysOnline} / ${s.gatewaysTotal}', hint: 'gateways up'),
        connected || lanOperational || all || unmatched || apsOffline =>
          s.apsTotal == 0 ? (value: Fmt.ratio(s.uptimeShare, decimals: 1), hint: 'uptime') : (value: '${s.apsOnline} / ${s.apsTotal}', hint: 'APs up'),
        meaningfullyConnected || uptimeMeasured => (value: Fmt.ratio(s.uptimeShare, decimals: 1), hint: 'uptime'),
        activelyUsing => (value: '${s.daysWithActivity} / ${s.schoolDays}', hint: 'active days'),
        highAdoption || lowAdoption || adoptionSupport =>
          (value: s.usageScore == null ? '–' : s.usageScore!.toStringAsFixed(0), hint: 'use score'),
        clientsMeasured => (value: s.avgDailyClients == null ? '–' : Fmt.int_(s.avgDailyClients!.round()), hint: 'devices / day'),
        technicalIntervention => (value: Fmt.int_(_faults(s)), hint: 'faults'),
        openIncidents => (value: Fmt.int_(s.openCriticalAlarms), hint: 'critical'),
        switchesOffline => (value: '${s.switchesOnline} / ${s.switchesTotal}', hint: 'switches up'),
        poeFailed => (value: Fmt.int_(s.poePortsFailed), hint: 'PoE failed'),
        portErrors => (value: Fmt.int_(s.portsError), hint: 'port errors'),
        firmwareOutdated => (value: Fmt.int_(s.firmwareTotal - s.firmwareCompliant), hint: 'off baseline'),
      };

  /// Sort key inside the slice, largest first — the worst offender or the
  /// strongest performer, whichever the slice is about.
  double? _rank(SchoolNetwork s) => switch (this) {
        connected || lanOperational || all || unmatched => s.apsTotal == 0 ? s.uptimeShare : s.apsOnline / s.apsTotal,
        meaningfullyConnected || uptimeMeasured => s.uptimeShare,
        activelyUsing => s.activityShare,
        highAdoption || adoptionSupport => s.usageScore,
        lowAdoption => s.usageScore == null ? null : -s.usageScore!,
        clientsMeasured => s.avgDailyClients,
        technicalIntervention => _faults(s).toDouble(),
        openIncidents => s.openCriticalAlarms.toDouble(),
        gatewayOffline => (s.gatewaysTotal - s.gatewaysOnline).toDouble(),
        apsOffline => (s.apsTotal - s.apsOnline).toDouble(),
        switchesOffline => (s.switchesTotal - s.switchesOnline).toDouble(),
        poeFailed => s.poePortsFailed.toDouble(),
        portErrors => s.portsError.toDouble(),
        firmwareOutdated => (s.firmwareTotal - s.firmwareCompliant).toDouble(),
      };

  static int _faults(SchoolNetwork s) =>
      (s.gatewayOnline == false ? 1 : 0) + (s.apsMostlyDown ? 1 : 0) + (s.openCriticalAlarms > 0 ? 1 : 0) + (s.poePortsFailed > 0 ? 1 : 0) + (s.portsError > 0 ? 1 : 0);

  /// The schools behind the number, worst or strongest first.
  List<SchoolNetwork> select(NetworkInsights d) {
    final rows = d.schools.where((s) => matches(s, d.thresholds)).toList();
    rows.sort((a, b) {
      final ra = _rank(a), rb = _rank(b);
      if (ra == null && rb == null) return a.name.compareTo(b.name);
      if (ra == null) return 1;
      if (rb == null) return -1;
      final r = rb.compareTo(ra);
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    return rows;
  }

  /// How many schools the slice holds.
  int count(NetworkInsights d) => d.schools.where((s) => matches(s, d.thresholds)).length;
}
