import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/network_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';
import 'package:unicef_solar_monitor/core/models/network_insights.dart';

/// The live account exposes access points only — no gateway or switch is
/// listed for any network — so the indicators have to work without one.
List<GwnDevice> _aps({required int total, required int online}) => [
      for (var i = 0; i < total; i++)
        GwnDevice(
          networkId: 'n1',
          mac: 'AP$i',
          name: 'AP $i',
          kind: GwnDeviceKind.accessPoint,
          status: i < online ? GwnDeviceStatus.online : GwnDeviceStatus.offline,
        ),
    ];

NetworkInsights _build(List<GwnDevice> devices, List<GwnNetworkDay> days) =>
    const NetworkInsightsBuilder().build(
      networks: const [GwnNetwork(id: 'n1', name: 'A School')],
      devices: devices,
      days: days,
      ssidDays: const [],
      alarms: const [],
      schoolsByCerd: const {},
      publicSchools: 1,
    );

const _oneLook = GwnNetworkDay(networkId: 'n1', day: '2026-09-24', observations: 1, onlineObservations: 1);

void main() {
  test('an account with no gateway still reports a working LAN', () {
    final d = _build(_aps(total: 4, online: 4), const [_oneLook]);
    final s = d.schools.single;

    expect(s.gatewayOnline, isNull, reason: 'no gateway is listed at all');
    expect(s.lanOperational, isTrue, reason: 'the access points are up');
    expect(d.lanOperational, 1);
    expect(s.hasFault, isFalse);
  });

  test('most access points down is a technical fault', () {
    final d = _build(_aps(total: 10, online: 3), const [_oneLook]);
    final s = d.schools.single;

    expect(s.apsMostlyDown, isTrue);
    expect(s.lanOperational, isFalse);
    expect(s.hasFault, isTrue);
    expect(d.technicalIntervention, 1, reason: 'seven of ten radios down needs a technician');
  });

  test('a component with no score says why, never "null"', () {
    final d = _build(_aps(total: 4, online: 4), const [_oneLook]);
    final s = d.schools.single;

    for (final c in s.components.where((c) => !c.isAvailable)) {
      expect(c.missingSource, isNotNull, reason: '${c.label} must explain itself');
      expect(c.missingSource, isNotEmpty);
      expect(c.missingSource, isNot(contains('null')));
    }

    // Usage was never measured, so neither usage component is scored.
    expect(s.scoreOf('Wi-Fi utilisation'), isNull);
    expect(s.scoreOf('Regularity of usage'), isNull, reason: 'zero would read as "nobody used it"');
    expect(s.scoreOf('Infrastructure availability'), 100);
  });

  test('regularity counts measured days, not every day looked at', () {
    // Ten days observed; only two carried a client count, both of them busy.
    final days = [
      for (var i = 1; i <= 10; i++)
        GwnNetworkDay(
          networkId: 'n1',
          day: '2026-09-${i.toString().padLeft(2, '0')}',
          observations: 6,
          onlineObservations: 6,
          uniqueClients: i <= 2 ? 40 : null,
          rxBytes: i <= 2 ? 900 * 1024 * 1024 : null,
          apsOnline: 4,
          apsTotal: 4,
          activeAps: i <= 2 ? 4 : null,
        ),
    ];
    final s = _build(_aps(total: 4, online: 4), days).schools.single;
    expect(s.scoreOf('Regularity of usage'), 100, reason: 'both measured days were active');
  });

  test('the usage page falls back to access points when clients are absent', () {
    // Two days of observations with AP counts but no client figure — what
    // this account actually returns.
    final days = [
      for (var i = 1; i <= 2; i++)
        GwnNetworkDay(
          networkId: 'n1',
          day: '2026-09-2$i',
          observations: 5,
          onlineObservations: 5,
          apsOnline: 3,
          apsTotal: 4,
        ),
    ];
    final d = _build(_aps(total: 4, online: 3), days);

    expect(d.dailyClients.every((x) => x.clients == 0), isTrue, reason: 'no client counts came back');
    expect(d.dailyApsOnline.length, 2, reason: 'the access points are still a real series');
    expect(d.dailyApsOnline.every((x) => x.aps == 3), isTrue);

    // …and it is still not treated as evidence about use.
    expect(d.schools.single.hasUsageEvidence, isFalse);
    expect(d.lowAdoption, 0);
  });
}