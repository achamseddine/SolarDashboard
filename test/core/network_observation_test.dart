import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unicef_solar_monitor/core/db/app_database.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';

Future<AppDatabase> _db() async {
  sqfliteFfiInit();
  return AppDatabase.openInMemory(factory: databaseFactoryFfi);
}

GwnNetworkDay _seen({int? clients, int? apsOnline, int apsTotal = 4}) => GwnNetworkDay(
      networkId: 'n1',
      day: '2026-09-24',
      uniqueClients: clients,
      peakClients: clients,
      apsOnline: apsOnline,
      apsTotal: apsTotal,
      activeAps: clients == null || clients == 0 ? 0 : apsOnline,
    );

void main() {
  test('repeated observations build one day, keeping the peak', () async {
    final db = await _db();
    addTearDown(db.close);

    await db.networks.recordObservation(_seen(clients: 12, apsOnline: 4), online: true);
    await db.networks.recordObservation(_seen(clients: 40, apsOnline: 4), online: true);
    await db.networks.recordObservation(_seen(clients: 9, apsOnline: 3), online: true);
    await db.networks.recordObservation(_seen(clients: 11, apsOnline: 4), online: true);

    final day = (await db.networks.getDaily()).single;
    expect(day.observations, 4);
    expect(day.onlineObservations, 4);
    expect(day.peakClients, 40, reason: 'the busiest look is the day\'s peak');
    expect(day.uniqueClients, 40);
    expect(day.uptimeShare, 1.0);
  });

  test('uptime is the share of observations that found the network up', () async {
    final db = await _db();
    addTearDown(db.close);

    for (final up in [true, true, false, true]) {
      await db.networks.recordObservation(_seen(clients: up ? 10 : 0, apsOnline: up ? 4 : 0), online: up);
    }

    final day = (await db.networks.getDaily()).single;
    expect(day.observations, 4);
    expect(day.onlineObservations, 3);
    expect(day.uptimeShare, closeTo(0.75, 0.001));
  });

  test('reported minutes win over sampled observations when the source has them', () async {
    final db = await _db();
    addTearDown(db.close);

    await db.networks.recordObservation(
      const GwnNetworkDay(networkId: 'n1', day: '2026-09-24', wanUpMinutes: 240, expectedMinutes: 480),
      online: true,
    );
    final day = (await db.networks.getDaily()).single;
    expect(day.uptimeShare, closeTo(0.5, 0.001), reason: 'minutes are measured, observations only sampled');
  });

  test('a v3 database gains the observation columns on upgrade', () async {
    sqfliteFfiInit();
    // An in-memory database is discarded when closed, so the migration has
    // to be exercised against a file that persists between opens.
    final dir = await Directory.systemTemp.createTemp('gwn_migration');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/unicef_solar.db';
    // Build the table as v3 had it, without the new columns.
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 3, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE gwn_network_daily (
          network_id TEXT NOT NULL, day TEXT NOT NULL,
          wan_up_minutes INTEGER, expected_minutes INTEGER,
          rx_bytes INTEGER, tx_bytes INTEGER,
          unique_clients INTEGER, peak_clients INTEGER,
          aps_online INTEGER, aps_total INTEGER, active_aps INTEGER,
          teaching_bytes INTEGER,
          PRIMARY KEY (network_id, day))''');
      await db.insert('gwn_network_daily', {'network_id': 'n1', 'day': '2026-09-01', 'unique_clients': 5});
    }));
    await raw.close();

    final db = await AppDatabase.open(path, factory: databaseFactoryFfi);
    addTearDown(db.close);

    final cols = await db.db.rawQuery('PRAGMA table_info(gwn_network_daily)');
    final names = cols.map((c) => c['name']).toSet();
    expect(names, containsAll(<String>['observations', 'online_observations']));

    // The row that was already there survives.
    final rows = await db.networks.getDaily();
    expect(rows.single.uniqueClients, 5);
  });

  test('a single look cannot certify uptime', () async {
    final db = await _db();
    addTearDown(db.close);

    await db.networks.recordObservation(_seen(clients: 10, apsOnline: 4), online: true);
    var day = (await db.networks.getDaily()).single;
    expect(day.wasSeenOnline, isTrue, reason: 'one look does show it was up');
    expect(day.uptimeShare, isNull, reason: 'but one look is not a percentage');
    expect(day.hasUptime, isFalse);

    // Once enough looks accrue, the share is reportable.
    for (var i = 0; i < GwnNetworkDay.minObservations - 1; i++) {
      await db.networks.recordObservation(_seen(clients: 10, apsOnline: 4), online: true);
    }
    day = (await db.networks.getDaily()).single;
    expect(day.hasUptime, isTrue);
    expect(day.uptimeShare, 1.0);
  });
}