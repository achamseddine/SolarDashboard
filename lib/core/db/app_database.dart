import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'alert_dao.dart';
import 'device_dao.dart';
import 'network_dao.dart';
import 'retention.dart';
import 'school_dao.dart';
import 'station_dao.dart';
import 'sync_dao.dart';

/// Which part of the data changed — providers subscribe by kind.
enum DataKind { stations, latest, devices, daily, alerts, buckets, schools, all }

/// Owns the SQLite connection and the DAOs. Use [AppDatabase.open] for a file
/// database and [AppDatabase.openInMemory] in tests.
class AppDatabase {
  AppDatabase._(this.db)
      : stations = StationDao(db),
        devices = DeviceDao(db),
        alerts = AlertDao(db),
        sync = SyncDao(db),
        schools = SchoolDao(db),
        networks = NetworkDao(db),
        retention = Retention(db);

  /// v1: plant/device/energy/alarm tables. v2: school dataset + links.
  /// v3: GWN Cloud networks, devices, daily counters and alarms.
  /// v4: observation counters on the GWN daily rows.
  static const int schemaVersion = 4;

  final Database db;
  final StationDao stations;
  final DeviceDao devices;
  final AlertDao alerts;
  final SyncDao sync;
  final SchoolDao schools;
  final NetworkDao networks;
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
    // New tables and indexes are all CREATE IF NOT EXISTS, so re-running the
    // schema script covers them. Columns added to a table that already
    // exists need an explicit ALTER.
    await createSchema(db);
    await _addColumn(db, 'gwn_network_daily', 'observations', 'INTEGER');
    await _addColumn(db, 'gwn_network_daily', 'online_observations', 'INTEGER');
  }

  /// Adds a column unless the table already has it.
  static Future<void> _addColumn(DatabaseExecutor db, String table, String column, String type) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (info.any((r) => r['name'] == column)) return;
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    } catch (_) {
      // The table may not exist yet on a fresh database; createSchema made it
      // with the column already present.
    }
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

    // ---- v2: school dataset (bundled MEHE/UNICEF workbooks) + plant links
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schools (
        cerd INTEGER PRIMARY KEY,
        in_master INTEGER NOT NULL DEFAULT 1,
        name TEXT NOT NULL, name_ar TEXT,
        region TEXT, caza TEXT, cadaster TEXT, cas_code INTEGER,
        ownership TEXT, capacity INTEGER,
        lat REAL, lng REAL, address TEXT, phone TEXT,
        students_am INTEGER, students_pm INTEGER, enrollment INTEGER, pm_cerd INTEGER,
        connected INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_schools_region ON schools(region)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_solar (
        cerd INTEGER PRIMARY KEY,
        listed_name TEXT, status TEXT NOT NULL, status_raw TEXT,
        donor TEXT, donor_group TEXT, project TEXT,
        cost_usd REAL, kwp REAL, inverter_kw REAL, battery_kwh REAL,
        enrollment_2324 INTEGER, qa_cost_usd REAL, led_cost_usd REAL,
        shift TEXT, language TEXT, contractor TEXT, consultant TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_school_solar_status ON school_solar(status)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_loads (
        cerd INTEGER PRIMARY KEY,
        lighting_kwh REAL, hvac_kwh REAL, it_kwh REAL, misc_kwh REAL
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cerd INTEGER NOT NULL, type TEXT NOT NULL, category TEXT NOT NULL,
        watts REAL, count INTEGER, hours_per_day REAL, annual_kwh REAL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_school_equipment_cerd ON school_equipment(cerd)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_education (
        cerd INTEGER PRIMARY KEY,
        shift TEXT,
        am_submitted INTEGER, am_attendance REAL, am_absence10 REAL,
        pm_submitted INTEGER, pm_attendance REAL, pm_absence10 REAL,
        am_risk TEXT, pm_risk TEXT,
        pm_teachers INTEGER, pm_teacher_terms_json TEXT, student_teacher_ratio REAL,
        visited_third_party INTEGER, pm_teacher_risk TEXT,
        pm_female_teachers INTEGER, pm_male_teachers INTEGER, teaching_days INTEGER,
        visited_by_bdo INTEGER,
        monthly_student_risk_json TEXT, monthly_teacher_risk_json TEXT
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS station_school_links (
        station_id INTEGER PRIMARY KEY,
        cerd INTEGER NOT NULL,
        method TEXT NOT NULL,
        confidence REAL NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_links_cerd ON station_school_links(cerd)');

    // ------------------------------------------------ GWN Cloud (v3)
    // One network per school LAN, its managed devices, the daily counters the
    // indicator framework is computed from, and the cloud's alarms.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gwn_networks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cerd INTEGER,
        link_confidence REAL,
        address TEXT,
        timezone TEXT,
        last_seen_ts INTEGER
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gwn_networks_cerd ON gwn_networks(cerd)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gwn_devices (
        network_id TEXT NOT NULL,
        mac TEXT NOT NULL,
        name TEXT,
        kind TEXT,
        status TEXT,
        model TEXT,
        firmware TEXT,
        ip TEXT,
        uptime_s INTEGER,
        client_count INTEGER,
        cpu_percent REAL,
        memory_percent REAL,
        poe_total INTEGER, poe_active INTEGER, poe_failed INTEGER,
        ports_up INTEGER, ports_down INTEGER, ports_error INTEGER,
        last_seen_ts INTEGER,
        PRIMARY KEY (network_id, mac)
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gwn_devices_kind ON gwn_devices(kind, status)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gwn_network_daily (
        network_id TEXT NOT NULL,
        day TEXT NOT NULL,
        wan_up_minutes INTEGER, expected_minutes INTEGER,
        rx_bytes INTEGER, tx_bytes INTEGER,
        unique_clients INTEGER, peak_clients INTEGER,
        aps_online INTEGER, aps_total INTEGER, active_aps INTEGER,
        teaching_bytes INTEGER,
        observations INTEGER, online_observations INTEGER,
        PRIMARY KEY (network_id, day)
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gwn_daily_day ON gwn_network_daily(day)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gwn_ssid_daily (
        network_id TEXT NOT NULL,
        day TEXT NOT NULL,
        ssid TEXT NOT NULL,
        bytes INTEGER, clients INTEGER,
        PRIMARY KEY (network_id, day, ssid)
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS gwn_alarms (
        id TEXT PRIMARY KEY,
        network_id TEXT NOT NULL,
        level TEXT,
        message TEXT,
        start_ts INTEGER NOT NULL,
        device_mac TEXT,
        end_ts INTEGER
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gwn_alarms_open ON gwn_alarms(end_ts, start_ts DESC)');
  }

  /// Tables filled by synchronisation (cleared by [clearAllData]).
  static const List<String> tables = [
    'stations', 'station_latest', 'devices', 'device_latest', 'device_samples', 'station_snapshots',
    'station_daily', 'station_monthly', 'station_battery_daily', 'power_buckets', 'station_status_events',
    'alerts', 'sync_log', 'sync_meta',
    'gwn_networks', 'gwn_devices', 'gwn_network_daily', 'gwn_ssid_daily', 'gwn_alarms',
  ];

  /// Tables filled from the bundled school dataset (kept by [clearAllData];
  /// re-imported from the asset when its version changes).
  static const List<String> datasetTables = ['schools', 'school_solar', 'school_loads', 'school_equipment', 'school_education'];

  /// Plant ↔ school links: derived from synced plants but kept across
  /// [clearAllData] so manual links survive a re-sync.
  static const String linksTable = 'station_school_links';

  /// Row counts per table (Settings → database statistics).
  Future<Map<String, int>> tableCounts() async {
    final out = <String, int>{};
    for (final t in [...tables, ...datasetTables, linksTable]) {
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

  /// Deletes all synced data (keeps settings, the school dataset and
  /// plant ↔ school links). Used when switching accounts.
  Future<void> clearAllData() async {
    // The dataset version lives in sync_meta; keep it so the asset is not
    // re-imported needlessly.
    final datasetMeta = await db.query('sync_meta', where: "key LIKE 'schools.%'");
    await db.transaction((txn) async {
      for (final t in tables) {
        await txn.delete(t);
      }
      for (final row in datasetMeta) {
        await txn.insert('sync_meta', row, conflictAlgorithm: ConflictAlgorithm.replace);
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
