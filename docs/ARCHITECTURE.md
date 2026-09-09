# UNICEF Lebanon School Solar Monitor — architecture

Tablet-first Flutter app (landscape, ≥ 8" screens, Android primary; Linux/Windows desktop builds for
office use) that mirrors the whole DeyeCloud fleet into a local SQLite database and renders a live
dashboard from that database. The UI **never** reads the network directly: API → sync engine → SQLite
→ Riverpod providers → widgets. That keeps the dashboard usable offline and makes every screen
testable with seeded data.

```
lib/
  main.dart                      bootstrap: sqflite ffi on desktop, ProviderScope, router
  app.dart                       MaterialApp.router + theme
  core/
    api/
      deye_endpoints.dart        path constants + alert path candidates + region base URLs
      deye_api_client.dart       DeyeApiClient (dio): auth, stations, devices, history, alerts
      deye_api_exception.dart    DeyeApiException(code,msg,httpStatus)
      json_utils.dart            tolerant parsing helpers (asDouble, asInt, asEpochSeconds, asString, firstList)
    models/
      station.dart               Station, StationLatest, StationSnapshot, StationEnergy, StatusEvent, PowerBucket, BatteryDay
      device.dart                Device, DeviceLatest, DeviceReading, DeviceSample, MeasureKeys
      alert.dart                 SolarAlert, AlertLevel, AlertStatus, AlertSource
      sync.dart                  SyncStatus, SyncPhase, SyncLogEntry
      credentials.dart           DeyeCredentials, DeyeRegion
      fleet_insights.dart        FleetInsights + StationInsight + RegionInsight + AlarmInsight
    db/
      app_database.dart          AppDatabase.open(path) → Database; schema + migrations
      station_dao.dart           stations, station_latest, snapshots, daily/monthly energy, buckets, status events, battery days
      device_dao.dart            devices, device_latest, device_samples
      alert_dao.dart             alerts (upsert keeps ack), counts, lifecycle helpers, MTTR
      sync_dao.dart              sync_log + sync_meta
      retention.dart             chunked purge
    settings/
      credential_store.dart      CredentialStore (flutter_secure_storage) + build-time --dart-define seed
      app_settings.dart          AppSettings (shared_preferences): region, poll interval, retention, demo mode, CO2 factor, keep-awake
    sync/
      rate_limiter.dart          simple token-bucket / min-gap limiter with concurrency cap
      sync_engine.dart           SyncEngine: phases, scheduling, circuit breaker, status stream, refreshStation()
      station_status.dart        deriveStationStatus(), DerivedAlertRules, aggregateInverters()
      station_region.dart        9 governorates + districts: point-in-polygon (bundled GeoJSON), keywords, centroids
    insights/
      fleet_insights_builder.dart  pure functions: build FleetInsights from DB snapshots
    demo/
      demo_deye_api.dart         DemoDeyeApi implements DeyeApi with ~60 synthetic Lebanese schools
    providers.dart               Riverpod providers: database, apiClient, syncEngine, settings, streams
    theme.dart                   colours (UNICEF cyan #1CABE2 accent), status palette, text styles
    utils/format.dart            number/energy/power/time formatters (kW, kWh, relative time)
    utils/app_time.dart          Asia/Beirut day helpers (timezone package)
  features/
    shell/app_shell.dart         NavigationRail + content area, sync status bar, offline banner
    dashboard/                   fleet dashboard (KPI tiles, charts, rankings, region table, alarm summary)
    stations/                    schools list (search/filter/sort) and station detail (flow diagram, charts, devices, alerts)
    alarms/                      alarm centre
    map/                         Lebanon map with status markers (flutter_map, OSM tiles, graceful offline)
    settings/                    credentials, region, intervals, retention, export CSV, DB stats, demo toggle
  test/ ...                      unit + widget tests (sqflite_common_ffi in-memory DB)
```

## Data flow

1. **Bootstrap** (`main.dart`): on desktop initialise `sqflite_common_ffi`; open the DB at
   `<app support dir>/unicef_solar.db`; load settings, credentials (secure storage) and the bundled
   Lebanon boundary polygons; start the `SyncEngine` when credentials exist or demo mode is on.
