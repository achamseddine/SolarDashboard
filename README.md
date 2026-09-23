# UNICEF Lebanon — School Solar Monitor

Tablet application (Flutter + SQLite) that mirrors every school solar plant registered in the
UNICEF DeyeCloud account into a local database and renders a real-time, country-wide monitoring
dashboard: plant status, alarms, live power flow, energy history, battery health, availability,
governorate roll-ups, rankings and environmental impact — all readable offline once synced.

* **Source of data**: DeyeCloud Open API v1 (`https://eu1-developer.deyecloud.com/v1.0`), see
  [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md).
* **Architecture**: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (sync engine, schema, insights).
* **Screens**: [`docs/UI_SPEC.md`](docs/UI_SPEC.md).

## Features

| Area | What you get |
|------|--------------|
| Landing dashboard | fleet-wide power generation and consumption (now, today, 7 d, 30 d, lifetime), carbon footprint avoided with diesel equivalent, generation-vs-consumption curve, energy balance, carbon by month, fleet health, generation by governorate |
| Schools directory | every school in the MEHE master list (1,211 public schools, 1,246 records), searchable and filterable by governorate, district, ownership, internet connectivity, solar status, monitored plant, energy audit and second shift; sortable table with CERD, internet, solar, kWp, students, audited load and attendance; CSV export |
| School record | one page per school whether or not it has a plant: master data (Arabic name, ownership, cadaster, CAS code, address, phone, students AM/PM, capacity, coordinates), internet-connectivity status in the context of its governorate, solar tracker record, energy audit with the equipment inventory, live plant figures when linked, and education indicators |
| Connectivity → network | live school-network monitoring from the GWN Cloud account, against the School Digital Infrastructure & Adoption indicator framework: executive headline indicators, infrastructure health (gateway, switches, APs, PoE and LAN ports, firmware), internet reliability, Wi-Fi and device usage, traffic by SSID, regularity of use, the Technology Adoption Index with its components, the infrastructure × adoption matrix, and a per-school table filterable by quadrant |
| Connectivity | internet roll-out dashboard: connected schools and students reached, coverage per governorate, the solar × internet matrix (solar + internet, solar only, internet only, neither), districts with the largest gap and the best served, and the monitored plants sitting at schools without a data path |
| Programme | solarisation programme dashboard from the MEHE/UNICEF workbooks: public schools vs solarised vs connected vs monitored (overall and per governorate), pipeline, students benefiting, installed kWp, investment and cost per kWp, funding by donor/project/contractor, audited annual loads by category vs expected and measured generation, undersized systems, next candidates, LED share, education indicators, plant ↔ school link status |
| Students and teachers | education dashboard from the MEHE extract: attendance by shift (mean and weighted by students), risk ratings, afternoon-shift teaching staff with the gender split, per-term attendance reporting, students per teacher, teaching days, third-party verification visits, and a governorate breakdown |
| Analytics | schools online/offline/alarm/stale, live PV / load / grid / battery totals, capacity utilisation, today's and 30-day energy, self-sufficiency, availability, CO₂ and diesel avoided, governorate table, attention lists (offline, under-performing, low battery, critical alarms), top/bottom yield rankings, SOC histogram, alarm trends |
| Plants | DeyeCloud-style overview of the whole account: real-time generating power, installed capacity, daily, monthly and total production, status counters (online, offline, alarm, stale, partial offline, with and without alerts) as one-tap filters, and a paged table of every plant with its status, alarms, capacity, power now, today's trend, daily production, battery and last data — every plant in the account, whether or not it is linked to a school or has a governorate |
| Plant list | searchable, filterable, sortable table of every plant with live values, 7-day specific yield vs governorate peers, availability, alarms, last data, linked CERD, internet connectivity and donor; CSV export |
| School detail | live power-flow diagram, today's power curve (yesterday as context), 30-day / 12-month energy, battery SOC history, every inverter/battery reading, alarms, status history, plus the linked MEHE school record (students, ownership, connectivity, solar tracker data, audited loads and equipment inventory vs measured generation, attendance and risk) with a manual link picker |
| Alarms | cloud alarms (DeyeCloud alert list) plus locally derived alarms (plant offline, device alarm state, alert messages, low SOC, over-temperature, PV string fault, no midday generation), acknowledge, filters, MTTR |
| Map | Lebanon map with governorate outlines and status-coloured markers per plant, plus an optional layer of all public schools coloured by solarisation status and connectivity |
| Settings | DeyeCloud credentials (secure storage), demo mode, school dataset (version, counts, re-import, re-link), sync cadence, retention, factors, diagnostics (sync log, DB stats, app log) |

