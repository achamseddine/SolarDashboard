# UI specification — tablet dashboard

Target: 10–13" Android tablets in landscape (1280×800 up to 2560×1600), also usable on Linux/Windows
desktops. Material 3, `flutter_riverpod` 3, `go_router`, `fl_chart`, `flutter_map`. Everything reads
from Riverpod providers in `lib/core/providers.dart`; **screens never call the API or the DB directly**
except through those providers (the only on-demand network call is `SyncEngine.refreshStation`).

## Shared building blocks (already implemented — reuse, don't duplicate)

* `lib/features/common/widgets.dart` — `SectionCard`, `KpiTile`, `StatusChip`, `DeviceStatusChip`,
  `LevelChip`, `LegendItem`, `AsyncView`, `EmptyState`, `ErrorState`, `TileGrid`, `TwoColumn`,
  `InfoRow`, `PageHeader`, `kPagePadding`, `kGap`.
* `lib/features/common/charts.dart` — `PowerLineChart` (multi-series W over time with legend + tooltip),
  `EnergyBarChart` (daily/monthly kWh, grouped or stacked, ≤ 24 px bars, 4 px rounded caps),
  `SocHistogram`, `DonutChart` (part-to-whole ≤ 6 slices, with centre figure), `SparkLine`,
  `HorizontalBars` (ranking / region comparison, single hue), `ChartTable` (table twin of any chart).
* `lib/core/theme.dart` — `AppColors` (validated palette: `pv`, `load`, `battery`, `gridImport`,
  `gridExport`, status colours, `socRamp`, `sequential`), `buildTheme()`.
* `lib/core/utils/format.dart` — `Fmt.power/energy/capacity/percent/ratio/co2/litres/ago/dateTime/…`.
* `lib/features/shell/` — `AppShell` (NavigationRail), `SyncStatusBar`.

## Data available

* `fleetInsightsProvider` → `FleetInsights` (see `lib/core/models/fleet_insights.dart`): counts, live
  totals over reporting plants, SOC median/histogram, energy today/7d/30d/lifetime, daily + monthly
  series, regions, alarms summary, availability/outages/MTTR, data-age histogram, per-station
  `StationInsight` list with yields, peer median, performance ratio, availability, outage, SOC, alarms.
* `stationDetailProvider(id)` → `StationDetail`: station, latest, devices + `DeviceLatest` map,
  today/yesterday frames, 30-day daily, 12-month monthly, alerts, battery days, status events, insight.
* `schoolInsightsProvider` → `SchoolInsights` (see `lib/core/models/school_insights.dart`): programme
  coverage totals and per governorate, slices by donor/project/contractor/ownership, audited loads,
  expected vs measured generation, education comparisons, link statistics, per-school `SchoolInsight`
  (school record + link + linked `StationInsight`). `schoolProfileProvider(stationId)` → linked school
  with equipment inventory; `linkedSchoolsProvider` → station id → `School`; `linkSuggestionsProvider`;
  `schoolDatasetInfoProvider`.
* `connectivityInsightsProvider` → `ConnectivityInsights`; `schoolDirectoryProvider(SchoolQuery)` →
  filtered/sorted `List<SchoolInsight>` over every school; `schoolRecordProvider(cerd)` → `SchoolRecord`
  (school, equipment, programme insight, link); `cazaOptionsProvider(region)`, `ownershipOptionsProvider`.
* `alertsProvider(AlertFilter)` → `List<SolarAlert>`; `powerBucketsProvider((region, hours))` →
  fleet/region 15-min `PowerBucket`s; `syncStatusProvider`, `syncLogsProvider`, `dbStatsProvider`,
  `settingsProvider`, `credentialsProvider`, `canSyncProvider`, `appLogProvider`, `syncEngineProvider`.

## Screens

### Dashboard (`/dashboard`)
Country-level view for a UNICEF energy officer. Order top → bottom:
1. Header: "School solar fleet — Lebanon", subtitle with `generatedAt`, "now" data range
   (`Fmt.time(dataTsMin)–Fmt.time(dataTsMax)`), reporting plants "n of N".
2. KPI row (stat tiles, `TileGrid`): Schools (total, with online/offline/alarm/stale breakdown hint),
   Generation now (Σ kW, hint "x % of y kWp reporting"), Consumption now, Grid import now / export now,
   Battery (median SOC, charge/discharge), Today's generation (kWh, "as of HH:MM"), Self-sufficiency
   (today, 7 d), CO₂ avoided 30 d (+ diesel litres), Availability 7 d, Active alarms (by level).
3. Two-column: **Fleet power today** (`PowerLineChart` from `powerBucketsProvider(('', 24))`: PV,
   load, import, export; battery as separate small chart or omitted; legend; tooltip) |
   **Status donut** (`DonutChart` of status counts, tap → `/stations?status=`) + data-age histogram
   (`HorizontalBars`).
4. **Energy last 30 days** (`EnergyBarChart` generation vs consumption vs import, daily) and
   **12 months** (`EnergyBarChart` monthly).
