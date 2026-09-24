import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/network_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';
import 'package:unicef_solar_monitor/core/models/network_insights.dart';

const _devices = [
  GwnDevice(networkId: 'n1', mac: 'A', name: 'gw', kind: GwnDeviceKind.router, status: GwnDeviceStatus.online),
  GwnDevice(networkId: 'n1', mac: 'B', name: 'ap', kind: GwnDeviceKind.accessPoint, status: GwnDeviceStatus.online),
];

NetworkInsights _build(List<GwnNetworkDay> days) => const NetworkInsightsBuilder().build(
      networks: const [GwnNetwork(id: 'n1', name: 'A School')],
      devices: _devices,
      days: days,
      ssidDays: const [],
      alarms: const [],
      schoolsByCerd: const {},
      publicSchools: 1,
    );

void main() {
  test('a school with no usage measured is not called low adoption', () {
    // One observation: the network was up, but nothing about use was seen.
    final d = _build([
      const GwnNetworkDay(networkId: 'n1', day: '2026-09-24', observations: 1, onlineObservations: 1),
    ]);

    final s = d.schools.single;
    expect(s.seenOnline, isTrue);
    expect(s.hasUsageEvidence, isFalse);
    expect(d.connected, 1, reason: 'it was seen online');
    expect(d.lowAdoption, 0, reason: 'nothing was measured — that is not low adoption');
    expect(d.highAdoption, 0);
    expect(s.quadrant, AdoptionQuadrant.unknown, reason: 'the usage axis has no reading');
  });

  test('one observation does not make a school meaningfully connected', () {
    final d = _build([
      const GwnNetworkDay(networkId: 'n1', day: '2026-09-24', observations: 1, onlineObservations: 1),
    ]);
    expect(d.meaningfullyConnected, 0);
    expect(d.avgUptime, isNull);
  });

  test('once use is measured, a quiet school does count as low adoption', () {
    final days = [
      for (var i = 1; i <= 10; i++)
        GwnNetworkDay(
          networkId: 'n1',
          day: '2026-09-${i.toString().padLeft(2, '0')}',
          observations: 8,
          onlineObservations: 8,
          uniqueClients: 1,
          peakClients: 1,
          rxBytes: 1024 * 1024,
          txBytes: 0,
          apsOnline: 1,
          apsTotal: 1,
          activeAps: 1,
        ),
    ];
    final d = _build(days);
    final s = d.schools.single;
    expect(s.hasUsageEvidence, isTrue);
    expect(d.meaningfullyConnected, 1, reason: 'eight checks a day over ten days is a real uptime');
    expect(s.quadrant, AdoptionQuadrant.adoptionSupport);
    // The composite index stays high here — infrastructure and internet are
    // perfect and carry half the available weight — so the adoption headline
    // has to read the usage score instead.
    expect(s.index, greaterThan(50));
    expect(s.usageScore, lessThan(40));
    expect(d.lowAdoption, 1, reason: 'healthy network, almost no use');
    expect(d.highAdoption, 0);
  });
}