Everything is stored locally in SQLite (`unicef_solar.db`): plant master data, live values,
per-plant power time series, per-device samples, daily/monthly energy, battery statistics, status
transitions, alarms, the sync log, the school dataset (MEHE master list, connectivity, solar tracker,
energy audit, education indicators) and the plant ↔ school links. Retention of raw time series is configurable (default 7 days);
daily/monthly energy and status history are kept indefinitely.

## Getting started

Requirements: Flutter 3.47 / Dart 3.13, Android SDK (API 24+) for tablets, or a Linux/Windows
desktop toolchain for desktop builds.

```bash
flutter pub get
flutter test                 # unit + widget tests (uses an in-memory SQLite and the demo API)
flutter run -d <tablet>      # or: flutter run -d linux
flutter build apk --release  # Android tablet package
```

Notes:
* Windows desktop builds need `sqlite3.dll` next to the executable (or add the
  `sqlite3_flutter_libs` package, which downloads SQLite at build time). Linux uses the system
  `libsqlite3`; Android uses the bundled sqflite plugin.
* If Material icons ever render as boxes after an incremental build, run `flutter clean` first (the
  icon-font subset is regenerated on a clean build) or pass `--no-tree-shake-icons`.
* The CI workflow in `.github/workflows/ci.yml` runs analyzer + tests and uploads a release APK.

## Installing on a tablet

Download the APK from the [latest release](../../releases/latest): `unicef-school-solar-arm64.apk`
for a modern 64-bit tablet, `unicef-school-solar-armv7.apk` for an older 32-bit one, or the larger
universal `unicef-school-solar.apk` if you are not sure which. Android 7.0 (API 24) or newer, with
"install unknown apps" allowed for the browser or file manager you install from.

If Android refuses with **"App not installed"**, the copy already on the tablet was signed with a
different key than the new APK. Uninstall the old copy and install again. That clears the local
cache and the stored DeyeCloud credentials, so re-enter them in Settings afterwards; nothing is
lost, as the fleet history is re-synced from the cloud.

## School network monitoring (GWN Cloud)

The Connectivity page carries five tabs. **Roll-out** is the MEHE membership list — which schools are
on the connectivity programme. The other four are live telemetry from the GWN Cloud account that
manages the school LANs, computed against the *School Digital Infrastructure & Adoption* indicator
framework.

Configure the account in **Settings → GWN Cloud account** (App ID and Secret Key), or seed it at
build time:

```bash
flutter build apk --release \
  --dart-define=GWN_APP_ID=... --dart-define=GWN_SECRET_KEY=... --dart-define=GWN_BASE_URL=https://www.gwn.cloud
```

Credentials go to the platform secure store, never to the database or this repository.

### What the framework asks for, and what this build can answer

| Family | Computed here | Needs another source |
|--------|---------------|----------------------|
| Infrastructure health | gateway, switch and AP availability, AP uptime, PoE and LAN port faults, switch CPU/memory, firmware compliance | configuration compliance (needs a VLAN/SSID/firewall baseline) |
| Internet & performance | availability, uptime, downtime, days since last outage | download/upload speed, latency, packet loss, jitter, contracted bandwidth, ISP SLA |
| Wi-Fi & device usage | active and peak clients, daily unique devices, traffic volume, traffic by SSID, active AP footprint | — |
| Technology adoption | school days with activity, regular use, usage growth, teaching-hours share, under-used and high-adoption flags | — |
| Digital learning | — | Madristi / Learning Passport platform analytics |
| Support & maintenance | open alarms, critical incidents | helpdesk tickets, mean time to repair, repeat faults |
| Power & resilience | — | UPS telemetry where SNMP is installed |

