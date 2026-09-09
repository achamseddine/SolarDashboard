import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../api/json_utils.dart';
import 'station.dart' show decodeRawJson;

enum DeviceStatus {
  online,
  offline,
  alarm,
  unknown;

  String get db => name.toUpperCase();

  static DeviceStatus fromDb(String? v) => DeviceStatus.values.firstWhere(
        (s) => s.db == (v ?? '').toUpperCase(),
        orElse: () => DeviceStatus.unknown,
      );

  /// Maps `connectStatus` / `deviceState` (numeric 1/2/3 or text).
  static DeviceStatus fromApi(Object? v) {
    if (v == null) return DeviceStatus.unknown;
    if (v is num) {
      switch (v.toInt()) {
        case 1:
          return DeviceStatus.online;
        case 2:
          return DeviceStatus.alarm;
        case 3:
          return DeviceStatus.offline;
        default:
          return DeviceStatus.unknown;
      }
    }
    final s = v.toString().toUpperCase();
    if (s == '1') return DeviceStatus.online;
    if (s == '2') return DeviceStatus.alarm;
    if (s == '3') return DeviceStatus.offline;
    if (s.contains('OFFLINE') || s.contains('DISCONNECT')) return DeviceStatus.offline;
    if (s.contains('ALARM') || s.contains('ALERT') || s.contains('FAULT') || s.contains('WARN')) return DeviceStatus.alarm;
    if (s.contains('ONLINE') || s.contains('NORMAL') || s.contains('CONNECT')) return DeviceStatus.online;
    return DeviceStatus.unknown;
  }

