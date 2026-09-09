import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/deye_api.dart';
import 'api/deye_api_client.dart';
import 'db/app_database.dart';
import 'demo/demo_deye_api.dart';
import 'insights/fleet_insights_builder.dart';
import 'models/alert.dart';
import 'models/credentials.dart';
import 'models/device.dart';
import 'models/fleet_insights.dart';
import 'models/station.dart';
import 'models/sync.dart';
import 'settings/app_settings.dart';
import 'settings/credential_store.dart';
import 'sync/rate_limiter.dart';
import 'sync/station_region.dart';
import 'sync/sync_engine.dart';
import 'utils/app_time.dart';

// --------------------------------------------------------------- bootstrap
// These are overridden in main() with the objects created during start-up.

final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider must be overridden'));
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'));
final credentialStoreProvider = Provider<CredentialStore>((ref) => CredentialStore());
final boundariesProvider = Provider<LebanonBoundaries?>((ref) => null);
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());
final initialCredentialsProvider = Provider<DeyeCredentials?>((ref) => null);

/// Log lines from the sync engine / API (shown in Settings → diagnostics).
final appLogProvider = NotifierProvider<AppLog, List<String>>(AppLog.new);

class AppLog extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void add(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    final next = [...state, '$stamp  $line'];
    state = next.length > 300 ? next.sublist(next.length - 300) : next;
  }

  void clear() => state = const [];
}

// ---------------------------------------------------------------- settings

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(sharedPrefsProvider));
  }
}

// ------------------------------------------------------------- credentials

final credentialsProvider = NotifierProvider<CredentialsNotifier, DeyeCredentials?>(CredentialsNotifier.new);

class CredentialsNotifier extends Notifier<DeyeCredentials?> {
  @override
  DeyeCredentials? build() => ref.read(initialCredentialsProvider);

  Future<void> save(DeyeCredentials c) async {
    await ref.read(credentialStoreProvider).save(c);
    state = c;
  }

  Future<void> clear() async {
    await ref.read(credentialStoreProvider).deleteAll();
    state = null;
  }
}

/// True when the app can talk to a data source (real credentials or demo).
final canSyncProvider = Provider<bool>((ref) {
  final demo = ref.watch(settingsProvider.select((s) => s.demoMode));
  final creds = ref.watch(credentialsProvider);
  return demo || (creds?.isComplete ?? false);
});

// ---------------------------------------------------------------------- api

/// The data source. Only rebuilt when credentials or the settings that
/// affect the client change (demo mode, concurrency, alert path overrides).
final apiProvider = Provider<DeyeApi>((ref) {
  final demo = ref.watch(settingsProvider.select((s) => s.demoMode));
  final concurrency = ref.watch(settingsProvider.select((s) => s.maxConcurrentRequests));
  final alertStationPath = ref.watch(settingsProvider.select((s) => s.alertStationPath));
  final alertDevicePath = ref.watch(settingsProvider.select((s) => s.alertDevicePath));
  final creds = ref.watch(credentialsProvider);
  final log = ref.read(appLogProvider.notifier);
  if (demo || creds == null || !creds.isComplete) {
    return DemoDeyeApi();
  }
  return DeyeApiClient(
    credentials: creds,
    tokenCache: ref.read(credentialStoreProvider),
    limiter: RateLimiter(maxConcurrent: concurrency),
    alertConfig: AlertEndpointConfig(stationPath: alertStationPath, devicePath: alertDevicePath),
    log: log.add,
  );
});

// --------------------------------------------------------------------- sync

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: ref.read(databaseProvider),
    apiProvider: () => ref.read(apiProvider),
    settingsProvider: () => ref.read(settingsProvider),
    boundaries: ref.read(boundariesProvider),
    log: (m) => ref.read(appLogProvider.notifier).add(m),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final ctl = StreamController<SyncStatus>();
  ctl.add(engine.status);
  final sub = engine.statusStream.listen(ctl.add);
  ref.onDispose(() {
    sub.cancel();
    ctl.close();
  });
  return ctl.stream;
});

/// Increments whenever the database reports a change of one of [kinds]
/// (or any change when `DataKind.all` is requested). Watch it to re-query.
final dataVersionProvider = NotifierProvider.family<DataVersion, int, DataKind>(DataVersion.new);

class DataVersion extends Notifier<int> {
  DataVersion(this.kind);
  final DataKind kind;

  @override
  int build() {
    final db = ref.read(databaseProvider);
    final sub = db.changes.listen((kinds) {
      if (kind == DataKind.all || kinds.contains(DataKind.all) || kinds.contains(kind)) state++;
    });
    ref.onDispose(sub.cancel);
    return 0;
  }
}

// ----------------------------------------------------------------- queries

final fleetInsightsProvider = FutureProvider<FleetInsights>((ref) async {
  ref.watch(dataVersionProvider(DataKind.all));
  final settings = ref.watch(settingsProvider);
  return FleetInsightsBuilder(ref.read(databaseProvider)).build(settings);
});

/// Everything the station detail screen shows.
class StationDetail {
  const StationDetail({
    required this.station,
    this.latest,
    required this.devices,
    required this.deviceLatest,
    required this.todayFrames,
    required this.yesterdayFrames,
    required this.daily,
    required this.monthly,
    required this.alerts,
    required this.batteryDays,
    required this.statusEvents,
    this.insight,
  });

