import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/providers.dart';
import 'core/schools/school_dataset.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/credential_store.dart';
import 'core/sync/station_region.dart';
import 'core/utils/app_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTime.ensureInitialised();

  final desktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  if (desktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = await AppDatabase.open(p.join(dir.path, 'unicef_solar.db'));

  final prefs = await SharedPreferences.getInstance();
  final settings = await AppSettings.load(prefs);
  final store = CredentialStore();
  final credentials = await store.load();
  final gwnCredentials = await store.loadGwn();
  final boundaries = await loadBoundaries();
  final seeds = await importSchoolDataset(db);

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      credentialStoreProvider.overrideWithValue(store),
      boundariesProvider.overrideWithValue(boundaries),
      demoSeedsProvider.overrideWithValue(seeds),
      initialSettingsProvider.overrideWithValue(settings),
      initialCredentialsProvider.overrideWithValue(credentials),
      initialGwnCredentialsProvider.overrideWithValue(gwnCredentials),
    ],
    child: const SolarMonitorApp(),
  ));
}

/// Imports the bundled MEHE/UNICEF school dataset when its version changed
/// and returns the demo seeds (real solarised schools). Never throws.
Future<List<DemoSeed>> importSchoolDataset(AppDatabase db) async {
  try {
    final text = await rootBundle.loadString(SchoolDataset.assetPath);
    final dataset = SchoolDataset.fromJson(text);
    await SchoolDatasetImporter(db).importIfNeeded(dataset);
    return dataset.demoSeeds;
  } catch (e) {
    debugPrint('School dataset unavailable: $e');
    return const [];
  }
}

/// Loads the bundled governorate/district polygons (null if unavailable).
Future<LebanonBoundaries?> loadBoundaries() async {
  try {
    final gov = await rootBundle.loadString('assets/geo/lebanon_governorates.geojson');
    final dist = await rootBundle.loadString('assets/geo/lebanon_districts.geojson');
    return LebanonBoundaries.fromGeoJson(governoratesJson: gov, districtsJson: dist);
  } catch (_) {
    return null;
  }
}