  String get label {
    switch (this) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.alarm:
        return 'Alarm';
      case DeviceStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Inverter, battery, logger, meter … belonging to a station.
class Device {
  const Device({
    required this.deviceSn,
    this.stationId,
    this.deviceId,
    this.deviceType,
    this.productId,
    this.productName,
    this.collectorSn,
    this.status = DeviceStatus.unknown,
    this.collectionTs,
    this.lastSeenAt,
    this.archived = false,
    this.raw = const {},
    this.updatedAt = 0,
  });

  final String deviceSn;
  final int? stationId;
  final int? deviceId;

  /// `INVERTER`, `BATTERY`, `COLLECTOR`, `METER`, … (upper-cased).
  final String? deviceType;
  final String? productId;
  final String? productName;
  final String? collectorSn;
  final DeviceStatus status;
  final int? collectionTs;
  final int? lastSeenAt;
  final bool archived;
  final Map<String, Object?> raw;
  final int updatedAt;

  bool get isInverter => (deviceType ?? '').contains('INVERTER');
  bool get isBattery => (deviceType ?? '') == 'BATTERY' || (deviceType ?? '').contains('BMS');
  bool get isLogger => (deviceType ?? '') == 'COLLECTOR' || (deviceType ?? '').contains('LOGGER');

  /// Nominal battery capacity (kWh) if the cloud reports it on a BATTERY.
  double? get batteryCapacityKwh {
    if (!isBattery) return null;
    final v = asDouble(pick(raw, ['capacity', 'ratedCapacity', 'batteryCapacity', 'nominalCapacity']));
    if (v == null) return null;
    // Some firmwares report Ah with a 48/51.2 V pack; treat > 500 as Ah.
    return v > 500 ? v * 51.2 / 1000 : v;
  }

  /// Parses an item of `deviceListItems`.
  static Device? fromApi(Map<String, Object?> j, {int? stationId}) {
    final sn = asString(pick(j, ['deviceSn', 'sn', 'serialNo', 'serialNumber']));
    if (sn == null) return null;
    return Device(
      deviceSn: sn,
      stationId: asInt(pick(j, ['stationId', 'plantId'])) ?? stationId,
      deviceId: asInt(pick(j, ['deviceId', 'id'])),
      deviceType: asString(pick(j, ['deviceType', 'type']))?.toUpperCase(),
      productId: asString(pick(j, ['productId', 'productCode', 'model'])),
      productName: asString(pick(j, ['productName', 'productModel', 'deviceModel', 'modelName'])),
      collectorSn: asString(pick(j, ['collectorSn', 'loggerSn', 'gatewaySn'])),
      status: DeviceStatus.fromApi(pick(j, ['connectStatus', 'connectionStatus', 'deviceState', 'status', 'state'])),
      collectionTs: asEpochSeconds(pick(j, ['collectionTime', 'lastUpdateTime', 'updateTime', 'dataTime'])),
      raw: j,
    );
  }

  factory Device.fromRow(Map<String, Object?> r) => Device(
        deviceSn: r['device_sn'] as String,
        stationId: asInt(r['station_id']),
        deviceId: asInt(r['device_id']),
        deviceType: r['device_type'] as String?,
        productId: r['product_id'] as String?,
        productName: r['product_name'] as String?,
        collectorSn: r['collector_sn'] as String?,
        status: DeviceStatus.fromDb(r['connect_status'] as String?),
        collectionTs: asInt(r['collection_ts']),
        lastSeenAt: asInt(r['last_seen_at']),
        archived: (asInt(r['archived']) ?? 0) == 1,
        raw: decodeRawJson(r['raw_json']),
        updatedAt: asInt(r['updated_at']) ?? 0,
      );

  Map<String, Object?> toRow({required int now}) => {
        'device_sn': deviceSn,
        'station_id': stationId,
        'device_id': deviceId,
        'device_type': deviceType,
        'product_id': productId,
        'product_name': productName,
        'collector_sn': collectorSn,
        'connect_status': status.db,
        'collection_ts': collectionTs,
        'last_seen_at': lastSeenAt ?? now,
        'archived': archived ? 1 : 0,
        'raw_json': jsonEncode(raw),
        'updated_at': now,
      };

  Device copyWith({DeviceStatus? status, int? collectionTs, int? stationId, int? lastSeenAt, bool? archived}) => Device(
        deviceSn: deviceSn,
        stationId: stationId ?? this.stationId,
        deviceId: deviceId,
        deviceType: deviceType,
        productId: productId,
        productName: productName,
        collectorSn: collectorSn,
        status: status ?? this.status,
        collectionTs: collectionTs ?? this.collectionTs,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        archived: archived ?? this.archived,
        raw: raw,
        updatedAt: updatedAt,
      );
}

/// One measure point (`dataList` entry) of a device.
class DeviceReading {
  const DeviceReading({required this.key, this.valueNum, this.valueText, this.unit, this.name});

  final String key;
  final double? valueNum;
  final String? valueText;
  final String? unit;
  final String? name;

  String get displayValue {
    if (valueNum != null) {
      final v = valueNum!;
      final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
      return unit == null || unit!.isEmpty ? s : '$s $unit';
    }
    return valueText ?? '-';
  }

  static DeviceReading? fromApi(Map<String, Object?> j) {
    final key = asString(pick(j, ['key', 'code']));
    if (key == null) return null;
    final rawValue = pick(j, ['value', 'val']);
    final n = asDouble(rawValue);
    return DeviceReading(
      key: key,
      valueNum: n,
      valueText: n == null ? asString(rawValue) : null,
      unit: asString(pick(j, ['unit'])),
      name: asString(pick(j, ['name', 'label', 'desc'])),
    );
  }

  Map<String, Object?> toJson() => {'key': key, 'value': valueNum ?? valueText, 'unit': unit, 'name': name};
}

/// Result of `/device/latest` for one device (also the `device_latest` row).
class DeviceLatest {
  const DeviceLatest({
    required this.deviceSn,
    required this.collectionTs,
    required this.fetchedAt,
    this.deviceType,
    this.status = DeviceStatus.unknown,
    this.stationId,
    this.productId,
    this.readings = const [],
  });

  final String deviceSn;

  /// Data timestamp (epoch seconds), or null when the cloud gave none.
  final int? collectionTs;
  final int fetchedAt;
  final String? deviceType;
  final DeviceStatus status;
  final int? stationId;
  final String? productId;
  final List<DeviceReading> readings;

  static DeviceLatest? fromApi(Map<String, Object?> j, {required int fetchedAt, tz.Location? location}) {
    final sn = asString(pick(j, ['deviceSn', 'sn', 'serialNo']));
    if (sn == null) return null;
    final ts = asEpochSeconds(pick(j, ['collectionTime', 'collectTime', 'lastUpdateTime', 'updateTime']), location: location);
    final list = pick(j, ['dataList', 'data', 'measurePoints']);
    final readings = <DeviceReading>[
      if (list is List)
        for (final e in list)
          if (e is Map) ?DeviceReading.fromApi(asMap(e)),
    ];
    return DeviceLatest(
      deviceSn: sn,
      collectionTs: ts,
      fetchedAt: fetchedAt,
      deviceType: asString(pick(j, ['deviceType', 'type']))?.toUpperCase(),
      status: DeviceStatus.fromApi(pick(j, ['deviceState', 'connectStatus', 'status', 'state'])),
      stationId: asInt(pick(j, ['stationId', 'plantId'])),
      productId: asString(pick(j, ['productId'])),
      readings: readings,
    );
  }

  factory DeviceLatest.fromRow(Map<String, Object?> r) {
    final data = r['data_json'];
    final readings = <DeviceReading>[];
    if (data is String && data.isNotEmpty) {
      try {
        final list = jsonDecode(data);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              final m = asMap(e);
              final v = m['value'];
              final n = asDouble(v);
              readings.add(DeviceReading(
                key: m['key'] as String,
                valueNum: n,
                valueText: n == null ? asString(v) : null,
                unit: m['unit'] as String?,
                name: m['name'] as String?,
              ));
            }
          }
        }
      } catch (_) {}
    }
    return DeviceLatest(
      deviceSn: r['device_sn'] as String,
      collectionTs: asInt(r['collection_ts']),
      fetchedAt: asInt(r['fetched_at']) ?? 0,
      deviceType: r['device_type'] as String?,
      status: DeviceStatus.fromDb(r['state'] as String?),
      stationId: asInt(r['station_id']),
      readings: readings,
    );
  }

  Map<String, Object?> toRow() => {
        'device_sn': deviceSn,
        'collection_ts': collectionTs,
        'fetched_at': fetchedAt,
        'device_type': deviceType,
        'state': status.db,
        'station_id': stationId,
        'data_json': jsonEncode([for (final r in readings) r.toJson()]),
      };

  DeviceReading? reading(List<String> keys) {
    for (final k in keys) {
      for (final r in readings) {
        if (r.key == k) return r;
      }
    }
    final lower = {for (final r in readings) r.key.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), ''): r};
    for (final k in keys) {
      final r = lower[k.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '')];
      if (r != null) return r;
    }
    return null;
  }

  /// Numeric value of the first matching key, normalised to base units
  /// (kW→W, MWh→kWh, Wh→kWh).
  double? value(List<String> keys) {
    final r = reading(keys);
    if (r?.valueNum == null) return null;
    return normaliseUnit(r!.valueNum!, r.unit);
  }

  String? text(List<String> keys) {
    final r = reading(keys);
    return r?.valueText ?? r?.valueNum?.toString();
  }

  static double normaliseUnit(double v, String? unit) {
    switch ((unit ?? '').trim().toLowerCase()) {
      case 'kw':
        return v * 1000;
      case 'mw':
        return v * 1e6;
      case 'mwh':
        return v * 1000;
      case 'wh':
        return v / 1000;
      case 'kv':
        return v * 1000;
      default:
        return v;
    }
  }
}

