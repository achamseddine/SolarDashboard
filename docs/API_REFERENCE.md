# DeyeCloud Open API v1 — reference used by this app

Source of truth: https://developer.deyecloud.com/api (login required). This file consolidates
what the official sample code (github.com/DeyeCloudDevelopers/deye-openapi-client-sample-code),
its ChangeLog, and several open-source clients demonstrate. Fields marked *(observed)* were seen in
real responses by third-party clients; fields marked *(unverified)* are best-effort and are parsed
defensively by the app.

## Base URLs (data centres)

| Region | Base URL |
|--------|----------|
| EU (default, Lebanon accounts) | `https://eu1-developer.deyecloud.com/v1.0` |
| US | `https://us1-developer.deyecloud.com/v1.0` |

All endpoints are `POST` with `Content-Type: application/json`. Authenticated calls send
`Authorization: bearer <accessToken>`.

Every response is a JSON envelope:

```json
{ "code": "1000000", "msg": "success", "success": true, "requestId": "...", ...payload }
```

`code == "1000000"` / `success == true` means OK. Any other code carries a human message in `msg`.

## Authentication

`POST /account/token?appId={appId}`

```json
{ "appSecret": "...", "email": "user@org", "password": "<sha256 hex, lowercase>", "companyId": "10377168" }
```

* `password` is the **SHA-256 hex digest** of the DeyeCloud password (the app accepts either a plain
  password, which it hashes, or an already-hashed 64-character hex string, which it sends as-is).
* `email` may be replaced by `username`, or by `mobile` + `countryCode`.
* `companyId` is optional. Without it the token is a *personal* token; with it the token acts as the
  *business member* of that company (needed for installer/organisation accounts that own many plants).
  `companyId` values are listed by `/account/info`.
* Response *(observed)*: `{ "accessToken": "eyJ...", "tokenType": "bearer", "expiresIn": <seconds>, "refreshToken": "...", "uid": ..., ... }`.
  Tokens are long-lived (community clients cache them for up to 60 days). The app refreshes on any
  401/403 or "token expired" error code.

`POST /account/info` `{}` → account profile including the list of companies/organisations the user
belongs to *(observed keys: `orgInfoList` / `companyId`, `companyName`)*.

## Stations (plants / schools)

`POST /station/list` `{ "page": 1, "size": 200 }` → `{ "stationList": [ ... ], "total": N }`

Station item *(observed)*:

| Key | Type | Notes |
|-----|------|-------|
| `id` | int | station id used in every other station call |
| `name` | string | plant name (school name) |
| `locationLat`, `locationLng` | double | coordinates |
| `locationAddress` | string | free-text address |
| `regionNationId`, `regionLevel1..3` | int/string | admin region identifiers |
| `regionTimezone` | string | e.g. `Asia/Beirut` |
| `gridInterconnectionType` | string | `BATTERY_BACKUP`, `SELF_CONSUMPTION`, `FULL_FEED_IN`, ... |
| `installedCapacity` | double | kWp |
| `startOperatingTime` | epoch seconds | commissioning date |
| `createdDate` | epoch seconds | |
| `batterySOC` | double | *(unverified)* present on some accounts |
| `connectionStatus` | string | *(unverified)* `NORMAL` / `OFFLINE` / `ALARM` / `NO_DATA` |
| `generationPower` | double | *(unverified)* W |
| `lastUpdateTime` | epoch seconds | *(unverified)* |
| `ownerName`, `contactPhone` | string | |

`POST /station/listWithDevice` `{ "page": 1, "size": 200, "deviceType": "INVERTER" }`
→ same as above with each station carrying `deviceListItems: [ device ... ]`.
`deviceType` ∈ `INVERTER, MICRO_INVERTER, COLLECTOR, BATTERY, MECD, METER, RELAY_BOX, OPTIMIZER, PV_MODULE`.

`POST /station/device` `{ "page": 1, "size": 100, "stationIds": [1, 2] }`
→ `{ "deviceListItems": [ device ... ], "total": N }`

Device item *(observed)*:

| Key | Type | Notes |
|-----|------|-------|
| `deviceSn` | string | serial, used for `/device/*` calls |
| `deviceId` | int | |
| `deviceType` | string | see list above |
| `productId` / `productName` | | model info |
| `connectStatus` | string / int | `ONLINE` / `OFFLINE` / `ALARM` *(unverified, parsed tolerantly)* |
| `stationId`, `stationName` | | |
| `collectionTime` | epoch seconds | last data time |
| `collectorSn` | string | logger serial |

`POST /station/latest` `{ "stationId": 123 }` → real-time power flow *(observed)*:

| Key | Unit | Meaning |
|-----|------|---------|
| `generationPower` | W | PV generation |
| `consumptionPower` | W | school load |
| `gridPower` | W | export to grid |
| `purchasePower` | W | import from grid |
| `wirePower` | W | net grid power (+import / −export) |
| `chargePower` | W | battery charging |
| `dischargePower` | W | battery discharging |
| `batteryPower` | W | signed battery power |
| `batterySOC` | % | state of charge |
| `irradiateIntensity` | W/m² | *(unverified)* if a sensor exists |
| `lastUpdateTime` | epoch seconds | data timestamp |

`POST /station/history` `{ "stationId": 123, "granularity": 2, "startAt": "2025-01-01", "endAt": "2025-01-31" }`
→ `{ "stationDataItems": [ ... ] }`

