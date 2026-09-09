import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../api/json_utils.dart';
import '../utils/app_time.dart';

/// Connection state of a plant as shown on the dashboard.
enum StationStatus {
  online,
  offline,
  alarm,
  stale,
  unknown;

  String get db => name.toUpperCase();

  static StationStatus fromDb(String? v) {
    switch ((v ?? '').toUpperCase()) {
      case 'ONLINE':
      case 'NORMAL':
        return StationStatus.online;
      case 'OFFLINE':
        return StationStatus.offline;
      case 'ALARM':
      case 'ALERT':
      case 'FAULT':
        return StationStatus.alarm;
      case 'STALE':
        return StationStatus.stale;
      default:
        return StationStatus.unknown;
    }
  }

  /// Maps DeyeCloud `connectionStatus` / `status` / numeric codes. Returns
  /// [unknown] for anything unrecognised (including `NO_DATA`).
  static StationStatus fromApi(Object? v) {
    if (v == null) return StationStatus.unknown;
    if (v is num) {
      switch (v.toInt()) {
        case 1:
          return StationStatus.online;
        case 2:
          return StationStatus.alarm;
        case 3:
          return StationStatus.offline;
        default:
          return StationStatus.unknown;
      }
    }
    final s = v.toString().toUpperCase();
    if (s == '1') return StationStatus.online;
    if (s == '2') return StationStatus.alarm;
    if (s == '3') return StationStatus.offline;
    if (s.contains('NO_DATA') || s.contains('NODATA')) return StationStatus.unknown;
    if (s.contains('OFFLINE') || s.contains('DISCONNECT')) return StationStatus.offline;
    if (s.contains('ALARM') || s.contains('ALERT') || s.contains('FAULT') || s.contains('WARN')) return StationStatus.alarm;
    if (s.contains('ONLINE') || s.contains('NORMAL') || s.contains('CONNECT')) return StationStatus.online;
    return StationStatus.unknown;
  }

  String get label {
    switch (this) {
      case StationStatus.online:
        return 'Online';
      case StationStatus.offline:
        return 'Offline';
      case StationStatus.alarm:
        return 'Alarm';
      case StationStatus.stale:
        return 'Stale data';
      case StationStatus.unknown:
        return 'Unknown';
    }
  }

  /// Counts as "down" for availability statistics.
  bool get isDown => this == StationStatus.offline || this == StationStatus.stale;
}

/// A DeyeCloud plant (= one school). Master data only; live values live in
/// [StationLatest].
class Station {
  const Station({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.region,
    this.caza,
    this.timezone,
    this.gridType,
    this.installedCapacityKw,
    this.batteryCapacityKwh,
    this.startOperatingTs,
    this.createdTs,
    this.ownerName,
    this.contactPhone,
    this.apiStatus = StationStatus.unknown,
    this.status = StationStatus.unknown,
    this.lastUpdateTs,
    this.lastSeenAt,
    this.archived = false,
    this.raw = const {},
    this.updatedAt = 0,
  });

  final int id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;

  /// Lebanon governorate resolved locally (see `station_region.dart`).
  final String? region;

  /// District (caza) resolved locally when boundary data is available.
  final String? caza;
  final String? timezone;
  final String? gridType;
  final double? installedCapacityKw;

  /// Nominal battery capacity (kWh) — from BATTERY device data when the cloud
  /// reports it, otherwise entered by hand in the station detail screen.
  final double? batteryCapacityKwh;
  final int? startOperatingTs;
  final int? createdTs;
  final String? ownerName;
  final String? contactPhone;

  /// Status as reported by the cloud in the station list (may be unknown).
  final StationStatus apiStatus;

  /// Derived status written by the sync engine (see `station_status.dart`).
  final StationStatus status;

  /// Newest data timestamp known for this plant (epoch seconds).
  final int? lastUpdateTs;

  /// Last time the plant appeared in `/station/list`.
  final int? lastSeenAt;