/// Names DeyeCloud uses for the measure points the app keeps as history.
/// Keys differ between inverter models; each list is tried in order.
class MeasureKeys {
  MeasureKeys._();

  static const soc = ['SOC', 'BMS_SOC', 'BMSSOC', 'BatterySOC', 'Battery SOC', 'SOC1'];
  static const batteryPower = ['BatteryPower', 'Battery Power', 'BatPower', 'TotalBatteryPower'];
  static const batteryVoltage = ['BatteryVoltage', 'BMSVoltage', 'Battery Voltage', 'BMS_Voltage'];
  static const batteryCurrent = ['BatteryCurrent', 'BMSCurrent', 'Battery Current'];
  static const batteryTemp = ['Temperature- Battery', 'BatteryTemperature', 'BMSTemperature', 'Battery Temperature', 'BMS_Temperature', 'Temperature-Battery'];
  static const pvPower = ['TotalDCInputPower', 'TotalPVPower', 'PVPower', 'DCPower', 'PV Power', 'TotalDcInputPower'];
  static const pv1 = ['DCPowerPV1', 'PV1Power', 'DC Power PV1'];
  static const pv2 = ['DCPowerPV2', 'PV2Power', 'DC Power PV2'];
  static const pv3 = ['DCPowerPV3', 'PV3Power', 'DC Power PV3'];
  static const pv4 = ['DCPowerPV4', 'PV4Power', 'DC Power PV4'];
  static const pvVoltage1 = ['DCVoltagePV1', 'PV1Voltage'];
  static const pvVoltage2 = ['DCVoltagePV2', 'PV2Voltage'];
  static const pvVoltage3 = ['DCVoltagePV3', 'PV3Voltage'];
  static const pvVoltage4 = ['DCVoltagePV4', 'PV4Voltage'];
  static const loadPower = ['TotalConsumptionPower', 'LoadPower', 'TotalLoadPower', 'ConsumptionPower', 'Load Power', 'UPSLoadPower'];
  static const gridPower = ['TotalGridPower', 'GridPower', 'Grid Power', 'ExternalCTPower', 'TotalExternalCTPower'];
  static const gridFrequency = ['GridFrequency', 'Grid Frequency', 'Frequency', 'GridFreq'];
  static const gridVoltage = ['GridVoltageL1', 'GridVoltage', 'Grid Voltage L1', 'ACVoltageL1', 'GridVoltageAB'];
  static const inverterTemp = ['AC Temperature', 'ACTemperature', 'DC Temperature', 'DCTemperature', 'Temperature', 'InverterTemperature', 'Temperature- Inverter'];
  static const dailyGeneration = ['DailyActiveProduction', 'DailyProduction', 'DailyEnergy', 'Daily Production', 'DailyGeneration', 'DailyPVEnergy'];
  static const totalGeneration = ['TotalActiveProduction', 'TotalProduction', 'TotalEnergy', 'CumulativeProduction'];
  static const dailyConsumption = ['DailyConsumption', 'Daily Consumption', 'DailyLoadEnergy', 'DailyLoadConsumption'];
  static const dailyImport = ['DailyEnergyBuy', 'DailyPurchase', 'DailyGridImport', 'DailyEnergyBought', 'Daily Energy Buy'];
  static const dailyExport = ['DailyEnergySell', 'DailyGridExport', 'DailyEnergySold', 'Daily Energy Sell'];
  static const dailyCharge = ['DailyBatteryCharge', 'DailyChargingEnergy', 'Daily Battery Charge', 'DailyCharge'];
  static const dailyDischarge = ['DailyBatteryDischarge', 'DailyDischargingEnergy', 'Daily Battery Discharge', 'DailyDischarge'];
  static const alertMessage = ['AlertMessage', 'AlarmMessage', 'FaultMessage', 'Alert', 'FaultInformation', 'WarningMessage'];
  static const runningStatus = ['RunningStatus', 'RunStatus', 'InverterStatus', 'Status', 'WorkState'];
  static const workMode = ['WorkMode', 'WorkingMode', 'EnergyPattern'];
}

