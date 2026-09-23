import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/network_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';
import 'package:unicef_solar_monitor/core/models/network_insights.dart';
import 'package:unicef_solar_monitor/core/schools/network_school_linker.dart';

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
  test('the sync fills every GWN table and links networks to schools', () async {
    final env = await TestEnv.create(schools: 10, networks: 40);
    addTearDown(env.dispose);

    final networks = await env.db.networks.getNetworks();
    expect(networks.length, 40);
    expect(await env.db.networks.getDevices(), isNotEmpty);
    expect(await env.db.networks.getDaily(), isNotEmpty);
    expect(await env.db.networks.getSsidDaily(), isNotEmpty);

    // Networks are named after real schools, so most should match a CERD.
    final linked = networks.where((n) => n.cerd != null).length;
    expect(linked, greaterThan(20), reason: 'name matching should link most demo networks');
    for (final n in networks.where((n) => n.cerd != null)) {
      expect(n.linkConfidence, greaterThanOrEqualTo(NetworkSchoolLinker.acceptName));
    }
  });

  test('the framework indicators are computed and stay within bounds', () async {
    final env = await TestEnv.create(schools: 10, networks: 40);
    addTearDown(env.dispose);
    final d = await _build(env);

    expect(d.networks, 40);
    expect(d.schools.length, 40);
    expect(d.publicSchools, greaterThan(1000));

    // Headline counts are subsets of the schools that have a network.
    for (final n in [d.connected, d.lanOperational, d.meaningfullyConnected, d.activelyUsing, d.highAdoption, d.lowAdoption]) {
      expect(n, inInclusiveRange(0, d.schools.length));
    }
    expect(d.meaningfullyConnected, lessThanOrEqualTo(d.connected));
    expect(d.avgUptime, inInclusiveRange(0.0, 1.0));

    // Every school lands in exactly one quadrant.
    expect(d.quadrants.values.fold<int>(0, (a, b) => a + b), d.schools.length);

    for (final s in d.schools) {
      if (s.index != null) expect(s.index, inInclusiveRange(0.0, 100.0));
      if (s.uptimeShare != null) expect(s.uptimeShare, inInclusiveRange(0.0, 1.0));
      expect(s.apsOnline, lessThanOrEqualTo(s.apsTotal));
      expect(s.daysWithActivity, lessThanOrEqualTo(s.schoolDays));
    }
  });

  test('the index is scored only on the weight the app actually has', () async {
    final env = await TestEnv.create(schools: 10, networks: 20);
    addTearDown(env.dispose);
    final d = await _build(env);

    final scored = d.schools.firstWhere((s) => s.index != null);
    // Infrastructure, internet, Wi-Fi and regularity — 60 % of the framework.
    expect(scored.availableWeight, closeTo(0.60, 0.001));

    final missing = scored.components.where((c) => !c.isAvailable).toList();
    expect(missing.map((c) => c.label), containsAll(<String>[
      'Connectivity quality',
      'Teacher / platform adoption',
      'Student / platform adoption',
      'Digital-learning application usage',
    ]));
    for (final c in missing) {
      expect(c.missingSource, isNotNull, reason: '${c.label} must say what it needs');
    }
    expect(missing.fold<double>(0, (a, c) => a + c.weight), closeTo(0.40, 0.001));

    // The index is the weighted mean of the available components only.
    final available = scored.components.where((c) => c.isAvailable);
    final expected = available.fold<double>(0, (a, c) => a + c.weight * c.score!) / scored.availableWeight;
    expect(scored.index, closeTo(expected, 0.001));

    expect(d.missingSources, isNotEmpty);
    for (final m in d.missingSources) {
      expect(m.source, isNotEmpty);
    }
  });

  test('a school with a healthy network but no traffic asks for adoption support', () async {
    const builder = NetworkInsightsBuilder();
    List<GwnNetworkDay> days({required int clients, required int mb, int upMinutes = 470}) => [
          for (var i = 1; i <= 20; i++)
            GwnNetworkDay(
              networkId: 'n1',
              day: '2026-09-${i.toString().padLeft(2, '0')}',
              wanUpMinutes: upMinutes,
              expectedMinutes: 480,
              rxBytes: mb * 1024 * 1024,
              txBytes: 0,
              uniqueClients: clients,
              peakClients: clients,
              apsOnline: 4,
              apsTotal: 4,
              activeAps: clients == 0 ? 0 : 3,
            ),
        ];
    const devices = [
      GwnDevice(networkId: 'n1', mac: 'A', name: 'gw', kind: GwnDeviceKind.router, status: GwnDeviceStatus.online),
      GwnDevice(networkId: 'n1', mac: 'B', name: 'ap', kind: GwnDeviceKind.accessPoint, status: GwnDeviceStatus.online),
    ];

    final idle = builder.build(
      networks: const [GwnNetwork(id: 'n1', name: 'Idle School')],
      devices: devices,
      days: days(clients: 1, mb: 5),
      ssidDays: const [],
      alarms: const [],
      schoolsByCerd: const {},
      publicSchools: 1,
    );
    expect(idle.schools.single.quadrant, AdoptionQuadrant.adoptionSupport);
    expect(idle.adoptionSupport, 1);
    expect(idle.technicalIntervention, 0, reason: 'nothing is broken — this is a training problem');

    final busy = builder.build(
      networks: const [GwnNetwork(id: 'n1', name: 'Busy School')],
      devices: devices,
      days: days(clients: 60, mb: 900),
      ssidDays: const [],
      alarms: const [],
      schoolsByCerd: const {},
      publicSchools: 1,
    );
    expect(busy.schools.single.quadrant, AdoptionQuadrant.active);
    expect(busy.activelyUsing, 1);
  });

  test('a down gateway is a technical problem, not a low-adoption one', () async {
    const builder = NetworkInsightsBuilder();
    final d = builder.build(
      networks: const [GwnNetwork(id: 'n2', name: 'Broken School')],
      devices: const [
        GwnDevice(networkId: 'n2', mac: 'A', name: 'gw', kind: GwnDeviceKind.router, status: GwnDeviceStatus.offline),
        GwnDevice(networkId: 'n2', mac: 'B', name: 'ap', kind: GwnDeviceKind.accessPoint, status: GwnDeviceStatus.offline),
      ],
      days: [
        for (var i = 1; i <= 10; i++)
          GwnNetworkDay(
            networkId: 'n2',
            day: '2026-09-${i.toString().padLeft(2, '0')}',
            wanUpMinutes: 0,
            expectedMinutes: 480,
            rxBytes: 0,
            txBytes: 0,
            uniqueClients: 0,
            apsOnline: 0,
            apsTotal: 2,
            activeAps: 0,
          ),
      ],
      ssidDays: const [],
      alarms: const [
        GwnAlarm(id: 'a1', networkId: 'n2', level: GwnAlarmLevel.critical, message: 'Gateway offline', startTs: 1),
      ],
      schoolsByCerd: const {},
      publicSchools: 1,
    );

    final s = d.schools.single;
    expect(s.quadrant, AdoptionQuadrant.technical);
    expect(s.lanOperational, isFalse);
    expect(s.hasFault, isTrue);
    expect(d.technicalIntervention, 1);
    expect(d.connected, 0);
    expect(d.openCriticalIncidents, 1);
  });
}