  /// True when the plant disappeared from the account (kept for history).
  final bool archived;
  final Map<String, Object?> raw;
  final int updatedAt;

  bool get hasLocation => lat != null && lng != null && (lat != 0 || lng != 0);

  tz.Location get location => AppTime.location(timezone);

  /// Parses an item of `stationList`.
  factory Station.fromApi(Map<String, Object?> j) {
    final id = asInt(pick(j, ['id', 'stationId', 'plantId']));
    if (id == null) {
      throw FormatException('station without id: ${jsonEncode(j)}');
    }
    final apiStatus = StationStatus.fromApi(pick(j, ['connectionStatus', 'connectStatus', 'status', 'stationStatus', 'state']));
    return Station(
      id: id,
      name: asString(pick(j, ['name', 'stationName', 'plantName'])) ?? 'Station $id',
      address: asString(pick(j, ['locationAddress', 'address', 'location'])),
      lat: asDouble(pick(j, ['locationLat', 'lat', 'latitude'])),
      lng: asDouble(pick(j, ['locationLng', 'lng', 'lon', 'longitude'])),
      timezone: asString(pick(j, ['regionTimezone', 'timezone', 'timeZone'])),
      gridType: asString(pick(j, ['gridInterconnectionType', 'gridType', 'type'])),
      installedCapacityKw: asDouble(pick(j, ['installedCapacity', 'capacity', 'installedCapacityKw'])),
      batteryCapacityKwh: asDouble(pick(j, ['batteryCapacity', 'batteryCapacityKwh', 'storageCapacity'])),
      startOperatingTs: asEpochSeconds(pick(j, ['startOperatingTime', 'startOperatingDate', 'operatingTime'])),
      createdTs: asEpochSeconds(pick(j, ['createdDate', 'createTime', 'createdAt'])),
      ownerName: asString(pick(j, ['ownerName', 'owner', 'contactName'])),
      contactPhone: asString(pick(j, ['contactPhone', 'phone', 'mobile'])),
      apiStatus: apiStatus,
      lastUpdateTs: asEpochSeconds(pick(j, ['lastUpdateTime', 'updateTime', 'collectionTime', 'dataTime'])),
      raw: j,
    );
  }

  factory Station.fromRow(Map<String, Object?> r) => Station(
        id: r['id'] as int,
        name: r['name'] as String,
        address: r['address'] as String?,
        lat: asDouble(r['lat']),
        lng: asDouble(r['lng']),
        region: r['region'] as String?,
        caza: r['caza'] as String?,
        timezone: r['timezone'] as String?,
        gridType: r['grid_type'] as String?,
        installedCapacityKw: asDouble(r['installed_capacity_kw']),
        batteryCapacityKwh: asDouble(r['battery_capacity_kwh']),
        startOperatingTs: asInt(r['start_operating_ts']),
        createdTs: asInt(r['created_ts']),
        ownerName: r['owner_name'] as String?,
        contactPhone: r['contact_phone'] as String?,
        apiStatus: StationStatus.fromDb(r['api_status'] as String?),
        status: StationStatus.fromDb(r['connection_status'] as String?),
        lastUpdateTs: asInt(r['last_update_ts']),
        lastSeenAt: asInt(r['last_seen_at']),
        archived: (asInt(r['archived']) ?? 0) == 1,
        raw: decodeRawJson(r['raw_json']),
        updatedAt: asInt(r['updated_at']) ?? 0,
      );

  Map<String, Object?> toRow({required int now}) => {
        'id': id,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'region': region,
        'caza': caza,
        'timezone': timezone,
        'grid_type': gridType,
        'installed_capacity_kw': installedCapacityKw,
        'battery_capacity_kwh': batteryCapacityKwh,
        'start_operating_ts': startOperatingTs,
        'created_ts': createdTs,
        'owner_name': ownerName,
        'contact_phone': contactPhone,
        'api_status': apiStatus.db,
        'connection_status': status.db,
        'last_update_ts': lastUpdateTs,
        'last_seen_at': lastSeenAt ?? now,
        'archived': archived ? 1 : 0,
        'raw_json': jsonEncode(raw),
        'updated_at': now,
      };