/// Narrow, whitelisted numeric sample of a device — one row per device per
/// data timestamp in `device_samples`.
class DeviceSample {
  const DeviceSample({
    required this.deviceSn,
    required this.ts,
    this.soc,
    this.batteryW,
    this.batteryV,
    this.batteryTemp,
    this.pvW,
    this.pv1W,
    this.pv2W,
    this.pv3W,
    this.pv4W,
    this.loadW,
    this.gridW,
    this.gridHz,
    this.gridV,
    this.inverterTemp,
    this.dailyGenKwh,
    this.dailyConsKwh,
    this.dailyImportKwh,
    this.dailyExportKwh,
    this.dailyChargeKwh,
    this.dailyDischargeKwh,
    this.totalGenKwh,
  });

  final String deviceSn;
  final int ts;
  final double? soc;
  final double? batteryW;
  final double? batteryV;
  final double? batteryTemp;
  final double? pvW;
  final double? pv1W;
  final double? pv2W;
  final double? pv3W;
  final double? pv4W;
  final double? loadW;

  /// Signed grid power as reported by the inverter (sign convention varies;
  /// positive usually = import on Deye hybrids).
  final double? gridW;
  final double? gridHz;
  final double? gridV;
  final double? inverterTemp;
  final double? dailyGenKwh;
  final double? dailyConsKwh;
  final double? dailyImportKwh;
  final double? dailyExportKwh;
  final double? dailyChargeKwh;
  final double? dailyDischargeKwh;
  final double? totalGenKwh;

  /// True when the grid is present (voltage or frequency reported).
  bool get gridPresent => (gridHz != null && gridHz! > 40) || (gridV != null && gridV! > 100);

  bool get isEmpty => soc == null && batteryW == null && pvW == null && loadW == null && gridW == null && dailyGenKwh == null;

