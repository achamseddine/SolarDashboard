import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unicef_solar_monitor/core/db/app_database.dart';
import 'package:unicef_solar_monitor/core/demo/demo_deye_api.dart';
import 'package:unicef_solar_monitor/core/insights/fleet_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/station.dart';
import 'package:unicef_solar_monitor/core/settings/app_settings.dart';
import 'package:unicef_solar_monitor/core/sync/sync_engine.dart';
import 'package:unicef_solar_monitor/core/utils/app_time.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    AppTime.ensureInitialised();
  });

  test('full sweep against the demo API populates every table and insights build', () async {
    final db = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    final api = DemoDeyeApi(latency: Duration.zero, schools: 30);
    final settings = const AppSettings(demoMode: true, maxConcurrentRequests: 8);
    final logs = <String>[];
    final engine = SyncEngine(db: db, apiProvider: () => api, settingsProvider: () => settings, log: logs.add);
    await engine.loadMeta();
    await engine.syncNow();

    final counts = await db.tableCounts();
    expect(counts['stations'], 30);
    expect(counts['devices'], greaterThan(60));
    expect(counts['station_latest'], 30);
    expect(counts['device_latest'], greaterThan(30));
    expect(counts['device_samples'], greaterThan(30));
    expect(counts['station_snapshots'], greaterThan(30));
    expect(counts['station_daily'], greaterThan(30 * 20));
    expect(counts['station_monthly'], greaterThan(0));
    expect(counts['station_status_events'], 30);
    expect(counts['alerts'], greaterThan(0));
    expect(counts['sync_log'], greaterThan(5));
    expect(engine.status.lastError, isNull, reason: logs.join('\n'));
    final phases = await db.sync.recentLogs(limit: 100);
    expect(phases.where((p) => p.ok != true).map((p) => '${p.kind}: ${p.message}'), isEmpty, reason: 'every phase must succeed');

    final stations = await db.stations.getStations();
    expect(stations.where((s) => s.region != null).length, 30, reason: 'every demo school resolves a governorate');
    expect(stations.map((s) => s.status).toSet(), containsAll([StationStatus.online]));
    expect(stations.any((s) => s.status == StationStatus.offline || s.status == StationStatus.stale), isTrue);

    // The device/station snapshot must not be hidden by the list snapshot at the same timestamp.
    final latestSnaps = await db.stations.allLatest();
    final first = latestSnaps.values.firstWhere((l) => l.snapshot?.consumptionW != null);
    final stored = await db.stations.latestSnapshot(first.stationId);
    expect(stored?.consumptionW, isNotNull, reason: 'snapshot row keeps consumption');
    final buckets = await db.stations.bucketsBetween(0, 1 << 40);
    expect(buckets.where((b) => b.region.isEmpty).any((b) => b.consumptionW > 1000), isTrue, reason: 'fleet bucket sums consumption over all plants');

    final insights = await FleetInsightsBuilder(db).build(settings);
    expect(insights.totalStations, 30);
    expect(insights.reportingStations, greaterThan(20));
    expect(insights.regions.length, greaterThan(3));
    expect(insights.last30d.generationKwh, greaterThan(0));
    expect(insights.installedKwp, greaterThan(0));
    expect(insights.stations.where((s) => s.yield7d != null).length, greaterThan(20));
    expect(insights.activeAlerts, greaterThan(0));

    // Second sweep is idempotent and cheap.
    final before = api.requestCount;
    await engine.syncNow();
    expect(engine.status.lastError, isNull);
    expect(api.requestCount - before, lessThan(before), reason: 'daily/monthly history is not re-fetched on the same day');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