2. **SyncEngine sweep** (timer every `pollInterval` minutes, default 5; also on tap of the status bar).
   Phase order, each phase isolated and logged in `sync_log`:
   * `auth` — `authenticate()` (token cached in secure storage, refreshed at 80 % of its lifetime,
     single-flight re-login on rejection, sweep aborted after two consecutive rejections).
   * `stations` — paginate `/station/list`; resolve governorate + district (point-in-polygon on the
     bundled geoBoundaries GeoJSON, then name/address keywords, then nearest centroid); upsert
     `stations`; rows not seen are **archived**, never deleted. Live values that the list already
     carries (`generationPower`, `batterySOC`, `lastUpdateTime`) seed `station_latest` opportunistically.
   * `devices` (hourly) — `/station/device` in chunks of 20 station ids with inner pagination →
     `devices` (+archive-on-not-seen). Battery nominal capacity is taken from BATTERY devices when reported.
   * `deviceLatest` (every sweep) — `/device/latest` in batches of 10 serials for inverters, batteries and
     meters (≈ N/10 calls). Each result is stored whole in `device_latest` (JSON) and as one narrow
     numeric row in `device_samples` (SOC, battery W/V/°C, PV total + strings, load, grid W/Hz/V,
     inverter °C, Daily* counters). Inverters are aggregated per plant into `station_latest` +
     `station_snapshots` (source `device`) and today's `Daily*` counters become a `station_daily`
     row (source `counter`) for the plant-local day.
   * `status` — pure `deriveStationStatus()` (cloud status → inverter states → freshness from data
     timestamps only; fetch time is never used). Transitions are appended to `station_status_events`
     (never purged) for availability / outage statistics. Derived alarms (`DerivedAlertRules`) are
     opened/closed here: plant offline, device alarm state, alert message, low SOC, battery/inverter
     temperature, PV string fault at midday, no generation at midday, discharging while importing.
   * `latest` (every `stationLatestIntervalMinutes`, default 15) — `/station/latest` per plant, the
     documented source of generation/consumption; newer data wins in `station_latest`, one row per
     distinct data timestamp in `station_snapshots` (source `station`). Per-plant errors are recorded in
     `station_latest.last_error_*` without changing status.
   * `daily` (once per local day) — `/station/history` granularity 2 for *closed* days (last 7, or 31 on
     first run and weekly), positional date fallback for undated rows, today only when counters are
     unavailable (with the "yesterday's bucket after midnight" guard); granularity 3 for the last 24
     months on first run and weekly.
   * `frames` (nightly) — granularity 1 for yesterday for every plant → `station_snapshots` (source
     `history`) + `station_daily.completeness_pct` from the frames' own cadence.
   * `alerts` — cloud alert endpoints are probed strictly (only a successful envelope resolves a path;
     paths can be overridden in Settings → Advanced; re-probed daily). All plants hourly, alarming plants
     every 15 min. Query window = min(oldest active alarm start, now − 24 h) (30 days on first run);
     active cloud alarms inside the window that the cloud no longer returns are marked recovered.
   * `rollup` — 15-minute fleet and per-governorate power buckets (`power_buckets`) recomputed for the
     last 3 h from raw snapshots; `station_battery_daily` (SOC min/max/avg, hours < 20 %, max
     temperature) from device samples; today's completeness.
   * `retention` (daily) — chunked deletes: raw snapshots and device samples older than `retentionDays`
     (default 7, chosen for tablet storage), buckets after 400 days, recovered alarms after a year.
   Systemic failures trip a circuit breaker (10 consecutive transient errors → pause 30 s…5 min with
   exponential back-off, shown in the status bar). A sweep requested while one is running is queued.
3. **Providers** re-query SQLite when the database emits a (debounced) change of the relevant kind.
   Screens never touch the network; `refreshStation()` is the only on-demand call (detail screen).
4. **FleetInsightsBuilder** reads `stations ⋈ station_latest`, `station_daily` sums, status events,
   alarm counts and battery days (all ≤ N rows) and produces `FleetInsights` (pure Dart, unit-tested).

## SQLite schema (v1)