  /// Builds a sample from a `/device/latest` result. Returns null when the
  /// device carries no data timestamp.
  static DeviceSample? fromLatest(DeviceLatest l) {
    final ts = l.collectionTs;
    if (ts == null) return null;
    final pv1 = l.value(MeasureKeys.pv1);
    final pv2 = l.value(MeasureKeys.pv2);
    final pv3 = l.value(MeasureKeys.pv3);
    final pv4 = l.value(MeasureKeys.pv4);
    var pv = l.value(MeasureKeys.pvPower);
    if (pv == null && (pv1 != null || pv2 != null || pv3 != null || pv4 != null)) {
      pv = (pv1 ?? 0) + (pv2 ?? 0) + (pv3 ?? 0) + (pv4 ?? 0);
    }
    return DeviceSample(
      deviceSn: l.deviceSn,
      ts: ts,
      soc: l.value(MeasureKeys.soc),
      batteryW: l.value(MeasureKeys.batteryPower),
      batteryV: l.value(MeasureKeys.batteryVoltage),
      batteryTemp: l.value(MeasureKeys.batteryTemp),
      pvW: pv,
      pv1W: pv1,
      pv2W: pv2,
      pv3W: pv3,
      pv4W: pv4,
      loadW: l.value(MeasureKeys.loadPower),
      gridW: l.value(MeasureKeys.gridPower),
      gridHz: l.value(MeasureKeys.gridFrequency),
      gridV: l.value(MeasureKeys.gridVoltage),
      inverterTemp: l.value(MeasureKeys.inverterTemp),
      dailyGenKwh: l.value(MeasureKeys.dailyGeneration),
      dailyConsKwh: l.value(MeasureKeys.dailyConsumption),
      dailyImportKwh: l.value(MeasureKeys.dailyImport),
      dailyExportKwh: l.value(MeasureKeys.dailyExport),
      dailyChargeKwh: l.value(MeasureKeys.dailyCharge),
      dailyDischargeKwh: l.value(MeasureKeys.dailyDischarge),
      totalGenKwh: l.value(MeasureKeys.totalGeneration),
    );
  }

  factory DeviceSample.fromRow(Map<String, Object?> r) => DeviceSample(
        deviceSn: r['device_sn'] as String,
        ts: r['ts'] as int,
        soc: asDouble(r['soc']),
        batteryW: asDouble(r['battery_w']),
        batteryV: asDouble(r['battery_v']),
        batteryTemp: asDouble(r['battery_temp']),
        pvW: asDouble(r['pv_w']),
        pv1W: asDouble(r['pv1_w']),
        pv2W: asDouble(r['pv2_w']),
        pv3W: asDouble(r['pv3_w']),
        pv4W: asDouble(r['pv4_w']),
        loadW: asDouble(r['load_w']),
        gridW: asDouble(r['grid_w']),
        gridHz: asDouble(r['grid_hz']),
        gridV: asDouble(r['grid_v']),
        inverterTemp: asDouble(r['inverter_temp']),
        dailyGenKwh: asDouble(r['daily_gen_kwh']),
        dailyConsKwh: asDouble(r['daily_cons_kwh']),
        dailyImportKwh: asDouble(r['daily_import_kwh']),
        dailyExportKwh: asDouble(r['daily_export_kwh']),
        dailyChargeKwh: asDouble(r['daily_charge_kwh']),
        dailyDischargeKwh: asDouble(r['daily_discharge_kwh']),
        totalGenKwh: asDouble(r['total_gen_kwh']),
      );

  Map<String, Object?> toRow() => {
        'device_sn': deviceSn,
        'ts': ts,
        'soc': soc,
        'battery_w': batteryW,
        'battery_v': batteryV,
        'battery_temp': batteryTemp,
        'pv_w': pvW,
        'pv1_w': pv1W,
        'pv2_w': pv2W,
        'pv3_w': pv3W,
        'pv4_w': pv4W,
        'load_w': loadW,
        'grid_w': gridW,
        'grid_hz': gridHz,
        'grid_v': gridV,
        'inverter_temp': inverterTemp,
        'daily_gen_kwh': dailyGenKwh,
        'daily_cons_kwh': dailyConsKwh,
        'daily_import_kwh': dailyImportKwh,
        'daily_export_kwh': dailyExportKwh,
        'daily_charge_kwh': dailyChargeKwh,
        'daily_discharge_kwh': dailyDischargeKwh,
        'total_gen_kwh': totalGenKwh,
      };
}