  Station copyWith({
    String? region,
    String? caza,
    StationStatus? status,
    StationStatus? apiStatus,
    int? lastUpdateTs,
    int? lastSeenAt,
    bool? archived,
    String? name,
    double? installedCapacityKw,
    double? batteryCapacityKwh,
  }) =>
      Station(
        id: id,
        name: name ?? this.name,
        address: address,
        lat: lat,
        lng: lng,
        region: region ?? this.region,
        caza: caza ?? this.caza,
        timezone: timezone,
        gridType: gridType,
        installedCapacityKw: installedCapacityKw ?? this.installedCapacityKw,
        batteryCapacityKwh: batteryCapacityKwh ?? this.batteryCapacityKwh,
        startOperatingTs: startOperatingTs,
        createdTs: createdTs,
        ownerName: ownerName,
        contactPhone: contactPhone,
        apiStatus: apiStatus ?? this.apiStatus,
        status: status ?? this.status,
        lastUpdateTs: lastUpdateTs ?? this.lastUpdateTs,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        archived: archived ?? this.archived,
        raw: raw,
        updatedAt: updatedAt,
      );
}

/// Where a power reading came from.
enum SnapshotSource {
  station, // /station/latest
  device, // aggregated from /device/latest
  history, // /station/history granularity 1 backfill
  list, // opportunistic values in /station/list
  demo;

  String get db => name;
  static SnapshotSource fromDb(String? v) => SnapshotSource.values.firstWhere((s) => s.name == v, orElse: () => SnapshotSource.station);
}

/// Instantaneous power flow of one plant. Used for `/station/latest`
/// responses, aggregated inverter data, and rows of `station_snapshots`.
class StationSnapshot {
  const StationSnapshot({
    required this.stationId,
    required this.ts,
    required this.fetchedAt,
    this.source = SnapshotSource.station,
    this.generationW,
    this.consumptionW,
    this.gridExportW,
    this.gridImportW,
    this.wireW,
    this.chargeW,
    this.dischargeW,
    this.batteryW,
    this.batterySoc,
    this.irradiance,
  });

  final int stationId;

  /// Data timestamp (epoch seconds). Never the fetch time.
  final int ts;
  final int fetchedAt;
  final SnapshotSource source;
  final double? generationW;
  final double? consumptionW;
  final double? gridExportW;
  final double? gridImportW;

  /// Net grid power; positive = importing, negative = exporting.
  final double? wireW;
  final double? chargeW;
  final double? dischargeW;

  /// Signed battery power; positive = charging.
  final double? batteryW;
  final double? batterySoc;
  final double? irradiance;

  double get batteryNetW => batteryW ?? ((chargeW ?? 0) - (dischargeW ?? 0));
  double get gridNetW => wireW ?? ((gridImportW ?? 0) - (gridExportW ?? 0));
  double get importW => gridImportW ?? (gridNetW > 0 ? gridNetW : 0);
  double get exportW => gridExportW ?? (gridNetW < 0 ? -gridNetW : 0);

  /// A snapshot is "empty" when the API returned no power fields at all.
  bool get isEmpty =>
      generationW == null && consumptionW == null && batterySoc == null && gridImportW == null && gridExportW == null && wireW == null && batteryW == null;

