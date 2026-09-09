import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unicef_solar_monitor/core/db/app_database.dart';
import 'package:unicef_solar_monitor/core/demo/demo_deye_api.dart';
import 'package:unicef_solar_monitor/core/providers.dart';
import 'package:unicef_solar_monitor/core/settings/app_settings.dart';
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
  TestEnv._(this.db, this.prefs, this.settings, this.api);

  final AppDatabase db;
  final SharedPreferences prefs;
  final AppSettings settings;
  final DemoDeyeApi api;

  static Future<TestEnv> create({int schools = 20, bool sync = true, AppSettings? settings}) async {
    sqfliteFfiInit();
    AppTime.ensureInitialised();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    final api = DemoDeyeApi(latency: Duration.zero, schools: schools);
    final s = settings ?? const AppSettings(demoMode: true, maxConcurrentRequests: 8);
    if (sync) {
      final engine = SyncEngine(db: db, apiProvider: () => api, settingsProvider: () => s);
      await engine.loadMeta();
      await engine.syncNow();
    }
    return TestEnv._(db, prefs, s, api);
  }

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        initialSettingsProvider.overrideWithValue(settings),
        apiProvider.overrideWithValue(api),
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
}
