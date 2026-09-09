import 'dart:math' as math;

import '../db/app_database.dart';
import '../db/station_dao.dart';
import '../models/alert.dart';
import '../models/fleet_insights.dart';
import '../models/station.dart';
import '../settings/app_settings.dart';
import '../sync/station_region.dart';
import '../utils/app_time.dart';

/// Builds [FleetInsights] from the local database. All heavy lifting is SQL
/// aggregates over ≤ N-station tables; the Dart part is O(stations).
class FleetInsightsBuilder {
  FleetInsightsBuilder(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<FleetInsights> build(AppSettings settings) async {
    final now = _clock();
    final nowTs = now.millisecondsSinceEpoch ~/ 1000;
    final staleSec = settings.staleAfter.inSeconds;
    final today = AppTime.today();
    final yesterday = AppTime.addDays(today, -1);
    final d7 = AppTime.addDays(today, -7);
    final d30 = AppTime.addDays(today, -30);

    final stations = await db.stations.getStations();
    final latest = await db.stations.allLatest();
    final events = await db.stations.currentStatusEvents();
    final alertCounts = await db.alerts.activeCountPerStation();
    final alertLevels = await db.alerts.highestActiveLevelPerStation();
    final todayEnergy = await db.stations.dailyForDay(today);
    final yesterdayEnergy = await db.stations.dailyForDay(yesterday);
    final sums7 = await db.stations.dailySumsPerStation(d7, yesterday);
    final sums30 = await db.stations.dailySumsPerStation(d30, yesterday);
    final days7 = await db.stations.dailyDayCounts(d7, yesterday);
    final days30 = await db.stations.dailyDayCounts(d30, yesterday);
    final batteryToday = await db.stations.batteryDayForAll(today);
    final statusEvents30 = await db.stations.statusEventsBetween(nowTs - 30 * 86400, nowTs);
    final gridHours = await _gridHoursToday(nowTs);

    // Availability per station from status events.
    final avail7 = <int, double>{};
    final avail30 = <int, double>{};
    final outages30 = <int, int>{};
    final recoveries = <double>[];
    var outages7 = 0;
    final byStation = <int, List<StatusEvent>>{};
    for (final e in statusEvents30) {
      byStation.putIfAbsent(e.stationId, () => []).add(e);
    }
    byStation.forEach((sid, evs) {
      avail7[sid] = _availability(evs, nowTs - 7 * 86400, nowTs);
      avail30[sid] = _availability(evs, nowTs - 30 * 86400, nowTs);
      var n = 0;
      for (final e in evs) {
        if (!e.status.isDown) continue;
        n++;
        if (e.startTs >= nowTs - 7 * 86400) outages7++;
        if (e.endTs != null) recoveries.add((e.endTs! - e.startTs).toDouble());
      }
      outages30[sid] = n;
    });

    // Per-station yields.
    final insights = <StationInsight>[];
    final yield7ByRegion = <String, List<double>>{};
    for (final s in stations) {
      final l = latest[s.id];
      final kwp = s.installedCapacityKw;
      final t = todayEnergy[s.id];
      final todayGen = l?.today.generationKwh ?? t?.generationKwh;
      final todayCons = l?.today.consumptionKwh ?? t?.consumptionKwh;
      final todayImp = l?.today.gridImportKwh ?? t?.gridImportKwh;
      final todayExp = l?.today.gridExportKwh ?? t?.gridExportKwh;
      final s7 = sums7[s.id];
      final s30 = sums30[s.id];
      final n7 = days7[s.id] ?? 0;
      final n30 = days30[s.id] ?? 0;
      double? perKwp(double? kwh, int days) => kwh == null || kwp == null || kwp <= 0 || days == 0 ? null : kwh / kwp / days;
      final y7 = perKwp(s7?.generationKwh, n7);
      if (y7 != null && n7 >= 3 && !s.status.isDown) yield7ByRegion.putIfAbsent(s.region ?? LebanonRegions.unassigned, () => []).add(y7);
      final ev = events[s.id];
      final dataTs = l?.dataTs ?? s.lastUpdateTs;
      final b = batteryToday[s.id];
      insights.add(StationInsight(
        station: s,
        latest: l,
        status: s.status,
        statusSince: ev?.startTs,
        dataAgeSeconds: dataTs == null ? null : nowTs - dataTs,
        todayGenKwh: todayGen,
        todayConsKwh: todayCons,
        todayImportKwh: todayImp,
        todayExportKwh: todayExp,
        yieldTodaySoFar: perKwp(todayGen, 1),
        yieldLastDay: perKwp(yesterdayEnergy[s.id]?.generationKwh, 1),
        yield7d: y7,
        yield30d: perKwp(s30?.generationKwh, n30),
        selfSufficiency7d: s7?.selfSufficiency,
        availability7d: avail7[s.id],
        availability30d: avail30[s.id],
        outages30d: outages30[s.id] ?? 0,
        currentOutage: s.status.isDown && ev != null ? Duration(seconds: nowTs - ev.startTs) : null,
        activeAlerts: alertCounts[s.id] ?? 0,
        highestAlert: alertLevels[s.id],
        socNow: l?.snapshot?.batterySoc,
        socMinToday: b?.socMin,
        hoursBelow20Today: b?.hoursBelow20,
        batteryCyclesProxy7d: s.batteryCapacityKwh == null || s.batteryCapacityKwh! <= 0 || s7?.dischargeKwh == null ? null : s7!.dischargeKwh! / s.batteryCapacityKwh!,
        completeness7d: s7?.completenessPct,
        daysWithData7d: n7,
        gridHoursToday: gridHours[s.id],
        lastError: l?.lastErrorMsg,
      ));
    }
    final allY7 = yield7ByRegion.values.expand((e) => e).toList();
    final fleetMedian = _median(allY7);
    final withPeers = <StationInsight>[];
    for (final i in insights) {
      final peers = yield7ByRegion[i.region] ?? const [];
      final peerMedian = peers.length >= 5 ? _median(peers) : fleetMedian;
      withPeers.add(_withPeer(i, peerMedian));
    }

    // Live totals over reporting stations only.
    var gen = 0.0, cons = 0.0, imp = 0.0, exp = 0.0, chg = 0.0, dis = 0.0;
    var reporting = 0;
    var reportingKwp = 0.0;
    int? tsMin, tsMax;
    final socs = <double>[];
    final hist = List<int>.filled(5, 0);
    final counts = <StationStatus, int>{};
    final ageHist = <String, int>{'< 15 min': 0, '15–60 min': 0, '1–6 h': 0, '6–24 h': 0, '> 24 h': 0, 'never': 0};
    var errors = 0;
    for (final i in withPeers) {
      counts[i.status] = (counts[i.status] ?? 0) + 1;
      if (i.lastError != null && (i.latest?.lastErrorAt ?? 0) > nowTs - 3600) errors++;
      final age = i.dataAgeSeconds;
      if (age == null) {
        ageHist['never'] = ageHist['never']! + 1;
      } else if (age < 900) {
        ageHist['< 15 min'] = ageHist['< 15 min']! + 1;
      } else if (age < 3600) {
        ageHist['15–60 min'] = ageHist['15–60 min']! + 1;
      } else if (age < 6 * 3600) {
        ageHist['1–6 h'] = ageHist['1–6 h']! + 1;
      } else if (age < 86400) {
        ageHist['6–24 h'] = ageHist['6–24 h']! + 1;
      } else {
        ageHist['> 24 h'] = ageHist['> 24 h']! + 1;
      }
      final snap = i.snapshot;
      if (snap == null || i.isDown || age == null || age > staleSec) continue;
      reporting++;
      reportingKwp += i.kwp ?? 0;
      tsMin = tsMin == null ? snap.ts : math.min(tsMin, snap.ts);
      tsMax = tsMax == null ? snap.ts : math.max(tsMax, snap.ts);
      gen += snap.generationW ?? 0;
      cons += snap.consumptionW ?? 0;
      imp += snap.importW;
      exp += snap.exportW;
      final bn = snap.batteryNetW;
      if (bn > 0) {
        chg += bn;
      } else {
        dis += -bn;
      }
      final soc = snap.batterySoc;
      if (soc != null) {
        socs.add(soc);
        hist[soc >= 100 ? 4 : (soc / 20).floor().clamp(0, 4)]++;
      }
    }

    // Energy aggregates.
    final todayRows = await db.stations.fleetDailySeries(today, today);
    final dailySeries = await db.stations.fleetDailySeries(d30, today);
    final months = await db.stations.fleetMonthlySeries(AppTime.addMonths(today.substring(0, 7), -11), today.substring(0, 7));
    final lifetime = await db.stations.lifetimeTotals();
    final todayFleet = _sumEnergy('today', withPeers.map((i) => (i.todayGenKwh, i.todayConsKwh, i.todayImportKwh, i.todayExportKwh, i.latest?.today.chargeKwh, i.latest?.today.dischargeKwh)).toList(), fallback: todayRows.firstOrNull);
    final last7 = _sumDays('7d', dailySeries.where((d) => d.day.compareTo(d7) >= 0 && d.day.compareTo(yesterday) <= 0));
    final last30 = _sumDays('30d', dailySeries.where((d) => d.day.compareTo(yesterday) <= 0));

    // Regions.
    final regions = <RegionInsight>[];
    final byRegion = <String, List<StationInsight>>{};
    for (final i in withPeers) {
      byRegion.putIfAbsent(i.region, () => []).add(i);
    }
    final regionOrder = [...LebanonRegions.all, LebanonRegions.unassigned];
    for (final name in regionOrder) {
      final list = byRegion[name];
      if (list == null || list.isEmpty) continue;
      var rgen = 0.0, rcons = 0.0, rkwp = 0.0, rtg = 0.0, rtc = 0.0;
      var ralerts = 0;
      final rc = <StationStatus, int>{};
      final av = <double>[];
      final ys = <double>[];
      var cons7 = 0.0, imp7 = 0.0;
      for (final i in list) {
        rc[i.status] = (rc[i.status] ?? 0) + 1;
        rkwp += i.kwp ?? 0;
        rtg += i.todayGenKwh ?? 0;
        rtc += i.todayConsKwh ?? 0;
        ralerts += i.activeAlerts;
        if (i.availability7d != null) av.add(i.availability7d!);
        if (i.yield7d != null && i.daysWithData7d >= 3) ys.add(i.yield7d!);
        final s7 = sums7[i.id];
        cons7 += s7?.consumptionKwh ?? 0;
        imp7 += s7?.gridImportKwh ?? 0;
        final age = i.dataAgeSeconds;
        if (i.snapshot != null && !i.isDown && age != null && age <= staleSec) {
          rgen += i.snapshot!.generationW ?? 0;
          rcons += i.snapshot!.consumptionW ?? 0;
        }
      }
      regions.add(RegionInsight(
        name: name,
        stations: list.length,
        online: rc[StationStatus.online] ?? 0,
        offline: rc[StationStatus.offline] ?? 0,
        alarm: rc[StationStatus.alarm] ?? 0,
        stale: rc[StationStatus.stale] ?? 0,
        unknown: rc[StationStatus.unknown] ?? 0,
        kwp: rkwp,
        generationNowW: rgen,
        consumptionNowW: rcons,
        todayGenKwh: rtg,
        todayConsKwh: rtc,
        activeAlerts: ralerts,
        availability7d: av.isEmpty ? null : av.reduce((a, b) => a + b) / av.length,
        medianYield7d: _median(ys),
        selfSufficiency7d: cons7 < 1 ? null : ((cons7 - imp7) / cons7).clamp(0, 1),
      ));
    }

    // Alarms.
    final byLevel = await db.alerts.activeCountsByLevel();
    final topNames = await db.alerts.topActiveNames();
    final mostAlarming = await db.alerts.stationsWithMostAlerts();
    final perDay = await db.alerts.newAlertsPerDay(now: nowTs);
    final (_, mttrMedian) = await db.alerts.recoveryStats(now: nowTs);
    final openOver7 = await db.alerts.countOpenLongerThan(now: nowTs);

    final availabilities7 = withPeers.map((i) => i.availability7d).whereType<double>().toList();
    final availabilities30 = withPeers.map((i) => i.availability30d).whereType<double>().toList();
    final completeness = withPeers.map((i) => i.completeness7d).whereType<double>().toList();
    final gridHoursList = gridHours.values.toList();

    return FleetInsights(
      generatedAt: now,
      stations: withPeers,
      regions: regions,
      counts: counts,
      reportingStations: reporting,
      dataTsMin: tsMin,
      dataTsMax: tsMax,
      generationNowW: gen,
      consumptionNowW: cons,
      importNowW: imp,
      exportNowW: exp,
      chargeNowW: chg,
      dischargeNowW: dis,
      socMedian: _median(socs),
      socHistogram: hist,
      installedKwp: withPeers.fold(0.0, (a, i) => a + (i.kwp ?? 0)),
      reportingKwp: reportingKwp,
      capacityUtilisation: reportingKwp <= 0 ? null : gen / 1000 / reportingKwp,
      today: todayFleet,
      last7d: last7,
      last30d: last30,
      lifetime: lifetime,
      dailySeries30d: dailySeries,
      monthlySeries12m: months,
      co2FactorKgPerKwh: settings.co2FactorKgPerKwh,
      dieselLitresPerKwh: settings.dieselLitresPerKwh,
      activeAlertsByLevel: {for (final l in AlertLevel.values) l: byLevel[l] ?? 0},
      topAlertNames: topNames,
      mostAlarmingStations: mostAlarming,
      newAlertsPerDay: perDay,
      alertMttrMedianSeconds: mttrMedian,
      alertsOpenOver7d: openOver7,
      availability7d: availabilities7.isEmpty ? null : availabilities7.reduce((a, b) => a + b) / availabilities7.length,
      availability30d: availabilities30.isEmpty ? null : availabilities30.reduce((a, b) => a + b) / availabilities30.length,
      outages7d: outages7,
      outageMttrMedianSeconds: _median(recoveries),
      dataAgeHistogram: ageHist,
      stationsWithErrors: errors,
      fleetMedianYield7d: fleetMedian,
      gridHoursTodayMean: gridHoursList.isEmpty ? null : gridHoursList.reduce((a, b) => a + b) / gridHoursList.length,
      completenessMean7d: completeness.isEmpty ? null : completeness.reduce((a, b) => a + b) / completeness.length,
    );
  }

  /// Hours of grid presence today per station, from device samples.
  Future<Map<int, double>> _gridHoursToday(int nowTs) async {
    final start = AppTime.dayStart(AppTime.today());
    final rows = await db.db.rawQuery('''
      SELECT d.station_id sid, COUNT(*) n,
             SUM(CASE WHEN (s.grid_hz IS NOT NULL AND s.grid_hz > 40) OR (s.grid_v IS NOT NULL AND s.grid_v > 100) THEN 1 ELSE 0 END) g,
             MIN(s.ts) t0, MAX(s.ts) t1
      FROM device_samples s JOIN devices d ON d.device_sn = s.device_sn
      WHERE s.ts >= ? AND s.ts <= ? AND d.station_id IS NOT NULL AND (s.grid_hz IS NOT NULL OR s.grid_v IS NOT NULL)
      GROUP BY d.station_id
    ''', [start, nowTs]);
    final out = <int, double>{};
    for (final r in rows) {
      final n = (r['n'] as num).toInt();
      final g = (r['g'] as num).toInt();
      if (n < 2) continue;
      final span = ((r['t1'] as num) - (r['t0'] as num)).toDouble();
      final cadenceH = span / (n - 1) / 3600;
      out[r['sid'] as int] = g * cadenceH;
    }
    return out;
  }

  static double _availability(List<StatusEvent> events, int from, int to) {
    var down = 0;
    var covered = 0;
    for (final e in events) {
      final s = math.max(e.startTs, from);
      final t = math.min(e.endTs ?? to, to);
      if (t <= s) continue;
      covered += t - s;
      if (e.status.isDown) down += t - s;
    }
    if (covered == 0) return 1;
    return 1 - down / covered;
  }

  static double? _median(List<double> xs) {
    if (xs.isEmpty) return null;
    final s = xs.toList()..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static StationInsight _withPeer(StationInsight i, double? peerMedian) => StationInsight(
        station: i.station,
        latest: i.latest,
        status: i.status,
        statusSince: i.statusSince,
        dataAgeSeconds: i.dataAgeSeconds,
        todayGenKwh: i.todayGenKwh,
        todayConsKwh: i.todayConsKwh,
        todayImportKwh: i.todayImportKwh,
        todayExportKwh: i.todayExportKwh,
        yieldTodaySoFar: i.yieldTodaySoFar,
        yieldLastDay: i.yieldLastDay,
        yield7d: i.yield7d,
        yield30d: i.yield30d,
        peerMedianYield7d: peerMedian,
        performanceRatio7d: i.yield7d == null || peerMedian == null || peerMedian <= 0 ? null : i.yield7d! / peerMedian,
        selfSufficiency7d: i.selfSufficiency7d,
        availability7d: i.availability7d,
        availability30d: i.availability30d,
        outages30d: i.outages30d,
        currentOutage: i.currentOutage,
        activeAlerts: i.activeAlerts,
        highestAlert: i.highestAlert,
        socNow: i.socNow,
        socMinToday: i.socMinToday,
        hoursBelow20Today: i.hoursBelow20Today,
        batteryCyclesProxy7d: i.batteryCyclesProxy7d,
        completeness7d: i.completeness7d,
        daysWithData7d: i.daysWithData7d,
        gridHoursToday: i.gridHoursToday,
        lastError: i.lastError,
      );

  static FleetEnergyDay _sumEnergy(String label, List<(double?, double?, double?, double?, double?, double?)> rows, {FleetEnergyDay? fallback}) {
    var n = 0;
    var g = 0.0, c = 0.0, i = 0.0, e = 0.0, ch = 0.0, dc = 0.0;
    for (final r in rows) {
      if (r.$1 == null && r.$2 == null) continue;
      n++;
      g += r.$1 ?? 0;
      c += r.$2 ?? 0;
      i += r.$3 ?? 0;
      e += r.$4 ?? 0;
      ch += r.$5 ?? 0;
      dc += r.$6 ?? 0;
    }
    if (n == 0 && fallback != null) return fallback;
    return FleetEnergyDay(day: label, stations: n, generationKwh: g, consumptionKwh: c, gridImportKwh: i, gridExportKwh: e, chargeKwh: ch, dischargeKwh: dc);
  }

  static FleetEnergyDay _sumDays(String label, Iterable<FleetEnergyDay> days) {
    var n = 0;
    var g = 0.0, c = 0.0, i = 0.0, e = 0.0, ch = 0.0, dc = 0.0;
    for (final d in days) {
      n = math.max(n, d.stations);
      g += d.generationKwh;
      c += d.consumptionKwh;
      i += d.gridImportKwh;
      e += d.gridExportKwh;
      ch += d.chargeKwh;
      dc += d.dischargeKwh;
    }
    return FleetEnergyDay(day: label, stations: n, generationKwh: g, consumptionKwh: c, gridImportKwh: i, gridExportKwh: e, chargeKwh: ch, dischargeKwh: dc);
  }
}
