import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'alert_dao.dart';
import 'device_dao.dart';
import 'retention.dart';
import 'station_dao.dart';
import 'sync_dao.dart';

/// Which part of the data changed — providers subscribe by kind.
enum DataKind { stations, latest, devices, daily, alerts, buckets, all }

/// Owns the SQLite connection and the DAOs. Use [AppDatabase.open] for a file
/// database and [AppDatabase.openInMemory] in tests.
class AppDatabase {
  AppDatabase._(this.db)
      : stations = StationDao(db),
        devices = DeviceDao(db),
        alerts = AlertDao(db),
        sync = SyncDao(db),
        retention = Retention(db);

  static const int schemaVersion = 1;

  final Database db;
  final StationDao stations;
  final DeviceDao devices;
  final AlertDao alerts;
  final SyncDao sync;
  final Retention retention;

  final StreamController<Set<DataKind>> _changes = StreamController<Set<DataKind>>.broadcast();
  final Set<DataKind> _pending = {};
  Timer? _debounce;

  /// Emits (debounced, ≥ 400 ms) the set of kinds that changed.
  Stream<Set<DataKind>> get changes => _changes.stream;

  void notifyChanged([DataKind kind = DataKind.all]) {
    if (_changes.isClosed) return;
    _pending.add(kind);
    _debounce ??= Timer(const Duration(milliseconds: 400), () {
      _debounce = null;
      final kinds = Set<DataKind>.from(_pending);
      _pending.clear();
      if (!_changes.isClosed) _changes.add(kinds);
    });
  }

  static Future<AppDatabase> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _configure,
        onCreate: (db, v) => createSchema(db),
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<AppDatabase> openInMemory({DatabaseFactory? factory}) => open(inMemoryDatabasePath, factory: factory);