| Table | Key | Purpose / retention |
|-------|-----|---------------------|
| `stations` | `id` | plant master data + derived `connection_status`, `region`, `caza`, `archived`, `last_seen_at` |
| `station_latest` | `station_id` | newest power flow, today's kWh counters, last error — what "now" reads |
| `devices` | `device_sn` | inverters/batteries/loggers, `archived`, `last_seen_at` |
| `device_latest` | `device_sn` | full `dataList` JSON of the newest reading |
| `device_samples` | `(device_sn, ts)` WITHOUT ROWID | whitelisted numeric history; `retentionDays` |
| `station_snapshots` | `(station_id, ts)` WITHOUT ROWID | plant power time series (station/device/history/list sources); `retentionDays` |
| `station_daily` | `(station_id, day)` | kWh per local day, `source` counter/history, `completeness_pct`, `full_power_hours`; kept |
| `station_monthly` | `(station_id, month)` | kWh per month; kept |
| `station_battery_daily` | `(station_id, day)` | SOC min/max/avg, hours below 20 %, temp max; kept |
| `power_buckets` | `(region, bucket_ts)` | 15-min fleet (`region=''`) and governorate sums; 400 days |
| `station_status_events` | `(station_id, start_ts)` | status transitions; kept |
| `alerts` | `id` | cloud (`cloud:<id>`) and derived (`derived:<sn>:<code>`) alarms, `acknowledged`; recovered kept 1 year |
| `sync_log`, `sync_meta` | | phase log (last 500) and timing metadata |

Pragmas: WAL, `synchronous=NORMAL`, `temp_store=MEMORY`, 16 MB cache, 5 s busy timeout.

## Insights computed for the dashboard (all from local DB)

* Fleet status counts (ONLINE / OFFLINE / ALARM / STALE / UNKNOWN), reporting plants and the data
  timestamp range of the "now" figures; data-age histogram; plants with API errors.
* Live totals over **reporting** plants only: Σ generation, load, import, export, charge, discharge,
  median SOC + histogram, installed kWp, **capacity utilisation** = Σ kW / reporting kWp.
* Energy today (from counters), last 7 / 30 complete days, lifetime (monthly rows), 30-day daily series,
  12-month series. **Self-sufficiency** = (consumption − import) / consumption (n/a below 1 kWh);
  **self-consumption** = (generation − export) / generation.
* **Specific yield** kWh/kWp/day for the last complete day, 7 d and 30 d; peer median per governorate
  (≥ 5 peers, else fleet); **performance ratio** = yield7d / peer median; under-performers < 0.5 with ≥ 3
  days of data and not down. Today's yield is shown only as "so far".
* **Availability** (share of time not OFFLINE/STALE) 7 d / 30 d per plant, governorate and fleet; outage
  counts, current outage duration (triage list sorted by duration), median time-to-recovery.
* Battery: SOC now, min today, hours below 20 % today, 7-day equivalent cycles (discharge kWh /
  nominal kWh when known), temperature; low-SOC list.
* Grid (EDL) availability hours today from inverter grid voltage/frequency samples.
* Alarms: active by level, top names, most-alarming plants, new per day (14 d), median MTTR, open > 7 d.
* Environmental: CO₂ avoided and diesel litres avoided from **self-consumed** generation (today / 30 d /
  lifetime), factors configurable (defaults 0.70 kg/kWh, 0.27 L/kWh).
* Data completeness (7-day mean of intraday frame coverage).

## Credentials

Never committed. Entered in Settings (app id, app secret, email, password or SHA-256 hash, company id,
region) and stored with `flutter_secure_storage`. For kiosk builds they can be seeded with
`--dart-define=DEYE_APP_ID=... --dart-define=DEYE_APP_SECRET=... --dart-define=DEYE_EMAIL=...
--dart-define=DEYE_PASSWORD_SHA256=... --dart-define=DEYE_COMPANY_ID=...`; seeded values are copied
into secure storage on first launch and can be overridden in Settings.

## Demo mode

`DemoDeyeApi` implements `DeyeApi` (the abstract interface used by `SyncEngine`) with ~60 synthetic
schools across all governorates, realistic diurnal PV curves, batteries, and alarms, so the whole app
can be exercised without network access. Toggle in Settings; unit/widget tests use it too.