  /// Parses the `/station/latest` envelope. Returns null when the payload
  /// carries no data timestamp (the caller must not fabricate one).
  static StationSnapshot? fromApi(Map<String, Object?> j, {required int stationId, required int fetchedAt, tz.Location? location, SnapshotSource source = SnapshotSource.station}) {
    final ts = asEpochSeconds(pick(j, ['lastUpdateTime', 'dateTime', 'collectTime', 'updateTime', 'time', 'date', 'timestamp']), location: location);
    if (ts == null) return null;
    return StationSnapshot(
      stationId: stationId,
      ts: ts,
      fetchedAt: fetchedAt,
      source: source,
      generationW: asDouble(pick(j, ['generationPower', 'pvPower', 'productionPower'])),
      consumptionW: asDouble(pick(j, ['consumptionPower', 'loadPower', 'usePower'])),
      gridExportW: asDouble(pick(j, ['gridPower', 'feedInPower', 'sellPower'])),
      gridImportW: asDouble(pick(j, ['purchasePower', 'buyPower', 'importPower'])),
      wireW: asDouble(pick(j, ['wirePower', 'gridNetPower'])),
      chargeW: asDouble(pick(j, ['chargePower'])),
      dischargeW: asDouble(pick(j, ['dischargePower'])),
      batteryW: asDouble(pick(j, ['batteryPower'])),
      batterySoc: asDouble(pick(j, ['batterySOC', 'batterySoc', 'soc', 'SOC'])),
      irradiance: asDouble(pick(j, ['irradiateIntensity', 'irradiance'])),
    );
  }

  factory StationSnapshot.fromRow(Map<String, Object?> r) => StationSnapshot(
        stationId: r['station_id'] as int,
        ts: r['ts'] as int,
        fetchedAt: asInt(r['fetched_at']) ?? (r['ts'] as int),
        source: SnapshotSource.fromDb(r['source'] as String?),
        generationW: asDouble(r['generation_w']),
        consumptionW: asDouble(r['consumption_w']),
        gridExportW: asDouble(r['grid_export_w']),
        gridImportW: asDouble(r['grid_import_w']),
        wireW: asDouble(r['wire_w']),
        chargeW: asDouble(r['charge_w']),
        dischargeW: asDouble(r['discharge_w']),
        batteryW: asDouble(r['battery_w']),
        batterySoc: asDouble(r['battery_soc']),
        irradiance: asDouble(r['irradiance']),
      );

  Map<String, Object?> toRow() => {
        'station_id': stationId,
        'ts': ts,
        'fetched_at': fetchedAt,
        'source': source.db,
        'generation_w': generationW,
        'consumption_w': consumptionW,
        'grid_export_w': gridExportW,
        'grid_import_w': gridImportW,
        'wire_w': wireW,
        'charge_w': chargeW,
        'discharge_w': dischargeW,
        'battery_w': batteryW,
        'battery_soc': batterySoc,
        'irradiance': irradiance,
      };
}

/// Today's running energy counters of a plant (kWh since local midnight).
class TodayEnergy {
  const TodayEnergy({this.generationKwh, this.consumptionKwh, this.gridImportKwh, this.gridExportKwh, this.chargeKwh, this.dischargeKwh});

  final double? generationKwh;
  final double? consumptionKwh;
  final double? gridImportKwh;
  final double? gridExportKwh;
  final double? chargeKwh;
  final double? dischargeKwh;

  bool get isEmpty => generationKwh == null && consumptionKwh == null && gridImportKwh == null && gridExportKwh == null;

  static const empty = TodayEnergy();
}

/// Row of `station_latest`: the newest known state of a plant, updated once
/// per sweep. This is what the dashboard reads for "now".
class StationLatest {
  const StationLatest({
    required this.stationId,
    this.dataTs,
    required this.fetchedAt,
    this.source = SnapshotSource.station,
    this.snapshot,
    this.today = TodayEnergy.empty,
    this.lastErrorAt,
    this.lastErrorMsg,
    this.raw,
  });

  final int stationId;

  /// Timestamp of the newest data (null when the plant never reported).
  final int? dataTs;
  final int fetchedAt;
  final SnapshotSource source;