| granularity | `startAt`/`endAt` format | returns |
|-------------|--------------------------|---------|
| 1 (frame) | `yyyy-MM-dd` (startAt only) | intra-day frames (5–10 min) with **power** keys (`generationPower`, `consumptionPower`, `gridPower`, `purchasePower`, `wirePower`, `chargePower`, `dischargePower`, `batteryPower`, `batterySOC`) and `dateTime` |
| 2 (day) | `yyyy-MM-dd` | up to 31 daily rows with **energy** keys |
| 3 (month) | `yyyy-MM` | up to 12 monthly rows |
| 4 (year) | `yyyy` | yearly rows |

Energy keys *(observed)*: `generationValue`, `consumptionValue`, `gridValue` (export),
`purchaseValue` (import), `chargeValue`, `dischargeValue` (all kWh), `fullPowerHoursDay` (h),
plus date parts `year`, `month`, `day` and/or `dateTime`/`date`. `endAt` is **exclusive** for
granularity 2. The app reads all these keys tolerantly (string or number, epoch or ISO).

## Devices

`POST /device/list` `{ "page": 1, "size": 100 }` → `{ "deviceListItems": [...], "total": N }` (business accounts).

`POST /device/latest` `{ "deviceList": ["SN1", "SN2"] }` — **max 10 serials per call** →

```json
{ "deviceDataList": [
    { "deviceSn": "SN1", "deviceType": "INVERTER", "deviceState": 1, "collectionTime": 1717000000,
      "productId": 1, "stationId": 123,
      "dataList": [ { "key": "SOC", "value": "87.0", "unit": "%", "name": "Battery SOC" }, ... ] } ] }
```

`deviceState` *(observed)*: `1` online, `2` alarm, `3` offline (parsed tolerantly; strings also accepted).
Common inverter `dataList` keys *(observed on Deye hybrid inverters)*: `SOC`, `BatteryPower`,
`BatteryVoltage`, `BatteryCurrent`, `Temperature- Battery`, `TotalGridPower`, `GridPower`,
`TotalDCInputPower`, `DCPowerPV1..4`, `DCVoltagePV1..4`, `DCCurrentPV1..4`, `TotalConsumptionPower`,
`UPSLoadPower`, `DailyActiveProduction`, `TotalActiveProduction`, `DailyConsumption`,
`DailyEnergyBuy`, `DailyEnergySell`, `DailyBatteryCharge`, `DailyBatteryDischarge`, `GridFrequency`,
`GridVoltageL1..3`, `AC Temperature`, `DC Temperature`, `BMS_SOC`, `BMSVoltage`, `BMSCurrent`,
`BMSTemperature`, `BMSChargeVoltage`, `BMSDisChargeVoltage`, `BMSMaxChargeCurrent`, `BMSMaxDischargeCurrent`,
`SN`, `WorkMode`, `RunningStatus`, `AlertMessage`. Keys vary per model — the app stores whatever comes back.

`POST /device/measurePoints` `{ "deviceSn": "SN1" }` → list of supported keys for `device/history`
*(observed: `measurePoints: [ { "key": ..., "name": ..., "unit": ... } ]` or plain string list)*.

`POST /device/history` `{ "deviceSn": "SN1", "granularity": 1, "startAt": "2025-01-01", "endAt": "2025-01-01", "measurePoints": ["SOC"] }`
→ `{ "paramDataList": [ { "collectTime": 1717000000, "dataList": [ {key,value,unit} ] } ] }` *(unverified shape; parsed tolerantly)*.

## Alerts / alarms (launched 18 Dec 2024)

ChangeLog: *"Station Alert List, retrieving station alert list using 10-digit Unix timestamps (in
seconds) for stations, with support for paginated queries"* and *"Device Alert List, retrieving device
alert list using 10-digit Unix timestamp (in seconds)"*.

The exact paths are not reproduced in any public sample, so the app tries the candidates below in
order and remembers the first one that answers with a DeyeCloud envelope (`code` present):

| Purpose | Candidate paths | Body |
|---------|-----------------|------|
| Station alerts | `/station/alertList`, `/station/alert/list` | `{ "stationId": 123, "startTimestamp": 1735689600, "endTimestamp": 1735776000, "page": 1, "size": 100 }` |
| Device alerts | `/device/alertList`, `/device/alert/list` | `{ "deviceSn": "SN1", "startTimestamp": ..., "endTimestamp": ... }` |

Alert item keys are read tolerantly *(expected, unverified)*: `alertId`/`id`, `deviceSn`, `deviceType`,
`stationId`, `stationName`, `alertName`/`name`/`alertContent`, `alertCode`/`code`, `level`/`alertLevel`
(`1..3` or `LOW/MEDIUM/HIGH`), `startTime`/`alertTime`/`occurTime`, `endTime`/`recoverTime`,
`status` (`ACTIVE`/`RECOVERED`), `description`/`desc`/`suggestion`.
If your developer-portal documentation shows different paths, change `DeyeEndpoints.stationAlertCandidates`
and `DeyeEndpoints.deviceAlertCandidates` in `lib/core/api/deye_endpoints.dart`.

## Rate limits and etiquette

DeyeCloud does not publish hard limits. The app:
* runs at most 4 requests in flight and spaces requests ≥120 ms apart,
* polls `/station/latest` for every plant every *N* minutes (default 5) in a rolling sweep,
* batches `/device/latest` by 10 serials,
* pulls daily energy history once per day per plant (and on first sync),
* pulls alerts every 15 minutes for the last 24 h, and once for the last 30 days at first sync,
* backs off exponentially on HTTP 429/5xx.