The **Technology Adoption Index** uses the framework's weights, but scores only the components the
app actually has — infrastructure availability, internet reliability, Wi-Fi utilisation and
regularity of use, 60 % of the total weight — and renormalises over them. The page states that share
and names each missing component with the source that would fill it, so a school is never marked
down for data nobody collected. The index is shown with its components, as the framework asks,
because it is a diagnostic rather than a ranking.

The **infrastructure × adoption matrix** keeps its two axes independent: infrastructure health on one,
usage on the other. That is what separates a school needing a technician from one needing training.
Tapping a quadrant opens the school list filtered to it.

### How the Open API is called

`doc.grandstream.dev` is unreachable from the build environment, so the wire format was established
from published community examples of the GWN Manager API rather than the developer portal. Two
things follow from that, both isolated in `lib/core/api/`:

* **Token** — `GET {host}/oauth/token?grant_type=client_credentials&client_id=APP_ID&client_secret=SECRET_KEY`.
  It sits at the host root, *not* under `/oapi/v1.0.0`; assuming otherwise made every path answer 404.
* **Signed calls** — the secret key takes part in the signature but is never transmitted:

  ```
  params    = access_token=…&appID=…&secretKey=…&timestamp=…   (ms since epoch)
  bodyHash  = sha256(compact JSON body)
  signature = sha256("&" + params + "&" + bodyHash + "&")
  query     = access_token, appID, timestamp, signature
  ```

Confirmed endpoints — `network/list` (GET), `network/detail`, `ap/list`, `ssid/list` (POST) — are
named directly and take the documented body (`networkId`, `search`, `order`, `pageNum`, `pageSize`).
Switch and alarm paths are still candidate lists the client probes.

**This API version exposes no time series.** There is no `statistics/*` or `report/*` family: only
list and detail endpoints, each describing the network as it stands right now. The daily counters
every usage indicator needs are therefore *accrued by the app*, not fetched — each sync folds one
observation into the day (peak clients keep the highest seen, uptime is the share of observations
that found the network up), so the history deepens the longer the app runs. The dashboards say this
rather than showing an empty chart, and a reported figure always wins over a sampled one when the
cloud does provide it.

*Settings → Test connection* reports which paths answered **and the field names each returned**,
which is what the parsing has to be matched against.

### Release signing

