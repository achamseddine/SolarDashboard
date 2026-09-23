import '../api/gwn_api.dart';
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

    var devices = 0, dailyRows = 0, failures = 0;
    for (final n in networks) {
      try {
        final list = await api.listDevices(n.id);
        await db.networks.upsertDevices(list);
        await db.networks.pruneDevices(n.id, {for (final d in list) d.mac});
        devices += list.length;

        final daily = await api.networkDaily(n.id, fromDay, toDay);
        await db.networks.upsertDaily(daily);
        dailyRows += daily.length;

        final ssid = await api.ssidDaily(n.id, fromDay, toDay);
        await db.networks.upsertSsidDaily(ssid);
      } catch (e) {
        failures++;
        log?.call('GWN: network ${n.id} failed: $e');
      }
    }

    var alarms = <GwnAlarm>[];
    try {
      alarms = await api.listAlarms();
      await db.networks.upsertAlarms(alarms);
    } catch (e) {
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

    return NetworkSyncReport(
      networks: networks.length,
      devices: devices,
      dailyRows: dailyRows,
      alarms: alarms.length,
      linked: linked,
      failures: failures,
      finishedTs: now.millisecondsSinceEpoch ~/ 1000,
      message: failures == 0 ? null : '$failures of ${networks.length} networks did not return detail this run',
    );
  }
}
