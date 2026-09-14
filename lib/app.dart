import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/alarms/alarms_screen.dart';
import 'features/connectivity/connectivity_screen.dart';
import 'features/education/education_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/map/map_screen.dart';
import 'features/overview/overview_screen.dart';
import 'features/programme/programme_screen.dart';
import 'features/schools/school_record_screen.dart';
import 'features/schools/schools_directory_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/stations/station_detail_screen.dart';
import 'features/stations/stations_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final canSync = ref.read(canSyncProvider);
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: canSync ? '/dashboard' : '/settings',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
          GoRoute(path: '/dashboard', pageBuilder: (c, s) => const NoTransitionPage(child: OverviewScreen())),
          GoRoute(path: '/analytics', pageBuilder: (c, s) => const NoTransitionPage(child: DashboardScreen())),
          GoRoute(path: '/programme', pageBuilder: (c, s) => const NoTransitionPage(child: ProgrammeScreen())),
          GoRoute(path: '/connectivity', pageBuilder: (c, s) => const NoTransitionPage(child: ConnectivityScreen())),
          GoRoute(path: '/education', pageBuilder: (c, s) => const NoTransitionPage(child: EducationScreen())),
          GoRoute(
            path: '/schools',
            pageBuilder: (c, s) => NoTransitionPage(
              child: SchoolsDirectoryScreen(
                initialQuery: s.uri.queryParameters['q'],
                initialRegion: s.uri.queryParameters['region'],
                initialCaza: s.uri.queryParameters['caza'],
                initialConnected: s.uri.queryParameters['connected'],
                initialSolar: s.uri.queryParameters['solar'],
                initialMonitored: s.uri.queryParameters['monitored'],
                initialFilter: s.uri.queryParameters['filter'],
              ),
            ),
            routes: [
              GoRoute(
                path: ':cerd',
                pageBuilder: (c, s) => NoTransitionPage(child: SchoolRecordScreen(cerd: int.tryParse(s.pathParameters['cerd'] ?? '') ?? 0)),
              ),
            ],
          ),
          GoRoute(
            path: '/stations',
            pageBuilder: (c, s) => NoTransitionPage(child: StationsScreen(initialQuery: s.uri.queryParameters['q'], initialRegion: s.uri.queryParameters['region'], initialStatus: s.uri.queryParameters['status'], initialFilter: s.uri.queryParameters['filter'])),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (c, s) => NoTransitionPage(child: StationDetailScreen(stationId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
              ),
            ],
          ),
          GoRoute(path: '/alarms', pageBuilder: (c, s) => NoTransitionPage(child: AlarmsScreen(initialStationId: int.tryParse(s.uri.queryParameters['station'] ?? '')))),
          GoRoute(path: '/map', pageBuilder: (c, s) => const NoTransitionPage(child: MapScreen())),
          GoRoute(path: '/settings', pageBuilder: (c, s) => const NoTransitionPage(child: SettingsScreen())),
        ],
      ),
    ],
  );
});

class SolarMonitorApp extends ConsumerStatefulWidget {
  const SolarMonitorApp({super.key});

  @override
  ConsumerState<SolarMonitorApp> createState() => _SolarMonitorAppState();
}

class _SolarMonitorAppState extends ConsumerState<SolarMonitorApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final engine = ref.read(syncEngineProvider);
      await engine.loadMeta();
      if (ref.read(canSyncProvider)) engine.start();
      _applyWakelock(ref.read(settingsProvider).keepScreenOn);
    });
  }

  void _applyWakelock(bool on) {
    try {
      WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = ref.watch(settingsProvider.select((s) => s.darkMode));
    ref.listen(settingsProvider.select((s) => s.keepScreenOn), (_, on) => _applyWakelock(on));
    ref.listen(canSyncProvider, (prev, next) {
      final engine = ref.read(syncEngineProvider);
      if (next) {
        engine.start();
      } else {
        engine.stop();
      }
    });
    // Restart the scheduler when the data source changes (credentials/demo).
    ref.listen(apiProvider, (prev, next) {
      if (prev != null && ref.read(canSyncProvider)) ref.read(syncEngineProvider).start();
    });
    return MaterialApp.router(
      title: 'UNICEF School Solar Monitor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