Release builds are signed with the key in `android/key.properties`, which is git-ignored and never
committed. Without it Gradle falls back to its debug key — and because every machine and every CI
runner generates its own debug key, two builds signed that way cannot be installed over each other.
To give the repository one stable key, create it once:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
base64 -w0 release.jks          # paste the output into the secret below
```

Then add four repository secrets (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
CI writes `android/key.properties` from them before building. Keep `release.jks` somewhere safe and
off the repository: losing it means every tablet has to uninstall and reinstall again.

## Screenshots (demo mode, Linux desktop build)

| Landing dashboard | Landing dashboard (continued) |
|-------------------|-------------------------------|
| ![Dashboard](docs/screenshots/dashboard.png) | ![Dashboard 2](docs/screenshots/dashboard_4.png) |

| Internet connectivity (roll-out) | Students and teachers |
|----------------------------------|------------------------|
| ![Connectivity](docs/screenshots/connectivity.png) | ![Education](docs/screenshots/education.png) |

| School networks: headline indicators | Adoption index and the weight behind it |
|---------------------------------------|------------------------------------------|
| ![Network overview](docs/screenshots/network_overview.png) | ![Adoption index](docs/screenshots/network_overview_3.png) |

| Infrastructure health and faults | Wi-Fi use and traffic by SSID |
|-----------------------------------|--------------------------------|
| ![Infrastructure](docs/screenshots/network_infrastructure.png) | ![Usage](docs/screenshots/network_usage.png) |

| Schools, filterable by matrix quadrant | |
|-----------------------------------------|--|
| ![Network schools](docs/screenshots/network_schools.png) | |

| Schools directory | School record |
|-------------------|---------------|
| ![Schools](docs/screenshots/schools.png) | ![School record](docs/screenshots/school_record.png) |

| Programme (solarisation coverage) | Programme (funding, audited loads) |
|-----------------------------------|------------------------------------|
| ![Programme](docs/screenshots/programme.png) | ![Programme 2](docs/screenshots/programme_3.png) |

| Programme (attention lists, measured vs audited) | Programme (education, links) |
|--------------------------------------------------|------------------------------|
| ![Programme 3](docs/screenshots/programme_8.png) | ![Programme 4](docs/screenshots/programme_11.png) |

| Analytics | Plants (every plant in the account) |
|-----------|--------------------------------------|
| ![Analytics](docs/screenshots/analytics.png) | ![Plants](docs/screenshots/plants.png) |

| Plant overview (live flow and KPIs) | Plant summary and solar utilisation |
|-------------------------------------|--------------------------------------|
| ![Plant overview](docs/screenshots/plant_detail.png) | ![Plant summary](docs/screenshots/plant_detail_3.png) |

| Generation & usage history (usage mirrored below the axis) | Plant devices |
|-------------------------------------------------------------|---------------|
| ![Plant history](docs/screenshots/plant_detail_6.png) | ![Plant devices](docs/screenshots/plant_devices.png) |

| Plant alerts and status history | Plant info (registration and the linked school) |
|----------------------------------|--------------------------------------------------|
| ![Plant alerts](docs/screenshots/plant_alerts.png) | ![Plant info](docs/screenshots/plant_info.png) |

| Alarms | Map with the public-schools layer |
|--------|-----------------------------------|
| ![Alarms](docs/screenshots/alarms.png) | ![Map schools](docs/screenshots/map_schools.png) |

| Map | Settings |
|-----|----------|
| ![Map](docs/screenshots/map.png) | ![Settings](docs/screenshots/settings.png) |

| Governorates and attention lists | Today's power curve for one plant |
|----------------------------------|------------------------------------|
| ![Governorates](docs/screenshots/analytics_5.png) | ![Today](docs/screenshots/plant_detail_5.png) |

| Dark theme |  |
|------------|--|
| ![Dashboard dark](docs/screenshots/dashboard_dark.png) | ![Plant overview dark](docs/screenshots/plant_detail_dark.png) |

All captures (light and dark, every screen scrolled) are in `docs/screenshots/`, generated by
`scripts/screenshots.sh` from the Linux desktop build in demo mode with the clock set to 14:00 Beirut
time. In demo mode the synthetic plants carry the names and coordinates of real solarised
schools, so the programme pages show the real dataset joined with synthetic live data.

### Credentials

The app needs a DeyeCloud **developer application** (App ID + App Secret from
https://developer.deyecloud.com/app) and the DeyeCloud **account** (e-mail + password, and the
**company id** for the UNICEF organisation account). Enter them in *Settings → DeyeCloud account*
and press *Test connection* (it logs in and lists the organisations the account belongs to);
they are stored in the device secure store (Android Keystore) and never in the database or the
repository. The password field accepts either the plain password or its SHA-256 hex digest.
The **App ID** is mandatory for the token call (`/account/token?appId=…`) — it is shown next to
the App Secret in the developer portal's application page.

For kiosk deployments the values can be baked in at build time (they still end up only in secure
storage on first launch):

```bash
flutter build apk --release \
  --dart-define=DEYE_APP_ID=... \
  --dart-define=DEYE_APP_SECRET=... \
  --dart-define=DEYE_EMAIL=... \
  --dart-define=DEYE_PASSWORD_SHA256=... \
  --dart-define=DEYE_COMPANY_ID=... \
  --dart-define=DEYE_REGION=eu