  static Future<void> _configure(Database db) async {
    for (final pragma in [
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA temp_store = MEMORY',
      'PRAGMA cache_size = -16384',
      'PRAGMA busy_timeout = 5000',
    ]) {
      try {
        await db.execute(pragma);
      } catch (_) {
        // In-memory databases reject WAL; ignore.
      }
    }
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    // Future migrations go here (from < 2 → ..., etc.).
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stations (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT, lat REAL, lng REAL,
        region TEXT, caza TEXT,
        timezone TEXT,
        grid_type TEXT,
        installed_capacity_kw REAL,
        battery_capacity_kwh REAL,
        start_operating_ts INTEGER, created_ts INTEGER,
        owner_name TEXT, contact_phone TEXT,
        api_status TEXT,
        connection_status TEXT,
        last_update_ts INTEGER,
        last_seen_at INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stations_region ON stations(region)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stations_status ON stations(connection_status)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_latest (
        station_id INTEGER PRIMARY KEY,
        data_ts INTEGER,
        fetched_at INTEGER NOT NULL,
        source TEXT,
        generation_w REAL, consumption_w REAL, grid_export_w REAL, grid_import_w REAL, wire_w REAL,
        charge_w REAL, discharge_w REAL, battery_w REAL, battery_soc REAL, irradiance REAL,
        today_gen_kwh REAL, today_cons_kwh REAL, today_import_kwh REAL, today_export_kwh REAL,
        today_charge_kwh REAL, today_discharge_kwh REAL,
        last_error_at INTEGER, last_error_msg TEXT,
        raw_json TEXT
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        device_sn TEXT PRIMARY KEY,
        station_id INTEGER, device_id INTEGER,
        device_type TEXT, product_id TEXT, product_name TEXT, collector_sn TEXT,
        connect_status TEXT,
        collection_ts INTEGER,
        last_seen_at INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL, updated_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_devices_station ON devices(station_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_latest (
        device_sn TEXT PRIMARY KEY,
        collection_ts INTEGER,
        fetched_at INTEGER NOT NULL,
        device_type TEXT,
        state TEXT,
        station_id INTEGER,
        data_json TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_device_latest_station ON device_latest(station_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_samples (
        device_sn TEXT NOT NULL, ts INTEGER NOT NULL,
        soc REAL, battery_w REAL, battery_v REAL, battery_temp REAL,
        pv_w REAL, pv1_w REAL, pv2_w REAL, pv3_w REAL, pv4_w REAL,
        load_w REAL, grid_w REAL, grid_hz REAL, grid_v REAL, inverter_temp REAL,
        daily_gen_kwh REAL, daily_cons_kwh REAL, daily_import_kwh REAL, daily_export_kwh REAL,
        daily_charge_kwh REAL, daily_discharge_kwh REAL, total_gen_kwh REAL,
        PRIMARY KEY (device_sn, ts)
      ) WITHOUT ROWID''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_samples_ts ON device_samples(ts)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_snapshots (
        station_id INTEGER NOT NULL,
        ts INTEGER NOT NULL,
        fetched_at INTEGER NOT NULL,
        source TEXT,
        generation_w REAL, consumption_w REAL, grid_export_w REAL, grid_import_w REAL, wire_w REAL,
        charge_w REAL, discharge_w REAL, battery_w REAL, battery_soc REAL, irradiance REAL,
        PRIMARY KEY (station_id, ts)
      ) WITHOUT ROWID''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snap_ts ON station_snapshots(ts)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_daily (
        station_id INTEGER NOT NULL, day TEXT NOT NULL,
        generation_kwh REAL, consumption_kwh REAL, grid_export_kwh REAL, grid_import_kwh REAL,
        charge_kwh REAL, discharge_kwh REAL, full_power_hours REAL, completeness_pct REAL,
        source TEXT,
        PRIMARY KEY (station_id, day)
      ) WITHOUT ROWID''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_daily_day ON station_daily(day)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_monthly (
        station_id INTEGER NOT NULL, month TEXT NOT NULL,
        generation_kwh REAL, consumption_kwh REAL, grid_export_kwh REAL, grid_import_kwh REAL,
        charge_kwh REAL, discharge_kwh REAL, source TEXT,
        PRIMARY KEY (station_id, month)
      ) WITHOUT ROWID''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_battery_daily (
        station_id INTEGER NOT NULL, day TEXT NOT NULL,
        soc_min REAL, soc_max REAL, soc_avg REAL, hours_below_20 REAL, temp_max REAL,
        charge_kwh REAL, discharge_kwh REAL, samples INTEGER,
        PRIMARY KEY (station_id, day)
      ) WITHOUT ROWID''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS power_buckets (
        region TEXT NOT NULL DEFAULT '',
        bucket_ts INTEGER NOT NULL,
        stations_reporting INTEGER,
        gen_w REAL, cons_w REAL, import_w REAL, export_w REAL, charge_w REAL, discharge_w REAL, soc_avg REAL,
        PRIMARY KEY (region, bucket_ts)
      ) WITHOUT ROWID''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_status_events (
        station_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        start_ts INTEGER NOT NULL,
        end_ts INTEGER,
        source TEXT,
        PRIMARY KEY (station_id, start_ts)
      ) WITHOUT ROWID''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_status_events_open ON station_status_events(end_ts)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY,
        station_id INTEGER, station_name TEXT, device_sn TEXT, device_type TEXT,
        level INTEGER NOT NULL DEFAULT 2,
        code TEXT, name TEXT, description TEXT,
        start_ts INTEGER, end_ts INTEGER,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        acknowledged INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'cloud',
        raw_json TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_alerts_station_start ON alerts(station_id, start_ts DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_alerts_active_start ON alerts(status, start_ts DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_alerts_status_level ON alerts(status, level)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER,
        ok INTEGER, items INTEGER, message TEXT
      )''');
    await db.execute('CREATE TABLE IF NOT EXISTS sync_meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  static const List<String> tables = [
    'stations', 'station_latest', 'devices', 'device_latest', 'device_samples', 'station_snapshots',
    'station_daily', 'station_monthly', 'station_battery_daily', 'power_buckets', 'station_status_events',
    'alerts', 'sync_log', 'sync_meta',
  ];

  /// Row counts per table (Settings → database statistics).
  Future<Map<String, int>> tableCounts() async {
    final out = <String, int>{};
    for (final t in tables) {
      out[t] = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0;
    }
    return out;
  }

  /// Approximate file size in bytes (page_count × page_size).
  Future<int> sizeBytes() async {
    try {
      final pages = Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_count')) ?? 0;
      final size = Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_size')) ?? 0;
      return pages * size;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes all synced data (keeps settings). Used when switching accounts.
  Future<void> clearAllData() async {
    await db.transaction((txn) async {
      for (final t in tables) {
        await txn.delete(t);
      }
    });
    notifyChanged(DataKind.all);
  }

  Future<void> close() async {
    _debounce?.cancel();
    await _changes.close();
    await db.close();
  }
}

/// Epoch seconds now.
int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Splits a list into chunks of [size].
Iterable<List<T>> chunked<T>(List<T> list, int size) sync* {
  for (var i = 0; i < list.length; i += size) {
    yield list.sublist(i, i + size > list.length ? list.length : i + size);
  }
}

String placeholders(int n) => List.filled(n, '?').join(',');