  /// Newest power flow (null when never reported).
  final StationSnapshot? snapshot;
  final TodayEnergy today;
  final int? lastErrorAt;
  final String? lastErrorMsg;
  final Map<String, Object?>? raw;

  factory StationLatest.fromRow(Map<String, Object?> r) {
    final dataTs = asInt(r['data_ts']);
    final sid = r['station_id'] as int;
    return StationLatest(
      stationId: sid,
      dataTs: dataTs,
      fetchedAt: asInt(r['fetched_at']) ?? 0,
      source: SnapshotSource.fromDb(r['source'] as String?),
      snapshot: dataTs == null
          ? null
          : StationSnapshot(
              stationId: sid,
              ts: dataTs,
              fetchedAt: asInt(r['fetched_at']) ?? 0,
              source: SnapshotSource.fromDb(r['source'] as String?),
              generationW: asDouble(r['generation_w']),
              consumptionW: asDouble(r['consumption_w']),
              gridExportW: asDouble(r['grid_export_w']),
              gridImportW: asDouble(r['grid_import_w']),
              wireW: asDouble(r['wire_w']),
              chargeW: asDouble(r['charge_w']),
              dischargeW: asDouble(r['discharge_w']),
              batteryW: asDouble(r['battery_w']),
              batterySoc: asDouble(r['battery_soc']),
              irradiance: asDouble(r['irradiance']),
            ),
      today: TodayEnergy(
        generationKwh: asDouble(r['today_gen_kwh']),
        consumptionKwh: asDouble(r['today_cons_kwh']),
        gridImportKwh: asDouble(r['today_import_kwh']),
        gridExportKwh: asDouble(r['today_export_kwh']),
        chargeKwh: asDouble(r['today_charge_kwh']),
        dischargeKwh: asDouble(r['today_discharge_kwh']),
      ),
      lastErrorAt: asInt(r['last_error_at']),
      lastErrorMsg: r['last_error_msg'] as String?,
      raw: r['raw_json'] == null ? null : decodeRawJson(r['raw_json']),
    );
  }

  Map<String, Object?> toRow() => {
        'station_id': stationId,
        'data_ts': dataTs,
        'fetched_at': fetchedAt,
        'source': source.db,
        'generation_w': snapshot?.generationW,
        'consumption_w': snapshot?.consumptionW,
        'grid_export_w': snapshot?.gridExportW,
        'grid_import_w': snapshot?.gridImportW,
        'wire_w': snapshot?.wireW,
        'charge_w': snapshot?.chargeW,
        'discharge_w': snapshot?.dischargeW,
        'battery_w': snapshot?.batteryW,
        'battery_soc': snapshot?.batterySoc,
        'irradiance': snapshot?.irradiance,
        'today_gen_kwh': today.generationKwh,
        'today_cons_kwh': today.consumptionKwh,
        'today_import_kwh': today.gridImportKwh,
        'today_export_kwh': today.gridExportKwh,
        'today_charge_kwh': today.chargeKwh,
        'today_discharge_kwh': today.dischargeKwh,
        'last_error_at': lastErrorAt,
        'last_error_msg': lastErrorMsg,
        'raw_json': raw == null ? null : jsonEncode(raw),
      };

  StationLatest copyWith({
    int? dataTs,
    int? fetchedAt,
    SnapshotSource? source,
    StationSnapshot? snapshot,
    TodayEnergy? today,
    int? lastErrorAt,
    String? lastErrorMsg,
    bool clearError = false,
    Map<String, Object?>? raw,
  }) =>
      StationLatest(
        stationId: stationId,
        dataTs: dataTs ?? this.dataTs,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        source: source ?? this.source,
        snapshot: snapshot ?? this.snapshot,
        today: today ?? this.today,
        lastErrorAt: clearError ? null : (lastErrorAt ?? this.lastErrorAt),
        lastErrorMsg: clearError ? null : (lastErrorMsg ?? this.lastErrorMsg),
        raw: raw ?? this.raw,
      );
}

