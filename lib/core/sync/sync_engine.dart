import 'dart:async';
import 'dart:math' as math;

import '../api/deye_api.dart';
import '../api/deye_api_client.dart';
import '../api/deye_api_exception.dart';
import '../api/json_utils.dart';
import '../db/app_database.dart';
import '../models/alert.dart';
import '../models/device.dart';
import '../models/station.dart';
import '../schools/station_school_linker.dart';
import '../models/sync.dart';
import '../settings/app_settings.dart';
import '../utils/app_time.dart';
import 'station_region.dart';
import 'station_status.dart';

/// Thrown to abort a sweep (credentials rejected, engine stopped).
class SyncAborted implements Exception {
  SyncAborted(this.reason);
  final String reason;
  @override
  String toString() => 'SyncAborted: $reason';
}

/// Orchestrates the periodic mirror of DeyeCloud into SQLite.
///
/// Phase order per sweep: auth → stations → devices (hourly) → device latest
/// → status derivation (+ derived alarms) → station latest (slower cadence)
/// → daily energy (once per local day) → intraday backfill (nightly) →
/// alarms → aggregates → housekeeping (daily). Every phase isolates
/// per-item failures; systemic failures trip a circuit breaker that pauses
/// the sweep with exponential back-off.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.apiProvider,
    required this.settingsProvider,
    this.boundaries,
    this.log,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;

  /// Returns the API to use (real client or demo) — evaluated per call so
  /// credential/demo changes take effect on the next sweep.
  final DeyeApi Function() apiProvider;
  final AppSettings Function() settingsProvider;
  final LebanonBoundaries? boundaries;
  final void Function(String message)? log;
  final DateTime Function() _clock;

  final StreamController<SyncStatus> _statusCtl = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();
  Timer? _timer;
  bool _running = false;
  bool _refreshRequested = false;
  bool _stopped = false;
  DateTime? _lastSweepStart;
  int _transientFailures = 0;
  int _breakerTrips = 0;
  final Map<int, int> _stationRefreshAt = {};
  final List<String> _phaseFailures = [];

  /// Failures of the last sweep's phases (empty when everything succeeded).
  List<String> get lastPhaseFailures => List.unmodifiable(_phaseFailures);

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  Stream<SyncStatus> get statusStream => _statusCtl.stream;
  SyncStatus get status => _status;
  bool get isRunning => _running;
  DeyeApi get api => apiProvider();
  AppSettings get settings => settingsProvider();

  // ---------------------------------------------------------------- control

  /// Starts the scheduler: an immediate sweep, then one every poll interval.
  void start() {
    _stopped = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    unawaited(_tick(force: true));
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _statusCtl.close();
  }

  Future<void> _tick({bool force = false}) async {
    if (_stopped || !settings.autoSync && !force) return;
    final last = _lastSweepStart;
    if (!force && last != null && _clock().difference(last) < settings.pollInterval) return;
    await syncNow();
  }

  /// Runs a full sweep now. If one is already running, a follow-up sweep is
  /// queued instead of starting a second one.
  Future<void> syncNow() async {
    if (_running) {
      _refreshRequested = true;
      return;
    }
    _running = true;
    _refreshRequested = false;
    try {
      do {
        _refreshRequested = false;
        await _sweep();
      } while (_refreshRequested && !_stopped);
    } finally {
      _running = false;
    }
  }

  // ------------------------------------------------------------------ sweep

  Future<void> _sweep() async {
    _lastSweepStart = _clock();
    _transientFailures = 0;
    _phaseFailures.clear();
    _emit(_status.copyWith(running: true, phase: SyncPhase.auth, current: 0, total: 0, clearMessage: true, startedAt: _lastSweepStart, clearPaused: true));
    final sweepLog = await db.sync.logStart('sweep', now: _now());
    var ok = true;
    String? failure;
    try {
      await _phase(SyncPhase.auth, () async {
        await api.authenticate();
        return 1;
      });
      await _phase(SyncPhase.stations, _syncStations);
      if (_due('devices.lastSync', const Duration(hours: 1))) {
        await _phase(SyncPhase.devices, _syncDevices, onSuccess: () => _mark('devices.lastSync'));
      }
      if (settings.collectDeviceReadings) {
        await _phase(SyncPhase.deviceLatest, _syncDeviceLatest);
      }
      await _phase(SyncPhase.status, _deriveStatuses);
      if (_due('stationLatest.lastSync', settings.stationLatestInterval) || !settings.collectDeviceReadings) {
        await _phase(SyncPhase.latest, _syncStationLatest, onSuccess: () => _mark('stationLatest.lastSync'));
        // Status may change with fresher station data.
        await _phase(SyncPhase.status, _deriveStatuses);
      }
      final today = AppTime.today();
      if (await db.sync.metaGet('daily.lastDay') != today) {
        await _phase(SyncPhase.daily, () => _syncDaily(today));
      }
      if (settings.backfillFrames) {
        final yesterday = AppTime.addDays(today, -1);
        if (await db.sync.metaGet('frames.lastDay') != yesterday) {
          await _phase(SyncPhase.frames, () => _backfillFrames(yesterday), onSuccess: () => db.sync.metaSet('frames.lastDay', yesterday));
        }
        // First installation: also pull today's frames so the fleet curve is
        // complete from the first sweep instead of growing bucket by bucket.
        if (await db.sync.metaGet('frames.todayDone') == null) {
          await _phase(SyncPhase.frames, () => _backfillFrames(today), onSuccess: () => db.sync.metaSet('frames.todayDone', today));
        }
      }
      await _phase(SyncPhase.alerts, _syncAlerts);
      await _phase(SyncPhase.rollup, _rollup);
      if (await db.sync.metaGet('retention.lastDay') != today) {
        await _phase(SyncPhase.retention, _housekeeping, onSuccess: () => db.sync.metaSet('retention.lastDay', today));
      }
      await db.sync.metaSet('sync.lastSuccess', _now().toString());
    } on SyncAborted catch (e) {
      ok = false;
      failure = e.reason;
      log?.call('Sweep aborted: ${e.reason}');
    } catch (e) {
      ok = false;
      failure = e.toString();
      log?.call('Sweep failed: $e');
    }
    if (ok && _phaseFailures.isNotEmpty) failure = _phaseFailures.join(' · ');
    await db.sync.logFinish(sweepLog, ok: ok && _phaseFailures.isEmpty, message: failure, now: _now());
    final client = api;
    _emit(_status.copyWith(
      running: false,
      phase: ok ? SyncPhase.done : _status.phase,
      // Data was refreshed even when a phase failed; only an aborted sweep is not a success.
      lastSuccessAt: ok ? _clock() : null,
      lastError: failure,
      clearError: failure == null,
      errorCount: ok && _phaseFailures.isEmpty ? _status.errorCount : _status.errorCount + 1,
      requestCount: client.requestCount,
      alertsUnsupportedReason: client.alertsUnsupported ? client.alertsUnsupportedReason : null,
      clearAlertsUnsupported: !client.alertsUnsupported,
      clearPaused: true,
    ));
    db.notifyChanged(DataKind.all);
  }

  /// Runs one phase with logging and error isolation. [body] returns the
  /// number of items processed.
  Future<void> _phase(SyncPhase phase, Future<int> Function() body, {FutureOr<void> Function()? onSuccess}) async {
    if (_stopped) throw SyncAborted('stopped');
    _emit(_status.copyWith(phase: phase, current: 0, total: 0, clearMessage: true, requestCount: api.requestCount));
    final id = await db.sync.logStart(phase.name, now: _now());
    try {
      final items = await body();
      await db.sync.logFinish(id, ok: true, items: items, now: _now());
      if (onSuccess != null) await onSuccess();
    } on SyncAborted {
      await db.sync.logFinish(id, ok: false, message: 'aborted', now: _now());
      rethrow;
    } catch (e) {
      await db.sync.logFinish(id, ok: false, message: e.toString(), now: _now());
      log?.call('Phase ${phase.name} failed: $e');
      _phaseFailures.add('${phase.label}: ${_short(e)}');
      _emit(_status.copyWith(lastError: '${phase.label}: $e', errorCount: _status.errorCount + 1));
      if (e is DeyeApiException && (e.code == 'AUTH_LOCKED' || (e.isAuthError && phase == SyncPhase.auth))) {
        throw SyncAborted('Credentials rejected: ${e.message}');
      }
    }
  }

  // --------------------------------------------------------------- stations

  Future<int> _syncStations() async {
    final client = api;
    final list = await client.listStations();
    // The cloud tells us how many plants the account holds; when the list
    // comes back shorter the fetch was truncated (paging that does not
    // advance, a server-side cap …) and the fleet on screen would be a lie.
    final report = client is DeyeApiClient ? client.lastStationListReport : null;
    final reportedTotal = report?.total;
    final truncated = report?.truncated ?? false;
    final truncation = report?.message('plants');
    if (truncated) {
      log?.call('WARNING: $truncation – plants missing from this sweep are kept, not archived');
    } else if (reportedTotal != null && reportedTotal != list.length) {
      log?.call('WARNING: DeyeCloud reported $reportedTotal plants but only ${list.length} could be parsed');
    }
    _emit(_status.copyWith(truncation: truncation, clearTruncation: truncation == null));
    if (list.isEmpty) {
      log?.call('Station list is empty – nothing archived');
      return 0;
    }
    final resolved = <Station>[];
    for (final s in list) {
      final (region, caza) = LebanonRegions.resolve(name: s.name, address: s.address, lat: s.lat, lng: s.lng, boundaries: boundaries);
      resolved.add(s.copyWith(region: region, caza: caza));
    }
    final now = _now();
    await db.stations.upsertStations(resolved, now: now);
    if (truncated) {
      // Archiving now would hide plants that exist but were not sent.
      log?.call('Archive sweep skipped: the plant list looks truncated');
    } else {
      final archived = await db.stations.archiveNotSeen(resolved.map((s) => s.id).toSet());
      if (archived > 0) log?.call('Archived $archived stations no longer in the account');
    }

    // Opportunistic live values carried by the station list.
    final latest = <StationLatest>[];
    for (final s in resolved) {
      final snap = StationSnapshot.fromApi(s.raw, stationId: s.id, fetchedAt: now, location: s.location, source: SnapshotSource.list);
      if (snap != null && !snap.isEmpty) {
        latest.add(StationLatest(stationId: s.id, dataTs: snap.ts, fetchedAt: now, source: SnapshotSource.list, snapshot: snap));
      }
    }
    if (latest.isNotEmpty) {
      await db.stations.upsertLatest(latest);
      await db.stations.insertSnapshots(latest.map((l) => l.snapshot!).toList());
    }
    await db.sync.metaSet('sync.first', '1');
    _emit(_status.copyWith(current: resolved.length, total: reportedTotal ?? resolved.length, stationsSynced: resolved.length));
    db.notifyChanged(DataKind.stations);
    await linkSchools();
    return resolved.length;
  }

  /// Matches plants to MEHE schools (CERD) using the bundled dataset. Manual
  /// links are kept; failures never break the sweep.
  Future<int> linkSchools() async {
    try {
      final schools = await db.schools.getSchools();
      if (schools.isEmpty) return 0;
      final n = await StationSchoolLinker(schools).linkAll(db, now: _now());
      if (n > 0) log?.call('Linked $n plants to schools');
      return n;
    } catch (e) {
      log?.call('School linking failed: ${_short(e)}');
      return 0;
    }
  }

  // ---------------------------------------------------------------- devices

  Future<int> _syncDevices() async {
    final ids = await db.stations.getStationIds();
    if (ids.isEmpty) return 0;
    final devices = await api.listStationDevices(ids);
    await db.devices.upsertDevices(devices, now: _now());
    if (devices.isNotEmpty) {
      await db.devices.archiveNotSeen(devices.map((d) => d.deviceSn).toSet(), onlyStations: ids.toSet());
    }
    // Battery capacity from BATTERY devices when the plant has none.
    final capByStation = <int, double>{};
    for (final d in devices) {
      final c = d.batteryCapacityKwh;
      if (c != null && d.stationId != null) capByStation[d.stationId!] = (capByStation[d.stationId!] ?? 0) + c;
    }
    if (capByStation.isNotEmpty) {
      final stations = await db.stations.getStations();
      for (final s in stations) {
        if (s.batteryCapacityKwh == null && capByStation.containsKey(s.id)) {
          await db.stations.setBatteryCapacity(s.id, capByStation[s.id]);
        }
      }
    }
    db.notifyChanged(DataKind.devices);
    return devices.length;
  }

  // ----------------------------------------------------------- device latest

  static const _pollableTypes = {'INVERTER', 'MICRO_INVERTER', 'BATTERY', 'METER', 'MECD'};

  Future<int> _syncDeviceLatest() async {
    final devices = await db.devices.allDevices();
    final pollable = devices.where((d) => d.deviceType == null || _pollableTypes.contains(d.deviceType)).toList();
    if (pollable.isEmpty) return 0;
    final stationOf = {for (final d in devices) d.deviceSn: d.stationId};
    final batches = chunked(pollable.map((d) => d.deviceSn).toList(), 10).toList();
    final results = <DeviceLatest>[];
    var done = 0;
    await _forEachConcurrent(batches, (batch) async {
      try {
        final res = await api.deviceLatest(batch, location: AppTime.beirut);
        results.addAll(res);
        _noteSuccess();
      } catch (e) {
        await _noteFailure(e, 'device/latest ${batch.first}…');
      }
      done += batch.length;
      _emit(_status.copyWith(current: done, total: pollable.length, requestCount: api.requestCount));
    });
    if (results.isEmpty) return 0;
    for (var i = 0; i < results.length; i++) {
      if (results[i].stationId == null && stationOf[results[i].deviceSn] != null) {
        results[i] = _withStation(results[i], stationOf[results[i].deviceSn]!);
      }
    }
    final samples = await db.devices.applyLatest(results);

    // Aggregate inverters → plant-level live values and today's counters.
    final byStation = <int, List<DeviceLatest>>{};
    for (final r in results) {
      final sid = r.stationId ?? stationOf[r.deviceSn];
      if (sid != null) byStation.putIfAbsent(sid, () => []).add(r);
    }
    final now = _now();
    final latestRows = <StationLatest>[];
    final snaps = <StationSnapshot>[];
    final dailyRows = <StationEnergy>[];
    final stationLoc = {for (final s in await db.stations.getStations()) s.id: s.location};
    byStation.forEach((sid, list) {
      final (snap, today) = aggregateInverters(sid, list, fetchedAt: now);
      if (snap == null) return;
      latestRows.add(StationLatest(stationId: sid, dataTs: snap.ts, fetchedAt: now, source: SnapshotSource.device, snapshot: snap, today: today));
      snaps.add(snap);
      if (!today.isEmpty) {
        dailyRows.add(StationEnergy(
          stationId: sid,
          period: AppTime.dayOf(snap.ts, stationLoc[sid]),
          generationKwh: today.generationKwh,
          consumptionKwh: today.consumptionKwh,
          gridImportKwh: today.gridImportKwh,
          gridExportKwh: today.gridExportKwh,
          chargeKwh: today.chargeKwh,
          dischargeKwh: today.dischargeKwh,
          source: EnergySource.counter,
        ));
      }
    });
    await db.stations.upsertLatest(latestRows);
    await db.stations.insertSnapshots(snaps);
    await db.stations.upsertDaily(dailyRows);
    db.notifyChanged(DataKind.latest);
    db.notifyChanged(DataKind.daily);
    log?.call('device/latest: ${results.length} devices, $samples new samples, ${latestRows.length} plants aggregated');
    return results.length;
  }

  DeviceLatest _withStation(DeviceLatest d, int stationId) => DeviceLatest(
        deviceSn: d.deviceSn,
        collectionTs: d.collectionTs,
        fetchedAt: d.fetchedAt,
        deviceType: d.deviceType,
        status: d.status,
        stationId: stationId,
        productId: d.productId,
        readings: d.readings,
      );

  // ----------------------------------------------------------------- status

  Future<int> _deriveStatuses() async {
    final now = _now();
    final stations = await db.stations.getStations();
    if (stations.isEmpty) return 0;
    final devices = await db.devices.allDevices();
    final latestDevices = await db.devices.allLatest();
    final latestStations = await db.stations.allLatest();
    final staleAfter = settings.staleAfter;

    final devicesByStation = <int, List<Device>>{};
    for (final d in devices) {
      if (d.stationId != null) devicesByStation.putIfAbsent(d.stationId!, () => []).add(d);
    }
    final updates = <int, (StationStatus, int?)>{};
    final statuses = <int, StationStatus>{};
    for (final s in stations) {
      final devs = devicesByStation[s.id] ?? const [];
      final inverterStates = <DeviceStatus>[];
      int? freshness = s.lastUpdateTs;
      for (final d in devs) {
        final l = latestDevices[d.deviceSn];
        if (d.isInverter || (d.deviceType == null)) {
          inverterStates.add(l?.status != null && l!.status != DeviceStatus.unknown ? l.status : d.status);
        }
        final ts = l?.collectionTs ?? d.collectionTs;
        if (ts != null && (freshness == null || ts > freshness)) freshness = ts;
      }
      final sl = latestStations[s.id];
      if (sl?.dataTs != null && (freshness == null || sl!.dataTs! > freshness)) freshness = sl!.dataTs;
      final status = deriveStationStatus(apiStatus: s.apiStatus, inverterStates: inverterStates, freshnessTs: freshness, now: now, staleAfter: staleAfter);
      updates[s.id] = (status, freshness);
      statuses[s.id] = status;
    }
    await db.stations.updateStatuses(updates);
    final transitions = await db.stations.recordStatuses(statuses, ts: now);
    if (transitions > 0) log?.call('$transitions plant status transitions');

    // Derived alarms.
    final events = await db.stations.currentStatusEvents();
    final derived = <SolarAlert>[];
    for (final s in stations) {
      final devs = devicesByStation[s.id] ?? const [];
      final inv = [for (final d in devs) ?latestDevices[d.deviceSn]];
      final ctx = StationRuleContext(
        station: s,
        status: statuses[s.id]!,
        statusSince: events[s.id]?.startTs,
        inverters: inv,
        latest: latestStations[s.id]?.snapshot,
        now: now,
        staleAfter: staleAfter,
      );
      derived.addAll(DerivedAlertRules.evaluate(ctx));
    }
    final active = await db.alerts.activeDerived();
    final newIds = derived.map((a) => a.id).toSet();
    final toClose = active.keys.where((id) => !newIds.contains(id)).toList();
    // Keep the original start when the alarm already exists.
    final merged = [for (final a in derived) active.containsKey(a.id) ? a.copyWith(endTs: null) : a];
    final inserted = await db.alerts.upsertAlerts(merged);
    await db.alerts.markRecovered(toClose, endTs: now);
    if (inserted > 0 || toClose.isNotEmpty) log?.call('Derived alarms: $inserted new, ${toClose.length} cleared');
    db.notifyChanged(DataKind.stations);
    db.notifyChanged(DataKind.alerts);
    _emit(_status.copyWith(current: stations.length, total: stations.length));
    return stations.length;
  }

  // ---------------------------------------------------------- station latest

  Future<int> _syncStationLatest() async {
    final stations = await db.stations.getStations();
    if (stations.isEmpty) return 0;
    final now = _now();
    final rows = <StationLatest>[];
    final snaps = <StationSnapshot>[];
    var done = 0;
    var okCount = 0;
    await _forEachConcurrent(stations, (s) async {
      try {
        final res = await api.stationLatest(s.id, location: s.location);
        final snap = res.snapshot;
        if (snap != null && !snap.isEmpty) {
          rows.add(StationLatest(stationId: s.id, dataTs: snap.ts, fetchedAt: now, source: SnapshotSource.station, snapshot: snap, raw: res.raw));
          snaps.add(snap);
          okCount++;
        } else {
          rows.add(StationLatest(stationId: s.id, fetchedAt: now, source: SnapshotSource.station, lastErrorAt: now, lastErrorMsg: 'No data timestamp in station/latest', raw: res.raw));
        }
        _noteSuccess();
      } catch (e) {
        await _noteFailure(e, 'station/latest ${s.id}');
        await db.stations.recordError(s.id, e.toString(), now: now);
      }
      done++;
      if (done % 25 == 0 || done == stations.length) {
        _emit(_status.copyWith(current: done, total: stations.length, requestCount: api.requestCount));
      }
    });
    await db.stations.upsertLatest(rows);
    final written = await db.stations.insertSnapshots(snaps);
    log?.call('station/latest: $okCount/${stations.length} plants, $written new snapshots');
    db.notifyChanged(DataKind.latest);
    return okCount;
  }

  // ------------------------------------------------------------------ daily

  Future<int> _syncDaily(String today) async {
    final stations = await db.stations.getStations();
    if (stations.isEmpty) return 0;
    final latest = await db.stations.allLatest();
    final firstRun = await db.sync.metaGet('daily.firstDone') != '1';
    final fullDue = firstRun || _dueDay('daily.lastFull', 7);
    final monthlyDue = firstRun || _dueDay('monthly.lastSync', 7);
    final nowTs = _now();
    var ok = 0;
    var done = 0;
    await _forEachConcurrent(stations, (s) async {
      try {
        final loc = s.location;
        final localToday = AppTime.today(loc);
        final start = AppTime.addDays(localToday, fullDue ? -31 : -7);
        // Closed days only (endAt is exclusive).
        final rows = await api.stationDaily(s.id, start, localToday, location: loc);
        final have = await db.stations.daysWithHistory(s.id, start, localToday);
        final fresh = rows.where((r) => r.period.compareTo(localToday) < 0 && (!have.contains(r.period) || fullDue)).toList();
        if (fresh.isNotEmpty) await db.stations.upsertDaily(fresh);

        // Today via history only when the counters are unavailable.
        if (latest[s.id]?.today.isEmpty ?? true) {
          final todayRows = await api.stationDaily(s.id, localToday, AppTime.addDays(localToday, 1), location: loc);
          final t = todayRows.where((r) => r.period == localToday).firstOrNull;
          if (t != null) {
            final yesterday = rows.where((r) => r.period == AppTime.addDays(localToday, -1)).firstOrNull;
            final sinceMidnight = nowTs - AppTime.dayStart(localToday, loc);
            final suspicious = yesterday != null && sinceMidnight < 2 * 3600 && t.looksLike(yesterday);
            if (!suspicious) await db.stations.upsertDaily([t]);
          }
        }
        if (monthlyDue) {
          final thisMonth = AppTime.formatMonth(AppTime.now(loc));
          final months = await api.stationMonthly(s.id, AppTime.addMonths(thisMonth, -23), thisMonth);
          await db.stations.upsertMonthly(months);
        }
        ok++;
        _noteSuccess();
      } catch (e) {
        await _noteFailure(e, 'history ${s.id}');
      }
      done++;
      if (done % 10 == 0 || done == stations.length) {
        _emit(_status.copyWith(current: done, total: stations.length, requestCount: api.requestCount));
      }
    });
    if (ok >= stations.length * 0.9) {
      await db.sync.metaSet('daily.lastDay', today);
      await db.sync.metaSet('daily.firstDone', '1');
      if (fullDue) await db.sync.metaSet('daily.lastFull', today);
      if (monthlyDue) await db.sync.metaSet('monthly.lastSync', today);
    }
    db.notifyChanged(DataKind.daily);
    return ok;
  }

  // ------------------------------------------------------------- backfill

  Future<int> _backfillFrames(String day) async {
    final stations = await db.stations.getStations();
    if (stations.isEmpty) return 0;
    var ok = 0;
    var done = 0;
    final completeness = <int, double>{};
    await _forEachConcurrent(stations, (s) async {
      try {
        final frames = await api.stationFrames(s.id, day, location: s.location);
        await db.stations.insertSnapshots(frames);
        completeness[s.id] = frameCompleteness(frames.map((f) => f.ts).toList());
        ok++;
        _noteSuccess();
      } catch (e) {
        await _noteFailure(e, 'frames ${s.id}');
      }
      done++;
      if (done % 10 == 0 || done == stations.length) {
        _emit(_status.copyWith(current: done, total: stations.length, requestCount: api.requestCount));
      }
    });
    await db.stations.updateCompleteness(completeness, day);
    db.notifyChanged(DataKind.latest);
    return ok;
  }

  /// Share (0–100) of a day covered by frames, judged from their own cadence.
  static double frameCompleteness(List<int> timestamps) {
    if (timestamps.length < 2) return timestamps.isEmpty ? 0 : 1;
    final ts = timestamps.toList()..sort();
    final gaps = <int>[for (var i = 1; i < ts.length; i++) ts[i] - ts[i - 1]]..sort();
    final cadence = math.max(60, gaps[gaps.length ~/ 2]);
    final expected = 86400 / cadence;
    return (ts.length / expected * 100).clamp(0, 100).toDouble();
  }

  /// Fetches today's (and optionally yesterday's) frames of one plant —
  /// used by the station detail screen.
  Future<void> backfillStationFrames(int stationId, {bool includeYesterday = true}) async {
    final s = await db.stations.getStation(stationId);
    if (s == null) return;
    final today = AppTime.today(s.location);
    final days = [today, if (includeYesterday) AppTime.addDays(today, -1)];
    for (final day in days) {
      try {
        final frames = await api.stationFrames(stationId, day, location: s.location);
        await db.stations.insertSnapshots(frames);
      } catch (e) {
        log?.call('frames $stationId $day: $e');
      }
    }
    db.notifyChanged(DataKind.latest);
  }

  // ----------------------------------------------------------------- alerts

  Future<int> _syncAlerts() async {
    final client = api;
    if (client.alertsUnsupported) {
      if (client is DeyeApiClient && _dueDay('alerts.lastProbe', 1)) {
        client.resetAlertProbe(stationPath: settings.alertStationPath, devicePath: settings.alertDevicePath);
        await db.sync.metaSet('alerts.lastProbe', AppTime.today());
      } else {
        _emit(_status.copyWith(alertsUnsupportedReason: client.alertsUnsupportedReason));
        return 0;
      }
    }
    final stations = await db.stations.getStations();
    if (stations.isEmpty) return 0;
    final fleetDue = _due('alerts.fleetLastSync', settings.alertFleetInterval);
    final firstRun = await db.sync.metaGet('alerts.firstDone') != '1';
    final now = _now();
    List<Station> targets;
    if (fleetDue || firstRun) {
      targets = stations;
    } else {
      final alarming = await db.alerts.activeCountPerStation();
      targets = stations.where((s) => s.status == StationStatus.alarm || alarming.containsKey(s.id)).toList();
      if (targets.isEmpty || !_due('alerts.lastSync', settings.alertInterval)) return 0;
    }
    final oldest = await db.alerts.oldestActiveStartPerStation();
    var ok = 0;
    var done = 0;
    var newCount = 0;
    var unsupported = false;
    await _forEachConcurrent(targets, (s) async {
      if (unsupported) return;
      try {
        final window = firstRun ? now - 30 * 86400 : now - 86400;
        final from = math.min(window, oldest[s.id] ?? window);
        final alerts = await api.stationAlerts(s.id, from: from, to: now, stationName: s.name, location: s.location);
        newCount += await db.alerts.upsertAlerts(alerts);
        // Lifecycle: active cloud alarms inside the window that the cloud no
        // longer reports are considered recovered.
        final active = await db.alerts.activeForStation(s.id, source: AlertSource.cloud);
        final returned = alerts.map((a) => a.id).toSet();
        final gone = [
          for (final a in active)
            if (!returned.contains(a.id) && (a.startTs ?? a.firstSeenAt) >= from) a.id,
        ];
        await db.alerts.markRecovered(gone, endTs: now);
        ok++;
        _noteSuccess();
      } on DeyeApiException catch (e) {
        if (e.code == 'ALERTS_UNSUPPORTED' || api.alertsUnsupported) {
          unsupported = true;
          _emit(_status.copyWith(alertsUnsupportedReason: api.alertsUnsupportedReason ?? e.message));
          return;
        }
        await _noteFailure(e, 'alerts ${s.id}');
      } catch (e) {
        await _noteFailure(e, 'alerts ${s.id}');
      }
      done++;
      if (done % 10 == 0 || done == targets.length) {
        _emit(_status.copyWith(current: done, total: targets.length, requestCount: api.requestCount));
      }
    });
    if (!unsupported) {
      await _mark('alerts.lastSync');
      if (fleetDue || firstRun) await _mark('alerts.fleetLastSync');
      if (ok >= targets.length * 0.9) await db.sync.metaSet('alerts.firstDone', '1');
    }
    if (newCount > 0) log?.call('$newCount new cloud alarms');
    db.notifyChanged(DataKind.alerts);
    return ok;
  }

  // ----------------------------------------------------------------- rollup

  Future<int> _rollup() async {
    final now = _now();
    // Recompute the buckets of the current local day (covers backfilled frames)
    // and at least the last three hours.
    final from = math.min(now - 3 * 3600, AppTime.dayStart(AppTime.today()));
    final rows = await db.db.rawQuery('''
      SELECT b, COALESCE(s.region, '') AS region, COUNT(*) n,
             SUM(g) g, SUM(c) c, SUM(gi) gi, SUM(ge) ge, SUM(ch) ch, SUM(dc) dc, AVG(soc) soc
      FROM (
        SELECT (ts / 900) * 900 AS b, station_id,
               AVG(generation_w) g, AVG(consumption_w) c, AVG(grid_import_w) gi, AVG(grid_export_w) ge,
               AVG(charge_w) ch, AVG(discharge_w) dc, AVG(battery_soc) soc
        FROM station_snapshots WHERE ts >= ? AND ts <= ? GROUP BY b, station_id
      ) x JOIN stations s ON s.id = x.station_id AND s.archived = 0
      GROUP BY b, region ORDER BY b
    ''', [from, now]);
    final buckets = <PowerBucket>[];
    final fleet = <int, PowerBucket>{};
    for (final r in rows) {
      final b = PowerBucket(
        bucketTs: asInt(r['b']) ?? 0,
        region: (r['region'] as String?) ?? '',
        stationsReporting: asInt(r['n']) ?? 0,
        generationW: asDouble(r['g']) ?? 0,
        consumptionW: asDouble(r['c']) ?? 0,
        gridImportW: asDouble(r['gi']) ?? 0,
        gridExportW: asDouble(r['ge']) ?? 0,
        chargeW: asDouble(r['ch']) ?? 0,
        dischargeW: asDouble(r['dc']) ?? 0,
        avgSoc: asDouble(r['soc']),
      );
      if (b.region.isNotEmpty) buckets.add(b);
      final f = fleet[b.bucketTs];
      final n = b.stationsReporting;
      fleet[b.bucketTs] = PowerBucket(
        bucketTs: b.bucketTs,
        stationsReporting: (f?.stationsReporting ?? 0) + n,
        generationW: (f?.generationW ?? 0) + b.generationW,
        consumptionW: (f?.consumptionW ?? 0) + b.consumptionW,
        gridImportW: (f?.gridImportW ?? 0) + b.gridImportW,
        gridExportW: (f?.gridExportW ?? 0) + b.gridExportW,
        chargeW: (f?.chargeW ?? 0) + b.chargeW,
        dischargeW: (f?.dischargeW ?? 0) + b.dischargeW,
        avgSoc: b.avgSoc == null
            ? f?.avgSoc
            : ((f?.avgSoc ?? b.avgSoc!) * (f?.stationsReporting ?? 0) + b.avgSoc! * n) / ((f?.stationsReporting ?? 0) + n),
      );
    }
    buckets.addAll(fleet.values);
    await db.stations.upsertBuckets(buckets);

    // Battery daily statistics for today (and yesterday right after midnight).
    final today = AppTime.today();
    final days = [today, if (AppTime.now().hour < 3) AppTime.addDays(today, -1)];
    for (final day in days) {
      await _batteryDay(day);
    }
    // Today's completeness from snapshot counts.
    final dayStart = AppTime.dayStart(today);
    final elapsedMin = math.max(1, (now - dayStart) ~/ 60);
    final counts = await db.stations.snapshotCounts(dayStart, now);
    final expected = math.max(1, elapsedMin / 10);
    await db.stations.updateCompleteness({for (final e in counts.entries) e.key: (e.value / expected * 100).clamp(0, 100).toDouble()}, today);
    db.notifyChanged(DataKind.buckets);
    return buckets.length;
  }

  Future<void> _batteryDay(String day) async {
    final start = AppTime.dayStart(day);
    final end = AppTime.dayEnd(day) - 1;
    final rows = await db.db.rawQuery('''
      SELECT d.station_id sid, s.device_sn sn, MIN(s.soc) mn, MAX(s.soc) mx, AVG(s.soc) av, MAX(s.battery_temp) tmax,
             COUNT(s.soc) n, SUM(CASE WHEN s.soc < 20 THEN 1 ELSE 0 END) low,
             MIN(s.ts) t0, MAX(s.ts) t1
      FROM device_samples s JOIN devices d ON d.device_sn = s.device_sn
      WHERE s.ts >= ? AND s.ts <= ? AND d.station_id IS NOT NULL AND s.soc IS NOT NULL
      GROUP BY d.station_id, s.device_sn
    ''', [start, end]);
    if (rows.isEmpty) return;
    final byStation = <int, List<Map<String, Object?>>>{};
    for (final r in rows) {
      byStation.putIfAbsent(r['sid'] as int, () => []).add(r);
    }
    final energy = await db.stations.dailyForDay(day);
    final out = <BatteryDay>[];
    byStation.forEach((sid, devs) {
      double? mn, mx;
      var av = 0.0, hoursLow = 0.0, n = 0;
      double? tmax;
      for (final d in devs) {
        final dmn = asDouble(d['mn']), dmx = asDouble(d['mx']), dav = asDouble(d['av']);
        final cnt = asInt(d['n']) ?? 0;
        final low = asInt(d['low']) ?? 0;
        final span = (asInt(d['t1']) ?? 0) - (asInt(d['t0']) ?? 0);
        final cadenceH = cnt > 1 ? span / (cnt - 1) / 3600 : 0.0;
        if (dmn != null && (mn == null || dmn < mn)) mn = dmn;
        if (dmx != null && (mx == null || dmx > mx)) mx = dmx;
        if (dav != null) {
          av += dav * cnt;
          n += cnt;
        }
        hoursLow = math.max(hoursLow, low * cadenceH);
        final t = asDouble(d['tmax']);
        if (t != null && (tmax == null || t > tmax)) tmax = t;
      }
      out.add(BatteryDay(
        stationId: sid,
        day: day,
        socMin: mn,
        socMax: mx,
        socAvg: n == 0 ? null : av / n,
        hoursBelow20: hoursLow,
        tempMax: tmax,
        chargeKwh: energy[sid]?.chargeKwh,
        dischargeKwh: energy[sid]?.dischargeKwh,
        samples: n,
      ));
    });
    await db.stations.upsertBatteryDays(out);
  }

  // ----------------------------------------------------------- housekeeping

  Future<int> _housekeeping() async {
    final deleted = await db.retention.purge(snapshotDays: settings.retentionDays, now: _now());
    await db.retention.optimise();
    log?.call('Housekeeping removed $deleted rows');
    return deleted;
  }

  // ----------------------------------------------------- targeted refresh

  /// Refreshes one plant (live values, its devices, today's frames and
  /// alarms). Throttled to once per 2 minutes per plant.
  Future<void> refreshStation(int stationId, {bool force = false}) async {
    final now = _now();
    if (!force && now - (_stationRefreshAt[stationId] ?? 0) < 120) return;
    _stationRefreshAt[stationId] = now;
    final s = await db.stations.getStation(stationId);
    if (s == null) return;
    try {
      await api.authenticate();
      final res = await api.stationLatest(stationId, location: s.location);
      if (res.snapshot != null && !res.snapshot!.isEmpty) {
        await db.stations.upsertLatest([StationLatest(stationId: stationId, dataTs: res.snapshot!.ts, fetchedAt: now, source: SnapshotSource.station, snapshot: res.snapshot, raw: res.raw)]);
        await db.stations.insertSnapshots([res.snapshot!]);
      }
      final devices = (await db.devices.devicesForStation(stationId)).where((d) => d.deviceType == null || _pollableTypes.contains(d.deviceType)).toList();
      if (devices.isNotEmpty) {
        final latest = await api.deviceLatest(devices.map((d) => d.deviceSn).toList(), location: s.location);
        await db.devices.applyLatest([for (final l in latest) l.stationId == null ? _withStation(l, stationId) : l]);
      }
      await backfillStationFrames(stationId, includeYesterday: false);
      if (!api.alertsUnsupported) {
        try {
          final alerts = await api.stationAlerts(stationId, from: now - 7 * 86400, to: now, stationName: s.name, location: s.location);
          await db.alerts.upsertAlerts(alerts);
        } catch (e) {
          log?.call('alerts $stationId: $e');
        }
      }
    } catch (e) {
      log?.call('refreshStation $stationId: $e');
      await db.stations.recordError(stationId, e.toString(), now: now);
    }
    db.notifyChanged(DataKind.latest);
    db.notifyChanged(DataKind.alerts);
  }

  // -------------------------------------------------------------- helpers

  Future<void> _forEachConcurrent<T>(List<T> items, Future<void> Function(T) fn) async {
    final concurrency = math.max(1, settings.maxConcurrentRequests);
    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (_stopped) throw SyncAborted('stopped');
        final i = index++;
        if (i >= items.length) return;
        await fn(items[i]);
      }
    }

    await Future.wait([for (var w = 0; w < math.min(concurrency, items.length); w++) worker()]);
  }

  void _noteSuccess() {
    _transientFailures = 0;
  }

  /// Per-item failure accounting + circuit breaker.
  Future<void> _noteFailure(Object e, String what) async {
    log?.call('$what: $e');
    if (e is DeyeApiException) {
      if (e.code == 'AUTH_LOCKED') throw SyncAborted('Credentials rejected: ${e.message}');
      if (e.isRateLimited || e.isServerError || e.isNetworkError) {
        _transientFailures++;
        if (_transientFailures >= 10) {
          _transientFailures = 0;
          _breakerTrips++;
          final pause = Duration(seconds: math.min(300, 30 * math.pow(2, _breakerTrips - 1).toInt()));
          final until = _clock().add(pause);
          log?.call('Circuit breaker: pausing ${pause.inSeconds}s after repeated API failures');
          _emit(_status.copyWith(phase: SyncPhase.paused, pausedUntil: until, message: 'API failing – paused ${pause.inSeconds}s'));
          await Future<void>.delayed(pause);
          _emit(_status.copyWith(clearPaused: true, clearMessage: true));
        }
        return;
      }
    }
    _emit(_status.copyWith(errorCount: _status.errorCount + 1));
  }

  bool _due(String key, Duration every) {
    final v = _metaCache[key];
    if (v == null) return true;
    return _now() - v >= every.inSeconds;
  }

  bool _dueDay(String key, int days) {
    final v = _metaDayCache[key];
    if (v == null) return true;
    final d = DateTime.tryParse(v);
    return d == null || _clock().difference(d).inDays >= days;
  }

  final Map<String, int> _metaCache = {};
  final Map<String, String> _metaDayCache = {};

  Future<void> _mark(String key) async {
    _metaCache[key] = _now();
    await db.sync.metaSet(key, _now().toString());
  }

  /// Loads persisted timing metadata (call once after opening the DB).
  Future<void> loadMeta() async {
    for (final k in ['devices.lastSync', 'stationLatest.lastSync', 'alerts.lastSync', 'alerts.fleetLastSync']) {
      final v = int.tryParse(await db.sync.metaGet(k) ?? '');
      if (v != null) _metaCache[k] = v;
    }
    for (final k in ['daily.lastFull', 'monthly.lastSync', 'alerts.lastProbe']) {
      final v = await db.sync.metaGet(k);
      if (v != null) _metaDayCache[k] = v;
    }
    final last = int.tryParse(await db.sync.metaGet('sync.lastSuccess') ?? '');
    if (last != null) {
      _emit(_status.copyWith(lastSuccessAt: DateTime.fromMillisecondsSinceEpoch(last * 1000)));
    }
  }

  void _emit(SyncStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  int _now() => _clock().millisecondsSinceEpoch ~/ 1000;
}
