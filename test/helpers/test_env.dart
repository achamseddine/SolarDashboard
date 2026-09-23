import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unicef_solar_monitor/core/db/app_database.dart';
import 'package:unicef_solar_monitor/core/demo/demo_deye_api.dart';
import 'package:unicef_solar_monitor/core/demo/demo_gwn_api.dart';
import 'package:unicef_solar_monitor/core/providers.dart';
import 'package:unicef_solar_monitor/core/schools/school_dataset.dart';
import 'package:unicef_solar_monitor/core/settings/app_settings.dart';
import 'package:unicef_solar_monitor/core/sync/network_sync.dart';
import 'package:unicef_solar_monitor/core/sync/sync_engine.dart';
import 'package:unicef_solar_monitor/core/theme.dart';
import 'package:unicef_solar_monitor/core/utils/app_time.dart';

/// In-memory database seeded by one demo sweep, plus the provider overrides
/// needed to pump any screen in a widget test.
///
/// ```dart
/// final env = await TestEnv.create();
/// await tester.pumpWidget(env.wrap(const DashboardScreen()));
/// await tester.pump(); await tester.pump(const Duration(seconds: 1));
/// ```
class TestEnv {
  TestEnv._(this.db, this.prefs, this.settings, this.api, this.gwnApi);

  final AppDatabase db;
  final SharedPreferences prefs;
  final AppSettings settings;
  final DemoDeyeApi api;
  final DemoGwnApi gwnApi;

  static SchoolDataset? _dataset;

  /// The bundled school dataset, read once from `assets/data/schools.json`.
  static SchoolDataset get dataset => _dataset ??= SchoolDataset.fromJson(File(SchoolDataset.assetPath).readAsStringSync());

  static Future<TestEnv> create({int schools = 20, bool sync = true, AppSettings? settings, bool withSchools = true, int networks = 0}) async {
    sqfliteFfiInit();
    AppTime.ensureInitialised();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    if (withSchools) await SchoolDatasetImporter(db).importIfNeeded(dataset);
    final api = DemoDeyeApi(latency: Duration.zero, schools: schools, seeds: withSchools ? dataset.demoSeeds : const []);
    final s = settings ?? const AppSettings(demoMode: true, maxConcurrentRequests: 8);
    if (sync) {
      final engine = SyncEngine(db: db, apiProvider: () => api, settingsProvider: () => s);
      await engine.loadMeta();
      await engine.syncNow();
    }
    final gwn = DemoGwnApi(
      latency: Duration.zero,
      networks: networks == 0 ? 1 : networks,
      seeds: withSchools ? dataset.demoSeeds : const [],
    );
    if (networks > 0) {
      await NetworkSync(api: gwn, db: db).run();
    }
    return TestEnv._(db, prefs, s, api, gwn);
  }

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        initialSettingsProvider.overrideWithValue(settings),
        apiProvider.overrideWithValue(api),
        demoSeedsProvider.overrideWithValue(api.seeds),
        gwnApiProvider.overrideWithValue(gwnApi),
      ];

  /// Wraps [child] in a ProviderScope + MaterialApp sized like a tablet.
  Widget wrap(Widget child, {Size size = const Size(1280, 800)}) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(data: MediaQueryData(size: size), child: Scaffold(body: child)),
        ),
      );

  Future<void> dispose() => db.close();

  /// Creates the environment from inside a widget test (real async zone).
  static Future<TestEnv> createFor(WidgetTester tester, {int schools = 20, int networks = 0}) async {
    late TestEnv env;
    await tester.runAsync(() async => env = await create(schools: schools, networks: networks));
    return env;
  }

  /// Flushes late real-time work and pending fake timers (call at the end of
  /// a test that triggers background writes, e.g. a station refresh).
  static Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  }

  /// Lets real async work (database queries) complete, then pumps frames and
  /// fires the database change debounce so providers rebuild.
  static Future<void> settle(WidgetTester tester, {int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
  }
}