/// Where a daily/monthly energy row came from.
enum EnergySource {
  history, // /station/history
  counter, // Daily* counters from /device/latest
  demo;

  String get db => name;
  static EnergySource fromDb(String? v) => EnergySource.values.firstWhere((s) => s.name == v, orElse: () => EnergySource.history);
}

/// One day (or month) of plant energy totals.
class StationEnergy {
  const StationEnergy({
    required this.stationId,
    required this.period,
    this.generationKwh,
    this.consumptionKwh,
    this.gridExportKwh,
    this.gridImportKwh,
    this.chargeKwh,
    this.dischargeKwh,
    this.fullPowerHours,
    this.completenessPct,
    this.source = EnergySource.history,
  });

  final int stationId;

  /// `yyyy-MM-dd` for daily rows, `yyyy-MM` for monthly rows.
  final String period;
  final double? generationKwh;
  final double? consumptionKwh;
  final double? gridExportKwh;
  final double? gridImportKwh;
  final double? chargeKwh;
  final double? dischargeKwh;
  final double? fullPowerHours;

  /// Share (0-100) of expected intraday frames actually stored, when known.
  final double? completenessPct;
  final EnergySource source;

  /// kWh that were self-consumed (generation not exported).
  double? get selfConsumedKwh => generationKwh == null ? null : (generationKwh! - (gridExportKwh ?? 0)).clamp(0, double.infinity);

  /// Share of consumption not bought from the grid (null below 1 kWh).
  double? get selfSufficiency {
    final c = consumptionKwh;
    if (c == null || c < 1) return null;
    return ((c - (gridImportKwh ?? 0)) / c).clamp(0, 1);
  }

  /// Parses one `stationDataItems` row. Returns null if the row carries no
  /// usable date; pass [fallbackPeriod] to map undated rows positionally.
  static StationEnergy? fromApi(Map<String, Object?> j, {required int stationId, required bool monthly, String? fallbackPeriod, tz.Location? location}) {
    final period = periodOf(j, monthly: monthly, location: location) ?? fallbackPeriod;
    if (period == null) return null;
    return StationEnergy(
      stationId: stationId,
      period: period,
      generationKwh: asDouble(pick(j, ['generationValue', 'generation', 'pvValue', 'production'])),
      consumptionKwh: asDouble(pick(j, ['consumptionValue', 'consumption', 'useValue', 'loadValue'])),
      gridExportKwh: asDouble(pick(j, ['gridValue', 'feedInValue', 'sellValue', 'exportValue'])),
      gridImportKwh: asDouble(pick(j, ['purchaseValue', 'buyValue', 'importValue'])),
      chargeKwh: asDouble(pick(j, ['chargeValue', 'batteryChargeValue'])),
      dischargeKwh: asDouble(pick(j, ['dischargeValue', 'batteryDischargeValue'])),
      fullPowerHours: asDouble(pick(j, ['fullPowerHoursDay', 'fullPowerHours', 'equivalentHours'])),
      source: EnergySource.history,
    );
  }

  /// Extracts the period (`yyyy-MM-dd` or `yyyy-MM`) of a history row.
  static String? periodOf(Map<String, Object?> j, {required bool monthly, tz.Location? location}) {
    final year = asInt(pick(j, ['year']));
    final month = asInt(pick(j, ['month']));
    final day = asInt(pick(j, ['day']));
    if (year != null && month != null && (monthly || day != null)) {
      final d = DateTime.utc(year, month, monthly ? 1 : day!);
      return monthly ? AppTime.formatMonth(d) : AppTime.formatDay(d);
    }
    final raw = pick(j, ['date', 'dateTime', 'time', 'collectTime', 'timestamp']);
    if (raw == null) return null;
    final s = raw.toString().trim();
    final m = RegExp(r'^(\d{4})[-/](\d{2})(?:[-/](\d{2}))?').firstMatch(s);
    if (m != null) {
      if (monthly) return '${m.group(1)}-${m.group(2)}';
      if (m.group(3) != null) return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
    }
    final epoch = asEpochSeconds(raw, location: location);
    if (epoch == null) return null;
    return monthly ? AppTime.monthOf(epoch, location) : AppTime.dayOf(epoch, location);
  }

