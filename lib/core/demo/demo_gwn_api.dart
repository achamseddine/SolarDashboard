import 'dart:math' as math;

import '../api/gwn_api.dart';
import '../api/json_utils.dart';
import '../models/gwn.dart';
import '../schools/school_dataset.dart';

/// Synthetic GWN Cloud account for demo mode and tests.
///
/// Networks are named after real schools from the bundled dataset so the
/// name-matching that links a network to a CERD is exercised, and the daily
/// counters carry a term rhythm — weekday use, quiet weekends, a handful of
/// schools with healthy infrastructure but almost no traffic, and a few with
/// a failed gateway — so every quadrant of the adoption matrix is populated.
class DemoGwnApi implements GwnApi {
  DemoGwnApi({
    int seed = 11,
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 10),
    int networks = 180,
    List<DemoSeed> seeds = const [],
  })  : _rnd = math.Random(seed),
        _clock = clock ?? DateTime.now {
    final picked = _pick(seeds, networks);
    _networks = [
      for (var i = 0; i < networks; i++)
        GwnNetwork(
          id: 'net-${1000 + i}',
          name: i < picked.length ? picked[i].name : 'Public School ${i + 1}',
          address: i < picked.length ? picked[i].region : 'Lebanon',
          timezone: 'Asia/Beirut',
        ),
    ];
    // Profiles decide how each school behaves, so the matrix has all corners.
    _profile = {
      for (var i = 0; i < _networks.length; i++)
        _networks[i].id: i % 17 == 16
            ? _Profile.gatewayDown
            : i % 11 == 10
                ? _Profile.healthyUnused
                : i % 13 == 12
                    ? _Profile.constrained
                    : _Profile.healthy,
    };
  }

  final math.Random _rnd;
  final DateTime Function() _clock;
  final Duration latency;
  late final List<GwnNetwork> _networks;
  late final Map<String, _Profile> _profile;

  List<GwnNetwork> get networks => List.unmodifiable(_networks);

  static List<DemoSeed> _pick(List<DemoSeed> seeds, int count) {
    if (seeds.isEmpty) return const [];
    final step = math.max(1, seeds.length ~/ count);
    final out = <DemoSeed>[];
    for (var i = 0; i < seeds.length && out.length < count; i += step) {
      out.add(seeds[i]);
    }
    return out;
  }

  Future<T> _delay<T>(T value) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return value;
  }

  @override
  Future<void> authenticate() async => _delay(null);

  @override
  void close() {}

  @override
  Future<List<GwnNetwork>> listNetworks() => _delay(_networks);

  @override
  Future<List<GwnDevice>> listDevices(String networkId) {
    final p = _profile[networkId] ?? _Profile.healthy;
    final r = math.Random(networkId.hashCode);
    final apCount = 3 + r.nextInt(8);
    final switchCount = 1 + r.nextInt(2);
    final gatewayUp = p != _Profile.gatewayDown;
    final firmware = r.nextInt(10) == 0 ? '1.0.23.9' : '1.0.25.14';

    GwnDevice ap(int i) {
      // A constrained school has radios that keep dropping out.
      final up = gatewayUp && (p == _Profile.constrained ? r.nextInt(3) > 0 : r.nextInt(20) > 0);
      return GwnDevice(
        networkId: networkId,
        mac: _mac(networkId, 'ap$i'),
        name: 'AP ${i + 1}',
        kind: GwnDeviceKind.accessPoint,
        status: up ? GwnDeviceStatus.online : GwnDeviceStatus.offline,
        model: 'GWN7660',
        firmware: firmware,
        ip: '192.168.${10 + i}.${20 + i}',
        uptimeSeconds: up ? 3600 * (24 + r.nextInt(600)) : 0,
        clientCount: up ? r.nextInt(30) : 0,
        cpuPercent: up ? 5 + r.nextDouble() * 40 : null,
        memoryPercent: up ? 30 + r.nextDouble() * 40 : null,
        lastSeenTs: _clock().millisecondsSinceEpoch ~/ 1000 - (up ? 120 : 86400),
      );
    }

    GwnDevice sw(int i) {
      final ports = 24;
      final poeUsed = math.min(ports, apCount);
      final failed = p == _Profile.constrained && r.nextInt(2) == 0 ? 1 : 0;
      return GwnDevice(
        networkId: networkId,
        mac: _mac(networkId, 'sw$i'),
        name: 'Switch ${i + 1}',
        kind: GwnDeviceKind.networkSwitch,
        status: gatewayUp ? GwnDeviceStatus.online : GwnDeviceStatus.offline,
        model: 'GWN7803P',
        firmware: firmware,
        uptimeSeconds: gatewayUp ? 3600 * (100 + r.nextInt(900)) : 0,
        cpuPercent: gatewayUp ? 8 + r.nextDouble() * 25 : null,
        memoryPercent: gatewayUp ? 40 + r.nextDouble() * 30 : null,
        poePortsTotal: ports,
        poePortsActive: gatewayUp ? poeUsed - failed : 0,
        poePortsFailed: failed,
        portsUp: gatewayUp ? poeUsed + 1 : 0,
        portsDown: ports - poeUsed - 1,
        portsError: p == _Profile.constrained ? r.nextInt(2) : 0,
        lastSeenTs: _clock().millisecondsSinceEpoch ~/ 1000 - 180,
      );
    }

    return _delay([
      GwnDevice(
        networkId: networkId,
        mac: _mac(networkId, 'gw'),
        name: 'Gateway',
        kind: GwnDeviceKind.router,
        status: gatewayUp ? GwnDeviceStatus.online : GwnDeviceStatus.offline,
        model: 'GWN7062',
        firmware: firmware,
        ip: '192.168.1.1',
        uptimeSeconds: gatewayUp ? 3600 * (50 + r.nextInt(1200)) : 0,
        lastSeenTs: _clock().millisecondsSinceEpoch ~/ 1000 - (gatewayUp ? 60 : 172800),
      ),
      for (var i = 0; i < switchCount; i++) sw(i),
      for (var i = 0; i < apCount; i++) ap(i),
    ]);
  }

  @override
  Future<List<GwnNetworkDay>> networkDaily(String networkId, String fromDay, String toDay) {
    final p = _profile[networkId] ?? _Profile.healthy;
    final r = math.Random(networkId.hashCode ^ 0x5eed);
    final apCount = 3 + math.Random(networkId.hashCode).nextInt(8);
    final out = <GwnNetworkDay>[];
    for (final day in _days(fromDay, toDay)) {
      final d = DateTime.parse(day);
      final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      final expected = weekend ? 0 : 480; // an eight-hour school day

      // Uptime: healthy schools sit near the target, a down gateway at zero.
      final up = switch (p) {
        _Profile.gatewayDown => 0,
        _Profile.constrained => (expected * (0.55 + r.nextDouble() * 0.3)).round(),
        _ => (expected * (0.93 + r.nextDouble() * 0.07)).round(),
      };

      final base = switch (p) {
        _Profile.healthyUnused => 2 + r.nextInt(4),
        _Profile.gatewayDown => 0,
        _Profile.constrained => 12 + r.nextInt(20),
        _ => 25 + r.nextInt(70),
      };
      final clients = weekend ? (base * 0.08).round() : base;
      final mbPerClient = p == _Profile.healthyUnused ? 3 : 25 + r.nextInt(40);
      final bytes = clients * mbPerClient * 1024 * 1024;
      final activeAps = clients == 0 ? 0 : math.min(apCount, 1 + (clients / 12).floor());

      out.add(GwnNetworkDay(
        networkId: networkId,
        day: day,
        wanUpMinutes: up,
        expectedMinutes: expected,
        rxBytes: (bytes * 0.8).round(),
        txBytes: (bytes * 0.2).round(),
        uniqueClients: clients,
        peakClients: (clients * 0.7).round(),
        apsOnline: p == _Profile.gatewayDown ? 0 : apCount,
        apsTotal: apCount,
        activeAps: activeAps,
        teachingHoursBytes: (bytes * (weekend ? 0.1 : 0.72)).round(),
      ));
    }
    return _delay(out);
  }

  @override
  Future<List<GwnSsidDay>> ssidDaily(String networkId, String fromDay, String toDay) async {
    final days = await networkDaily(networkId, fromDay, toDay);
    const split = {'School-Staff': 0.34, 'School-Students': 0.56, 'School-Admin': 0.10};
    return [
      for (final d in days)
        for (final e in split.entries)
          GwnSsidDay(
            networkId: networkId,
            day: d.day,
            ssid: e.key,
            bytes: ((d.totalBytes ?? 0) * e.value).round(),
            clients: ((d.uniqueClients ?? 0) * e.value).round(),
          ),
    ];
  }

  @override
  Future<List<GwnAlarm>> listAlarms({String? networkId, int? sinceTs}) {
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    final out = <GwnAlarm>[];
    for (final n in _networks) {
      if (networkId != null && n.id != networkId) continue;
      final p = _profile[n.id] ?? _Profile.healthy;
      if (p == _Profile.gatewayDown) {
        out.add(GwnAlarm(
          id: '${n.id}-gw',
          networkId: n.id,
          level: GwnAlarmLevel.critical,
          message: 'Gateway offline — WAN unreachable',
          startTs: now - 3600 * (6 + _rnd.nextInt(60)),
          deviceMac: _mac(n.id, 'gw'),
        ));
      }
      if (p == _Profile.constrained) {
        out.add(GwnAlarm(
          id: '${n.id}-ap',
          networkId: n.id,
          level: GwnAlarmLevel.major,
          message: 'Access point flapping — repeated disconnects',
          startTs: now - 3600 * (2 + _rnd.nextInt(30)),
          deviceMac: _mac(n.id, 'ap0'),
        ));
      }
    }
    return _delay(out);
  }

  static String _mac(String networkId, String role) {
    final h = (networkId.hashCode ^ role.hashCode).abs();
    final b = [for (var i = 0; i < 5; i++) (h >> (i * 5)) & 0xFF];
    return ['00', ...b.map((x) => x.toRadixString(16).padLeft(2, '0'))].join(':').toUpperCase();
  }

  static List<String> _days(String fromDay, String toDay) {
    final a = DateTime.parse(fromDay), b = DateTime.parse(toDay);
    final out = <String>[];
    for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) {
      out.add(ymd(d));
    }
    return out;
  }
}

enum _Profile { healthy, healthyUnused, constrained, gatewayDown }