  final Station station;
  final StationLatest? latest;
  final List<Device> devices;
  final Map<String, DeviceLatest> deviceLatest;
  final List<StationSnapshot> todayFrames;
  final List<StationSnapshot> yesterdayFrames;
  final List<StationEnergy> daily;
  final List<StationEnergy> monthly;
  final List<SolarAlert> alerts;
  final List<BatteryDay> batteryDays;
  final List<StatusEvent> statusEvents;
  final StationInsight? insight;
}

final stationDetailProvider = FutureProvider.autoDispose.family<StationDetail?, int>((ref, stationId) async {
  ref.watch(dataVersionProvider(DataKind.all));
  final db = ref.read(databaseProvider);
  final station = await db.stations.getStation(stationId);
  if (station == null) return null;
  final loc = station.location;
  final today = AppTime.today(loc);
  final yesterday = AppTime.addDays(today, -1);
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final insights = await ref.watch(fleetInsightsProvider.future);
  final devices = await db.devices.devicesForStation(stationId);
  final latestDevices = await db.devices.latestForStation(stationId);
  return StationDetail(
    station: station,
    latest: await db.stations.getLatest(stationId),
    devices: devices,
    deviceLatest: {for (final l in latestDevices) l.deviceSn: l},
    todayFrames: await db.stations.snapshotsBetween(stationId, AppTime.dayStart(today, loc), AppTime.dayEnd(today, loc)),
    yesterdayFrames: await db.stations.snapshotsBetween(stationId, AppTime.dayStart(yesterday, loc), AppTime.dayEnd(yesterday, loc)),
    daily: await db.stations.dailyBetween(stationId, AppTime.addDays(today, -30), today),
    monthly: await db.stations.monthlyBetween(stationId, AppTime.addMonths(today.substring(0, 7), -11), today.substring(0, 7)),
    alerts: await db.alerts.alertsForStation(stationId),
    batteryDays: await db.stations.batteryDaysBetween(stationId, AppTime.addDays(today, -30), today),
    statusEvents: await db.stations.statusEventsBetween(nowTs - 30 * 86400, nowTs, stationId: stationId),
    insight: insights.stations.where((s) => s.id == stationId).firstOrNull,
  );
});

/// Filter for the alarm centre.
class AlertFilter {
  const AlertFilter({this.status, this.level, this.source, this.stationId, this.search, this.unacknowledgedOnly = false, this.sinceDays});

  final AlertStatus? status;
  final AlertLevel? level;
  final AlertSource? source;
  final int? stationId;
  final String? search;
  final bool unacknowledgedOnly;
  final int? sinceDays;

  AlertFilter copyWith({
    AlertStatus? status,
    bool clearStatus = false,
    AlertLevel? level,
    bool clearLevel = false,
    AlertSource? source,
    bool clearSource = false,
    int? stationId,
    bool clearStation = false,
    String? search,
    bool? unacknowledgedOnly,
    int? sinceDays,
    bool clearSince = false,
  }) =>
      AlertFilter(
        status: clearStatus ? null : (status ?? this.status),
        level: clearLevel ? null : (level ?? this.level),
        source: clearSource ? null : (source ?? this.source),
        stationId: clearStation ? null : (stationId ?? this.stationId),
        search: search ?? this.search,
        unacknowledgedOnly: unacknowledgedOnly ?? this.unacknowledgedOnly,
        sinceDays: clearSince ? null : (sinceDays ?? this.sinceDays),
      );

  @override
  bool operator ==(Object other) =>
      other is AlertFilter &&
      other.status == status &&
      other.level == level &&
      other.source == source &&
      other.stationId == stationId &&
      other.search == search &&
      other.unacknowledgedOnly == unacknowledgedOnly &&
      other.sinceDays == sinceDays;

  @override
  int get hashCode => Object.hash(status, level, source, stationId, search, unacknowledgedOnly, sinceDays);
}

final alertsProvider = FutureProvider.autoDispose.family<List<SolarAlert>, AlertFilter>((ref, f) async {
  ref.watch(dataVersionProvider(DataKind.alerts));
  final db = ref.read(databaseProvider);
  return db.alerts.alerts(
    status: f.status,
    level: f.level,
    source: f.source,
    stationId: f.stationId,
    search: f.search,
    unacknowledgedOnly: f.unacknowledgedOnly,
    sinceTs: f.sinceDays == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 - f.sinceDays! * 86400,
  );
});

final syncLogsProvider = FutureProvider.autoDispose<List<SyncLogEntry>>((ref) async {
  ref.watch(dataVersionProvider(DataKind.all));
  ref.watch(syncStatusProvider);
  return ref.read(databaseProvider).sync.recentLogs(limit: 60);
});

final dbStatsProvider = FutureProvider.autoDispose<(Map<String, int>, int)>((ref) async {
  ref.watch(dataVersionProvider(DataKind.all));
  final db = ref.read(databaseProvider);
  return (await db.tableCounts(), await db.sizeBytes());
});

/// Fleet or region 15-minute power buckets for the last [hours].
final powerBucketsProvider = FutureProvider.autoDispose.family<List<PowerBucket>, (String, int)>((ref, arg) async {
  ref.watch(dataVersionProvider(DataKind.buckets));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return ref.read(databaseProvider).stations.bucketsBetween(now - arg.$2 * 3600, now, region: arg.$1);
});
