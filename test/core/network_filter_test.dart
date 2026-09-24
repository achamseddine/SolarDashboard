import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/network_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/network_filter.dart';
import 'package:unicef_solar_monitor/core/models/network_insights.dart';

import '../helpers/test_env.dart';

Future<NetworkInsights> _build(TestEnv env) async {
  final db = env.db;
  final schools = await db.schools.getSchools();
  return NetworkInsightsBuilder().build(
    networks: await db.networks.getNetworks(),
    devices: await db.networks.getDevices(),
    days: await db.networks.getDaily(),
    ssidDays: await db.networks.getSsidDaily(),
    alarms: await db.networks.getAlarms(),
    schoolsByCerd: {for (final s in schools) s.cerd: s},
    publicSchools: schools.where((s) => s.inMaster).length,
  );
}

void main() {
  test('every headline number and the list it opens are the same statement', () async {
    final env = await TestEnv.create(schools: 12, networks: 60);
    addTearDown(env.dispose);
    final d = await _build(env);

    // The tile prints the left-hand figure; tapping it lists the right-hand
    // schools. A drill-down that disagrees with the tile is the one failure
    // this whole design exists to prevent.
    final pairs = <String, (int, int)>{
      'Schools connected': (d.connected, NetworkSchoolFilter.connected.count(d)),
      'LAN operational': (d.lanOperational, NetworkSchoolFilter.lanOperational.count(d)),
      'Meaningfully connected': (d.meaningfullyConnected, NetworkSchoolFilter.meaningfullyConnected.count(d)),
      'Actively using technology': (d.activelyUsing, NetworkSchoolFilter.activelyUsing.count(d)),
      'High digital adoption': (d.highAdoption, NetworkSchoolFilter.highAdoption.count(d)),
      'Low / no adoption': (d.lowAdoption, NetworkSchoolFilter.lowAdoption.count(d)),
      'Technical intervention': (d.technicalIntervention, NetworkSchoolFilter.technicalIntervention.count(d)),
      'Adoption support': (d.adoptionSupport, NetworkSchoolFilter.adoptionSupport.count(d)),
      'Networks in the account': (d.networks, NetworkSchoolFilter.all.count(d)),
      'Not matched to a school': (d.unlinkedNetworks, NetworkSchoolFilter.unmatched.count(d)),
    };
    pairs.forEach((label, p) => expect(p.$2, p.$1, reason: '$label: the tile says ${p.$1}, the list holds ${p.$2}'));

    // The two figures that are not a count of schools still have to open a
    // list that can be read against them.
    expect(NetworkSchoolFilter.uptimeMeasured.count(d), d.schools.where((s) => s.uptimeShare != null).length);
    expect(
      NetworkSchoolFilter.clientsMeasured.select(d).fold<int>(0, (a, s) => a + (s.avgDailyClients ?? 0).round()),
      d.activeUsers,
      reason: 'the client-device headline is the sum over exactly the schools the list shows',
    );
  });

  test('an unreported day is told apart from a day with nothing on it', () async {
    final env = await TestEnv.create(schools: 8, networks: 20);
    addTearDown(env.dispose);
    final d = await _build(env);

    // The portfolio series are padded across every day in the window so the
    // chart has one bar per day; the day panel has to read the days that
    // actually carried a figure, or it prints "0 devices" for a day nobody
    // reported.
    for (final day in d.daysReportingClients) {
      expect(d.dailyClients.map((x) => x.day), contains(day));
    }
    final padded = d.dailyClients.where((x) => !d.daysReportingClients.contains(x.day));
    expect(padded.every((x) => x.clients == 0), isTrue, reason: 'a padded day should carry no figure of its own');
    expect(d.daysReportingTraffic.length, lessThanOrEqualTo(d.dailyBytes.length));
  });

  test('a slice never judges a school nobody measured', () async {
    final env = await TestEnv.create(schools: 8, networks: 30);
    addTearDown(env.dispose);
    final d = await _build(env);

    for (final s in NetworkSchoolFilter.lowAdoption.select(d)) {
      expect(s.hasUsageEvidence, isTrue, reason: '${s.name} was condemned without a measurement');
      expect(s.usageScore, isNotNull);
    }
    for (final s in NetworkSchoolFilter.highAdoption.select(d)) {
      expect(s.usageScore, isNotNull);
    }
  });

  test('a slice lists its worst offender first', () async {
    const t = NetworkThresholds();
    SchoolNetwork school(String name, {int poe = 0, int ports = 0}) => SchoolNetwork(
          networkId: name,
          name: name,
          poePortsFailed: poe,
          portsError: ports,
          components: const [],
          index: null,
          availableWeight: 0,
          quadrant: AdoptionQuadrant.unknown,
        );
    final d = NetworkInsights(
      schools: [school('A', poe: 1), school('B', poe: 9), school('C'), school('D', ports: 3)],
      publicSchools: 4,
      networks: 4,
      unlinkedNetworks: 0,
      connected: 0,
      lanOperational: 0,
      meaningfullyConnected: 0,
      activelyUsing: 0,
      highAdoption: 0,
      lowAdoption: 0,
      technicalIntervention: 3,
      adoptionSupport: 0,
      avgUptime: null,
      activeUsers: 0,
      openCriticalIncidents: 0,
      devicesByKind: const {},
      devicesOnlineByKind: const {},
      quadrants: const {},
      byRegion: const [],
      dailyClients: const [],
      dailyBytes: const [],
      dailyUptime: const [],
      ssidTraffic: const [],
      thresholds: t,
      lastSyncTs: null,
      missingSources: const [],
      days: 30,
    );

    expect(NetworkSchoolFilter.poeFailed.select(d).map((s) => s.name), ['B', 'A']);
    expect(NetworkSchoolFilter.technicalIntervention.select(d).map((s) => s.name), containsAll(['A', 'B', 'D']));
    expect(NetworkSchoolFilter.technicalIntervention.select(d).map((s) => s.name), isNot(contains('C')));
    expect(NetworkSchoolFilter.poeFailed.metric(d.schools[1]).value, '9');
  });

  test('every slice can describe itself and rank any school without throwing', () async {
    final env = await TestEnv.create(schools: 6, networks: 20);
    addTearDown(env.dispose);
    final d = await _build(env);

    for (final f in NetworkSchoolFilter.values) {
      expect(f.label, isNotEmpty);
      expect(f.what.length, greaterThan(40), reason: '${f.name} must say what the number means');
      for (final s in d.schools) {
        f.matches(s, d.thresholds);
        final m = f.metric(s);
        expect(m.value, isNotEmpty);
        expect(m.hint, isNotEmpty);
      }
      expect(f.select(d).length, f.count(d));
    }
  });
}
