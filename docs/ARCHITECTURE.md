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
      school.dart                School, SchoolSolar, SchoolLoads, SchoolEquipment, SchoolEducation, StationSchoolLink
      school_insights.dart       SchoolInsights + SchoolInsight + RegionCoverage + ProgrammeSlice + AttendanceComparison
      school_query.dart          SchoolQuery + SchoolSort: filter/sort the whole school directory
      connectivity_insights.dart ConnectivityInsights + ConnectivityGroup + ConnectivityQuadrant
    db/
      app_database.dart          AppDatabase.open(path) → Database; schema + migrations
      station_dao.dart           stations, station_latest, snapshots, daily/monthly energy, buckets, status events, battery days
      device_dao.dart            devices, device_latest, device_samples
      alert_dao.dart             alerts (upsert keeps ack), counts, lifecycle helpers, MTTR
      sync_dao.dart              sync_log + sync_meta
      school_dao.dart            schools ⋈ school_solar ⋈ school_loads ⋈ school_education, equipment, station_school_links
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
      school_insights_builder.dart programme roll-ups: dataset ⋈ links ⋈ FleetInsights
      connectivity_insights_builder.dart internet roll-out per governorate/district and the solar × internet matrix
    schools/
      school_dataset.dart        SchoolDataset (assets/data/schools.json), SchoolDatasetImporter (once per version)
      station_school_linker.dart StationSchoolLinker: plant → CERD by name (transliteration-folded) + coordinates
    demo/
      demo_deye_api.dart         DemoDeyeApi implements DeyeApi; plants impersonate real solarised schools (DemoSeed)
    providers.dart               Riverpod providers: database, apiClient, syncEngine, settings, streams
    theme.dart                   colours (UNICEF cyan #1CABE2 accent), status palette, text styles
    utils/format.dart            number/energy/power/time formatters (kW, kWh, relative time)
    utils/app_time.dart          Asia/Beirut day helpers (timezone package)
  features/
    shell/app_shell.dart         NavigationRail + content area, sync status bar, offline banner
    dashboard/                   fleet dashboard (KPI tiles, charts, rankings, region table, alarm summary)
    programme/                   solarisation programme dashboard (coverage, funding, audited loads, education, links)
    schools/                     school directory (every MEHE school) and the per-school record page
    connectivity/                internet-connectivity dashboard (coverage, solar × internet matrix, gaps)
    stations/                    schools list (search/filter/sort) and station detail (flow diagram, charts, devices, alerts)
    alarms/                      alarm centre
    map/                         Lebanon map with status markers (flutter_map, OSM tiles, graceful offline)
    settings/                    credentials, region, intervals, retention, export CSV, DB stats, demo toggle
  test/ ...                      unit + widget tests (sqflite_common_ffi in-memory DB)
assets/data/schools.json         bundled MEHE/UNICEF school dataset (built by scripts/build_school_dataset.py)
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

## SQLite schema (v2)

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
| `sync_log`, `sync_meta` | | phase log (last 500) and timing metadata; `schools.*` keys record the imported dataset version |
| `schools` | `cerd` | MEHE public school master record (names EN/AR, governorate/caza normalised to the app's regions, ownership, capacity, coordinates, address, school phone, students AM/PM, enrolment, PM-shift CERD, `connected`) — v2 |
| `school_solar` | `cerd` | UNICEF solar tracker: status, donor/grant + group, project, contractor, consultant, cost, kWp, inverter kW, battery kWh, LED/QA cost, shift, language — v2 |
| `school_loads` | `cerd` | energy audit: annual load per category (kWh/year) — v2 |
| `school_equipment` | `id` (index `cerd`) | energy audit inventory: type, category, W, count, h/day, kWh/year — v2 |
| `school_education` | `cerd` | MEHE education dashboard: attendance rates, risk levels, PM teachers, monthly risk JSON — v2 |
| `station_school_links` | `station_id` | plant → CERD with `method` (manual / cerd / name_location / name / location) and `confidence`; kept across "Clear all data" — v2 |

Schema versions only add tables (`CREATE … IF NOT EXISTS`), so `onUpgrade` simply re-runs the schema
script. The five dataset tables are replaced atomically when the bundled JSON's `version` changes
(`SchoolDatasetImporter`), and are *not* deleted by "Clear all data".

Pragmas: WAL, `synchronous=NORMAL`, `temp_store=MEMORY`, 16 MB cache, 5 s busy timeout.

## School dataset (MEHE / UNICEF workbooks)

`scripts/build_school_dataset.py <dir with the xlsx files>` merges the five workbooks by **CERD
number** (the MEHE school id every file shares) into `assets/data/schools.json` (~1.5 MB, 1,246
schools):

| Workbook | Sheet(s) | What is taken |
|----------|----------|---------------|
| Overview_of_Public_Schools | Public Schools | master list of 1,211 public schools (names, caza, CAS code, ownership, capacity, coordinates, address, school phone, students, enrolment) |
| Connectivity534Schools | Sheet1 | the 534 schools in the internet-connectivity roll-out → `connected` |
| Public_Schools_Solar_Implementation | Solarized Schools, Contractors | solar status, donor/grant, project, cost, kWp, inverter kW, battery kWh, LED/QA cost, shift, language, contractor, consultant |
| Energy_Breakdown | Sheet2 (loads), Sheet1 (inventory) | annual load per category (kWh/year) and the equipment inventory (both kept; the two sheets do not reconcile for most schools, so the inventory is shown as-is and the category sheet is used for totals) |
| EDU_Dashboard_Data | Student Attendance, Student Risk Level, PM Teachers Risk Level, School List | attendance rates, risk levels, PM teachers, teaching days, AM ↔ PM CERD |

Governorates are normalised to the app's nine regions (Keserwan-Jbeil is split out of Mount Lebanon by
caza) and cazas to the geoBoundaries district names used for plants. **Personal data (director names,
personal mobile numbers) is not exported** — the repository is public and the JSON ships inside the APK.

### Plant ↔ school linking

`StationSchoolLinker` runs after every plant-list sync (and from Settings). For each plant without a
manual link it looks for, in order: a CERD number written in the plant name; the best
**weighted token overlap** (IDF-weighted, transliteration folded to consonant skeletons so
*Achrafieh/Ashrafiyeh*, *Msaytbeh/Mousseitbeh*, *Tariq/Tarik* agree; Arabic names normalised too)
between the plant name and the school's English, tracker and Arabic names, combined with the
**distance** between plant and school coordinates (≤ 150 m strong, ≤ 5 km weak); finally a lone school
within 150 m. Close runners-up (schools sharing a compound) block an automatic link, which is then set
by hand on the plant page (search by name or CERD, suggestions shown with confidence and distance).
In demo mode the synthetic plants take the *tracker* names and coordinates of real solarised schools,
so the matcher is exercised end-to-end (tests require 90 %+ recall and zero wrong links).

### Connectivity insights (`ConnectivityInsightsBuilder`)

The connectivity workbook is a **membership list**: 534 schools are on the internet roll-out, with no
bandwidth, provider or uptime column. The builder therefore reports coverage rather than quality:
connected schools and students reached overall, per governorate and per district (SQL aggregates over
`schools`), the four solar × internet combinations with their school and student counts, the share of
solarised schools that also have internet, the districts with the largest absolute gap and the best
served ones, and the monitored plants whose school is not on the list — a solarised school with no
internet has no data path, which is the most common cause of a plant that never reports.

### Programme insights (`SchoolInsightsBuilder`)

Joins the dataset with the links and `FleetInsights`: coverage (public / solarised / pipeline /
connected / solarised + connected / monitored) overall and per governorate, students benefiting,
installed kWp / inverter kW / battery kWh, investment and cost per kWp and per student, slices by
donor group / project / contractor / ownership, audited load by category, expected annual generation
(kWp × specific yield, Settings, default 1,500 kWh/kWp·yr) vs audited load (sizing ratio, undersized
systems), measured 30-day generation/consumption of monitored schools vs the audit (coverage, audit
accuracy), LED share of lighting, top equipment loads, next solarisation candidates by audited load,
plants down at schools without connectivity, attendance comparisons (solarised vs not, connected vs
not, monitored vs not — descriptive only), link statistics and unlinked plants.

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
plants across all governorates, realistic diurnal PV curves, batteries, and alarms, so the whole app
can be exercised without network access. The plants borrow the names, coordinates and system sizes of
real solarised schools from the bundled dataset (`DemoSeed`), so school links, the programme dashboard
and the school profile are populated in demo mode. Toggle in Settings; unit/widget tests use it too.