```

> **Do not commit credentials.** If an App Secret or password was ever shared in chat, e-mail or a
> ticket, rotate it in the DeyeCloud developer portal / account settings.

### Demo mode

*Settings → Demo mode* switches the data source to a synthetic fleet of ~60 Lebanese schools with
realistic diurnal PV, school-hours load, EDL outages, batteries, faults and alarm history — useful for
training, screenshots and UI work without network access. Tests use the same generator.

## School dataset (MEHE / UNICEF workbooks)

Five workbooks — the MEHE public school list (1,211 schools), the internet-connectivity roll-out
(534 schools), the UNICEF solar implementation tracker, the energy audit (annual loads and equipment
inventory) and the MEHE education dashboard — are merged by **CERD number** into
`assets/data/schools.json` with:

```bash
pip install openpyxl
python3 scripts/build_school_dataset.py <folder containing the .xlsx files>
```

Bump `version` in the script when the workbooks change; the app re-imports the JSON into SQLite on
the next start. Director names and personal phone numbers are deliberately left out. Plants are
linked to school records automatically after every sync (name similarity with transliteration
folding + coordinates) and can be linked by hand from the school page; the *Programme* tab, the school
profile on each plant page, the list columns and the map layer all read from these tables. Details in
`docs/ARCHITECTURE.md`.

## How synchronisation works (short version)

Every 5 minutes (configurable) the engine: lists plants → lists devices (hourly) → polls all inverters
and batteries in batches of 10 (`/device/latest`) → derives each plant's status and derived alarms →
polls `/station/latest` for every plant (every 15 min) → fetches daily/monthly history once a day →
backfills yesterday's intraday frames nightly → fetches cloud alarms (hourly fleet-wide, every 15 min
for alarming plants) → recomputes 15-minute fleet/governorate aggregates and battery statistics →
runs housekeeping once a day. Per-plant failures never abort a sweep; systemic API failures trip a
circuit breaker with back-off that is visible in the status bar. Details in `docs/ARCHITECTURE.md`.

## Things to verify against the live account

The DeyeCloud developer portal was not reachable from the environment in which this app was
written, so a few items are implemented defensively and should be checked on first connection:

1. **Alert endpoints** — launched Dec 2024; the client probes `/station/alertList`,
   `/station/alert/list`, … and remembers the first that answers. If the portal documents other paths
   or body keys, set them in *Settings → Advanced* or edit `lib/core/api/deye_endpoints.dart`.
   Derived alarms work regardless.
2. **Field names** in `/station/list`, `/station/latest` and `/device/latest` are parsed tolerantly
   (several aliases per field); check *Settings → Diagnostics → app log* after the first sync for
   "skipped"/"no data timestamp" messages and compare with `docs/API_REFERENCE.md`.
3. **Sign conventions** of inverter `TotalGridPower` / `BatteryPower` (assumed positive = import /
   discharge, as on Deye hybrids). The plant-level `/station/latest` values are used preferentially.
4. **Rate limits** are unpublished; the defaults (4 concurrent requests, ≥120 ms apart) can be tuned
   in Settings.

## Repository layout

```
lib/core        models, API client, SQLite DAOs, sync engine, insights, school dataset + linker, demo data, settings
lib/features    overview, dashboard (analytics), programme, stations, alarms, map, settings, shared widgets/charts, shell
assets/geo      Lebanon governorate/district polygons (geoBoundaries, CC BY 4.0)
assets/data     schools.json — merged MEHE/UNICEF school dataset (no personal data)
scripts         build_school_dataset.py (xlsx → JSON), screenshots.sh
docs            API reference, architecture, UI specification
test            core unit tests (incl. dataset/linker/insights), end-to-end sync test, widget tests
```

## Licence / attribution

Boundary data © [geoBoundaries](https://www.geoboundaries.org) (CC BY 4.0). Map tiles ©
OpenStreetMap contributors. Deye and DeyeCloud are trademarks of Ningbo Deye Inverter Technology.