  factory StationEnergy.fromRow(Map<String, Object?> r) => StationEnergy(
        stationId: r['station_id'] as int,
        period: (r['day'] ?? r['month']) as String,
        generationKwh: asDouble(r['generation_kwh']),
        consumptionKwh: asDouble(r['consumption_kwh']),
        gridExportKwh: asDouble(r['grid_export_kwh']),
        gridImportKwh: asDouble(r['grid_import_kwh']),
        chargeKwh: asDouble(r['charge_kwh']),
        dischargeKwh: asDouble(r['discharge_kwh']),
        fullPowerHours: asDouble(r['full_power_hours']),
        completenessPct: asDouble(r['completeness_pct']),
        source: EnergySource.fromDb(r['source'] as String?),
      );

  Map<String, Object?> toRow({required bool monthly}) => {
        'station_id': stationId,
        monthly ? 'month' : 'day': period,
        'generation_kwh': generationKwh,
        'consumption_kwh': consumptionKwh,
        'grid_export_kwh': gridExportKwh,
        'grid_import_kwh': gridImportKwh,
        'charge_kwh': chargeKwh,
        'discharge_kwh': dischargeKwh,
        if (!monthly) 'full_power_hours': fullPowerHours,
        if (!monthly) 'completeness_pct': completenessPct,
        'source': source.db,
      };

  StationEnergy copyWith({double? completenessPct, EnergySource? source, double? fullPowerHours}) => StationEnergy(
        stationId: stationId,
        period: period,
        generationKwh: generationKwh,
        consumptionKwh: consumptionKwh,
        gridExportKwh: gridExportKwh,
        gridImportKwh: gridImportKwh,
        chargeKwh: chargeKwh,
        dischargeKwh: dischargeKwh,
        fullPowerHours: fullPowerHours ?? this.fullPowerHours,
        completenessPct: completenessPct ?? this.completenessPct,
        source: source ?? this.source,
      );

  /// True when this row looks like a copy of [other] (all non-zero values
  /// within 2 %) — DeyeCloud briefly serves yesterday's bucket as "today"
  /// right after midnight.
  bool looksLike(StationEnergy other) {
    var compared = 0;
    var matched = 0;
    for (final pair in [
      (generationKwh, other.generationKwh),
      (consumptionKwh, other.consumptionKwh),
      (gridImportKwh, other.gridImportKwh),
      (gridExportKwh, other.gridExportKwh),
      (chargeKwh, other.chargeKwh),
      (dischargeKwh, other.dischargeKwh),
    ]) {
      final a = pair.$1;
      final b = pair.$2;
      if (a == null || b == null || b <= 0.001) continue;
      compared++;
      if ((a - b).abs() <= (b * 0.02).clamp(0.001, double.infinity)) matched++;
    }
    return compared > 0 && matched >= (compared < 2 ? 1 : 2);
  }
}

/// A status transition of a plant (for availability / outage statistics).
class StatusEvent {
  const StatusEvent({required this.stationId, required this.status, required this.startTs, this.endTs, this.source = 'derived'});

  final int stationId;
  final StationStatus status;
  final int startTs;
  final int? endTs;
  final String source;

  Duration durationUntil(int now) => Duration(seconds: (endTs ?? now) - startTs);

  factory StatusEvent.fromRow(Map<String, Object?> r) => StatusEvent(
        stationId: r['station_id'] as int,
        status: StationStatus.fromDb(r['status'] as String?),
        startTs: r['start_ts'] as int,
        endTs: asInt(r['end_ts']),
        source: (r['source'] as String?) ?? 'derived',
      );

