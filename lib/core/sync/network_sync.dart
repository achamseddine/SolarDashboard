import '../api/gwn_api.dart';
import '../api/gwn_api_client.dart';
import '../api/json_utils.dart';
import '../db/app_database.dart';
import '../models/gwn.dart';
import '../schools/network_school_linker.dart';

/// What one GWN synchronisation did, for the status strip and Settings.
class NetworkSyncReport {
  const NetworkSyncReport({
    required this.networks,
    required this.devices,
    required this.dailyRows,
    required this.alarms,
    required this.linked,
    required this.failures,
    required this.finishedTs,
    this.message,
    this.endpointNotes = const {},
  });

  final int networks;
  final int devices;
  final int dailyRows;
  final int alarms;
  final int linked;

  /// Networks whose detail calls failed — their indicators keep the values
  /// from the previous run rather than being reset to zero.
  final int failures;
  final int finishedTs;
  final String? message;

  /// What each part of the pull actually did, including the reason a call
  /// returned nothing. Without this an endpoint the account does not expose
  /// looks identical to a school with no activity.
  final Map<String, String> endpointNotes;

  bool get isEmpty => networks == 0;
}

/// Pulls the GWN Cloud account into SQLite: the networks, their devices, the
/// daily counters over the reporting window, per-SSID traffic and alarms, and
/// then links each network to a school by name.
class NetworkSync {
  NetworkSync({
    required this.api,
    required this.db,
    this.windowDays = 30,
    this.source = 'live',
    DateTime Function()? clock,
    this.log,
  }) : _clock = clock ?? DateTime.now;

  final GwnApi api;
  final AppDatabase db;
  final int windowDays;

  /// Which account these rows came from: 'live' for a configured GWN
  /// account, 'demo' for the synthetic sample. Stored so switching sources
  /// clears the previous rows instead of mixing two fleets.
  final String source;
  final DateTime Function() _clock;
  final void Function(String message)? log;

  /// Fills a network's client and access-point counts from its own devices
  /// when the network payload did not carry them.
  ///
  /// The access points are fetched anyway and each reports its own clients,
  /// so their sum is the network's — a better source than a field name
  /// guessed at on an API with no published schema.
  static GwnNetworkDay _withDeviceCounts(GwnNetworkDay day, List<GwnDevice> devices) {
    if (devices.isEmpty) return day;
    final aps = devices.where((d) => d.kind == GwnDeviceKind.accessPoint).toList();
    final counted = aps.map((d) => d.clientCount).whereType<int>().toList();
    final clients = counted.isEmpty ? null : counted.fold<int>(0, (a, b) => a + b);

    return GwnNetworkDay(
      networkId: day.networkId,
      day: day.day,
      wanUpMinutes: day.wanUpMinutes,
      expectedMinutes: day.expectedMinutes,
      rxBytes: day.rxBytes,
      txBytes: day.txBytes,
      uniqueClients: day.uniqueClients ?? clients,
      peakClients: day.peakClients ?? clients,
      apsOnline: day.apsOnline ?? (aps.isEmpty ? null : aps.where((d) => d.isOnline).length),
      apsTotal: day.apsTotal ?? (aps.isEmpty ? null : aps.length),
      activeAps: day.activeAps ?? (counted.isEmpty ? null : aps.where((d) => (d.clientCount ?? 0) > 0).length),
      teachingHoursBytes: day.teachingHoursBytes,
      observations: day.observations,
      onlineObservations: day.onlineObservations,
    );
  }

  /// One line naming whatever came back empty, so the dashboards' zeros can
  /// be told apart from endpoints this account does not answer.
  static String? _summarise(Map<String, String> notes, int networks, int devices, int daily, int ssid) {
    final empty = <String>[
      if (devices == 0) 'devices',
      if (daily == 0) 'daily counters',
      if (ssid == 0) 'per-SSID traffic',
    ];
    // Field names the account returned. Names only, no values — it is the
    // one thing the parsing has to be matched against, and it is far easier
    // to read here than behind a separate diagnostic.
    final fields = notes.entries.where((e) => e.key.startsWith('fields:')).map((e) => '${e.key.substring(7)}: ${e.value}');
    final parts = <String>[
      if (empty.isNotEmpty) 'nothing came back for: ${empty.map((k) => '$k (${notes[k] ?? 'not called'})').join('; ')}',
      if (fields.isNotEmpty) 'fields returned — ${fields.join(' | ')}',
    ];
    if (parts.isEmpty) return null;
    return '$networks networks synced · ${parts.join(' · ')}';
  }