5. **Governorates** table (`DataTable`): schools, online %, availability 7 d, kWp, generation now,
   today kWh, median yield 7 d, self-sufficiency 7 d, alarms; row tap → `/stations?region=`.
6. Attention lists side by side (each a `SectionCard` with ≤ 8 rows and "See all" →):
   **Offline / stale** sorted by outage duration; **Under-performers** (performance ratio < 0.5, show
   yield vs peer median); **Low battery** (< 20 %); **Critical alarms**.
7. **Rankings**: top 10 / bottom 10 by 7-day specific yield (`HorizontalBars`, kWh/kWp/day, single hue,
   label completeness < 80 % with a warning icon).
8. **Battery health**: SOC histogram (`SocHistogram`), plants with hours below 20 % today.
9. **Alarms**: active by level, new alarms per day (14 d) bars, top alarm names, most-alarming schools.
10. **Environmental** card: CO₂/diesel today · 30 d · lifetime with the formula and factors in an
    info tooltip ("self-consumed generation × factor").
Every card's numbers must handle null → "–" / "n/a"; use `Fmt`. Pull-to-refresh / refresh button calls
`syncEngineProvider.syncNow()`.

### Schools (`/stations`)
Search field + filter chips row (region dropdown, status chips, "with alarms", "under-performing",
"low SOC") + sort (name, status, generation now, SOC, today kWh, yield 7 d, availability, last update).
`DataTable` (or `PaginatedDataTable`) with: status chip, name (+ governorate/caza), kWp, PV now, load
now, SOC, today kWh, yield 7 d + perf ratio, availability 7 d, alarms, last data (`Fmt.ago`).
Row tap → `/stations/:id`. Show counts "x of y schools". Honour `initialQuery/initialRegion/initialStatus`.
CSV export button of the current rows (`csv` + `share_plus`; on desktop write to a temp file and share).

### School detail (`/stations/:id`)
On open call `ref.read(syncEngineProvider).refreshStation(id)` once. Layout:
* Header: back button, name, status chip, governorate · caza · address, kWp, battery kWh, commissioned,
  grid type, plant id, coordinates, "Refresh" and "Open in map" actions.
* **Power flow** panel (custom painter or simple boxed diagram): PV → (load, battery, grid) with live
  W values and arrows coloured by direction; SOC meter (same-ramp track); data timestamp + age.
* KPI tiles: today generation/consumption/import/export, yield today so far, yield 7 d vs peer median,
  self-sufficiency 7 d, availability 30 d, outages 30 d, hours below 20 % SOC today, grid hours today.
* **School record** (`SchoolProfileCard`): the linked MEHE school (CERD, Arabic name, ownership,
  capacity, students AM/PM, enrolment, address, school phone, connectivity chip), solar tracker data
  (status, donor, project, contractor, consultant, cost, LED/QA cost, tracker kWp/inverter/battery vs
  cloud capacity), audited annual load by category with expected generation, sizing ratio, measured
  30-day generation/consumption, equipment inventory (expandable), education indicators; "Change link"
  opens the school picker (search by name/Arabic name/CERD, automatic suggestions with confidence and
  distance, unlink, re-run matching). Unlinked plants show a "Link to a school" prompt.
* **Today** `PowerLineChart` (frames) with yesterday as gray context line (emphasis form).
* **30-day energy** stacked/grouped `EnergyBarChart`; **12-month** chart; battery `SocHistogram`/30-day
  SOC min-max band (line chart).
* **Devices**: one card per device: type icon, model, serial, status, collection time, key readings
  (`MeasureKeys` groups: PV strings, battery, grid, temperatures, daily counters) + "All readings" table.
* **Alarms** for this plant (`LevelChip`, status, start/end, description, acknowledge).
* **Status history**: timeline of status events (30 d) as horizontal coloured bars.

### Alarms (`/alarms`)
Filter row: status (active/recovered), level, source (cloud/derived), region, days (1/7/30/all),
unacknowledged only, search. Summary tiles (active by level, open > 7 d, median time-to-recovery).
List/table rows: level chip, school (tap → detail), device type/serial, name, description, started
(`Fmt.dateTime` + ago), duration, status, acknowledge button; "Acknowledge all". Show a banner when
`syncStatus.alertsUnsupportedReason != null` explaining cloud alarms are unavailable and derived alarms
still work. Honour `initialStationId`.

### Programme (`/programme`)
Solarisation programme dashboard built from the MEHE/UNICEF dataset joined with the live fleet: KPI
grid (public schools, solarised, pipeline, connected, solar + connected, monitored plants, installed
kWp, investment, students benefiting), coverage by governorate (stacked bars + connectivity share),
solar status donut, funding by donor/project/contractor, audited load by category vs expected and
measured generation (sizing ratio, LED share, top equipment loads), attention lists (solarised but not
monitored, plants down without connectivity, undersized systems, next candidates), measured vs
audited coverage per monitored school, education indicators (attendance comparisons — descriptive
only), plant ↔ school link statistics with the unlinked plants. Every card copes with an empty fleet.