  Map<String, Object?> toRow() => {'station_id': stationId, 'status': status.db, 'start_ts': startTs, 'end_ts': endTs, 'source': source};
}

/// Fleet- or region-wide power aggregated into a time bucket (15 min).
class PowerBucket {
  const PowerBucket({
    required this.bucketTs,
    this.region = '',
    required this.stationsReporting,
    this.generationW = 0,
    this.consumptionW = 0,
    this.gridImportW = 0,
    this.gridExportW = 0,
    this.chargeW = 0,
    this.dischargeW = 0,
    this.avgSoc,
  });

  final int bucketTs;

  /// Governorate name, or empty string for the whole fleet.
  final String region;
  final int stationsReporting;
  final double generationW;
  final double consumptionW;
  final double gridImportW;
  final double gridExportW;
  final double chargeW;
  final double dischargeW;
  final double? avgSoc;

  factory PowerBucket.fromRow(Map<String, Object?> r) => PowerBucket(
        bucketTs: r['bucket_ts'] as int,
        region: (r['region'] as String?) ?? '',
        stationsReporting: asInt(r['stations_reporting']) ?? 0,
        generationW: asDouble(r['gen_w']) ?? 0,
        consumptionW: asDouble(r['cons_w']) ?? 0,
        gridImportW: asDouble(r['import_w']) ?? 0,
        gridExportW: asDouble(r['export_w']) ?? 0,
        chargeW: asDouble(r['charge_w']) ?? 0,
        dischargeW: asDouble(r['discharge_w']) ?? 0,
        avgSoc: asDouble(r['soc_avg']),
      );

  Map<String, Object?> toRow() => {
        'bucket_ts': bucketTs,
        'region': region,
        'stations_reporting': stationsReporting,
        'gen_w': generationW,
        'cons_w': consumptionW,
        'import_w': gridImportW,
        'export_w': gridExportW,
        'charge_w': chargeW,
        'discharge_w': dischargeW,
        'soc_avg': avgSoc,
      };
}

/// Daily battery statistics of a plant, derived from device samples.
class BatteryDay {
  const BatteryDay({
    required this.stationId,
    required this.day,
    this.socMin,
    this.socMax,
    this.socAvg,
    this.hoursBelow20 = 0,
    this.tempMax,
    this.chargeKwh,
    this.dischargeKwh,
    this.samples = 0,
  });

  final int stationId;
  final String day;
  final double? socMin;
  final double? socMax;
  final double? socAvg;
  final double hoursBelow20;
  final double? tempMax;
  final double? chargeKwh;
  final double? dischargeKwh;
  final int samples;

  factory BatteryDay.fromRow(Map<String, Object?> r) => BatteryDay(
        stationId: r['station_id'] as int,
        day: r['day'] as String,
        socMin: asDouble(r['soc_min']),
        socMax: asDouble(r['soc_max']),
        socAvg: asDouble(r['soc_avg']),
        hoursBelow20: asDouble(r['hours_below_20']) ?? 0,
        tempMax: asDouble(r['temp_max']),
        chargeKwh: asDouble(r['charge_kwh']),
        dischargeKwh: asDouble(r['discharge_kwh']),
        samples: asInt(r['samples']) ?? 0,
      );

  Map<String, Object?> toRow() => {
        'station_id': stationId,
        'day': day,
        'soc_min': socMin,
        'soc_max': socMax,
        'soc_avg': socAvg,
        'hours_below_20': hoursBelow20,
        'temp_max': tempMax,
        'charge_kwh': chargeKwh,
        'discharge_kwh': dischargeKwh,
        'samples': samples,
      };
}

Map<String, Object?> decodeRawJson(Object? v) {
  if (v is String && v.isNotEmpty) {
    try {
      return asMap(jsonDecode(v));
    } catch (_) {}
  }
  return const {};
}