  /// Retention: daily rows older than this many days are dropped.
  static const int keepDays = 120;

  /// sync_meta key recording which source filled the GWN tables.
  static const String sourceKey = 'gwn.source';

  Future<NetworkSyncReport> run() async {
    final now = _clock();
    final toDay = ymd(now);
    final fromDay = ymd(now.subtract(Duration(days: windowDays - 1)));

    // Sample rows and a real account must never mix: changing source wipes
    // what the previous one wrote.
    final previous = await db.sync.metaGet(sourceKey);
    if (previous != null && previous != source) {
      for (final t in ['gwn_networks', 'gwn_devices', 'gwn_network_daily', 'gwn_ssid_daily', 'gwn_alarms']) {
        await db.db.delete(t);
      }
      log?.call('GWN: source changed from $previous to $source — cleared the previous rows');
    }
    await db.sync.metaSet(sourceKey, source);

    await api.authenticate();
    final networks = await api.listNetworks();
    await db.networks.upsertNetworks(networks);

    var devices = 0, dailyRows = 0, ssidRows = 0, failures = 0;
    final notes = <String, String>{};

    // Each call is recorded separately: one endpoint the account does not
    // expose must not look like every school being idle.
    Future<int> part(String name, GwnNetwork n, Future<int> Function() run) async {
      try {
        final count = await run();
        if (count > 0) notes[name] = 'ok';
        notes.putIfAbsent(name, () => 'answered, but returned no rows');
        return count;
      } catch (e) {
        notes[name] = '$e';
        log?.call('GWN: $name for network ${n.id} failed: $e');
        return -1;
      }
    }

    for (final n in networks) {
      var failed = false;

      final d = await part('devices', n, () async {
        final list = await api.listDevices(n.id);
        await db.networks.upsertDevices(list);
        await db.networks.pruneDevices(n.id, {for (final x in list) x.mac});
        return list.length;
      });
      if (d < 0) {
        failed = true;
      } else {
        devices += d;
      }

      final day = await part('daily counters', n, () async {
        final list = await api.networkDaily(n.id, fromDay, toDay);
        if (list.isEmpty) return 0;
        // One row for today is a live observation to fold into the day; a
        // real series (demo, or a cloud that does expose history) is stored
        // as given.
        if (list.length == 1 && list.single.day == toDay) {
          final devices = await db.networks.getDevices(networkId: n.id);
          final up = devices.isEmpty
              ? (list.single.apsOnline ?? 0) > 0
              : devices.any((x) => x.isOnline);
          await db.networks.recordObservation(_withDeviceCounts(list.single, devices), online: up);
        } else {
          await db.networks.upsertDaily(list);
        }
        return list.length;
      });
      if (day < 0) {
        failed = true;
      } else {
        dailyRows += day;
      }

      final ssid = await part('per-SSID traffic', n, () async {
        final list = await api.ssidDaily(n.id, fromDay, toDay);
        // SSIDs without traffic figures are names only — not worth a row.
        final withTraffic = list.where((x) => (x.bytes ?? 0) > 0).toList();
        await db.networks.upsertSsidDaily(withTraffic);
        return withTraffic.length;
      });
      if (ssid < 0) {
        failed = true;
      } else {
        ssidRows += ssid;
      }

      if (failed) failures++;
    }

    var alarms = <GwnAlarm>[];
    try {
      alarms = await api.listAlarms();
      await db.networks.upsertAlarms(alarms);
      notes['alarms'] = alarms.isEmpty ? 'answered, but returned no rows' : 'ok';
    } catch (e) {
      notes['alarms'] = '$e';
      log?.call('GWN: alarm list failed: $e');
    }

    // Link by name against the MEHE master list.
    final schools = await db.schools.getSchools();
    final linked = await NetworkSchoolLinker(schools).linkAll(db);

    await db.networks.prune(
      beforeDay: ymd(now.subtract(const Duration(days: keepDays))),
      beforeTs: now.subtract(const Duration(days: keepDays)).millisecondsSinceEpoch ~/ 1000,
    );
    db.notifyChanged();

    final client = api;
    if (client is GwnApiClient) {
      client.fieldsSeen.forEach((k, v) => notes['fields:$k'] = v.join(', '));
    }
    return NetworkSyncReport(
      networks: networks.length,
      devices: devices,
      dailyRows: dailyRows,
      alarms: alarms.length,
      linked: linked,
      failures: failures,
      finishedTs: now.millisecondsSinceEpoch ~/ 1000,
      message: _summarise(notes, networks.length, devices, dailyRows, ssidRows),
      endpointNotes: notes,
    );
  }
}