### Plants (`/plants`)
Mirrors the DeyeCloud console overview. KPI strip: real-time generating power, installed capacity,
daily, monthly and total production. Status counters as filter chips (total, online, offline, alarm,
stale, unknown, partial offline, with alerts, no alerts) where "partial offline" means the plant still
reports while some of its devices do not. Paged table (25/50/100/all) of every plant: plant and
location, status, alarms, capacity, power now, today's trend sparkline, daily production, battery,
last data, open. Search over name, id, governorate, district and address. The list never filters by
school linkage or region, so plants with no location and plants that are not schools still appear. A
banner warns when the last sync fetched fewer plants than the cloud reported.

### Schools directory (`/schools`)
Every school in the dataset, not only the monitored plants. Search (name, Arabic name, CERD, district,
cadaster, address), governorate and district dropdowns, ownership dropdown, and chips for internet /
no internet, solarised / not solarised, monitored plant, energy audit and second shift. Sortable table:
school, CERD, governorate, district, internet icon, solar status pill, kWp, students, audited load,
attendance, plant. Row opens the school record; the plant cell opens the plant. CSV export of the
filtered rows.

### School record (`/schools/:cerd`)
One school: chips for internet, solar status, monitoring and second shift; KPI tiles (students,
capacity, kWp, audited load, expected generation, attendance); master-data card; connectivity card with
the governorate's share; solar tracker card; energy audit with the equipment inventory; live plant card
when a plant is linked; education indicators. Works for schools with no plant and no solar record.

### Connectivity (`/connectivity`)
Internet roll-out: connected schools and students reached, coverage per governorate (stacked bars plus
share), the solar × internet matrix as four tiles and a donut, districts with the largest gap and the
best served, and monitored plants at schools without a data path. Every tile deep-links into the
directory with the matching filter.

### Students and teachers (`/education`)
Student attendance per shift (mean over schools and weighted by students), attendance submission
counts, second-shift schools, and the morning/afternoon risk ratings with the unrated remainder made
explicit. Teacher section: headcount, gender split, students per teacher, teaching days, third-party
verification visits, high-risk records, the four per-term attendance-reporting bars and the teacher
risk rating. A governorate card stacks morning-only against second-shift schools and tabulates the
attendance means. Mirrors the MEHE education dashboard; the "10+ days of non-justified absences"
columns are empty in the bundled extract, and the page says so rather than showing a zero.

### Map (`/map`)
`flutter_map` with OSM tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, userAgentPackageName
`org.unicef.unicef_solar_monitor`), centred on Lebanon (33.85, 35.85, zoom 8). Draw governorate outlines
from `boundariesProvider` (`GeoArea.outlines`) as thin polylines. Markers per plant coloured by status
(cluster-free; ≤ 1500 simple circle markers is fine), size by kWp; tap → bottom sheet with key figures
and "Open". Filter chips (status, region). Legend. Handle tile loading failures gracefully (tiles are
optional; the outlines and markers must still render offline). Optional **Public schools** layer: every
school with coordinates as a small marker coloured by solarisation status (solarised without plant,
pipeline, not solarised; connected schools ringed), "Connected only" toggle, tap → school sheet.

### Settings (`/settings`)
Sections: **DeyeCloud account** (App ID, App Secret, e-mail, password *or* SHA-256 hash — explain that
either is accepted —, company id, region EU/US; "Test connection" runs `accountInfo()` and shows the
result; save → `credentialsProvider.save`; note that credentials are stored in the device secure
store), **Demo mode** switch, **School dataset** (version, generated/imported dates, counts, links, sources,
re-import, re-link), **Sync** (auto-sync, poll interval, station/latest interval, alarm
intervals, concurrency, stale threshold, retention days, nightly backfill, "Sync now", "Clear all data"),
**Display** (dark mode, keep screen on, CO₂ and diesel factors, expected PV yield, school hours), **Advanced** (alert
endpoint paths override), **Diagnostics** (sync log table, DB statistics, app log with copy button,
app version). A first-run banner when `!canSync`.

## Conventions

* Tablet landscape first; every screen scrolls vertically only (wide tables inside horizontal
  `SingleChildScrollView`). Minimum tap target 44 px.
* Colours only from `AppColors`; status always with icon/label, never colour alone.
* Charts: thin marks (2 px lines, ≤ 24 px bars), hairline solid grid, legend for ≥ 2 series, tooltips on
  touch, no dual axes, no pies for close values, "table view" toggle via `ChartTable` where feasible.
* Numbers via `Fmt`; times in device local zone (Asia/Beirut on the tablets).
* Riverpod 3: `AsyncValue.value` (not `valueOrNull`), `ref.watch(x.select(...))` for tiles,
  `autoDispose` families for detail screens.
* No `print`; use `debugPrint` sparingly. Keep files < 600 lines: split widgets into
  `lib/features/<feature>/widgets/`.
* `flutter analyze` must be clean (no infos) and existing tests must keep passing.
