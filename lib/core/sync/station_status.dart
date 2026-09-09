import '../models/alert.dart';
import '../models/device.dart';
import '../models/station.dart';
import '../utils/app_time.dart';
import '../utils/format.dart';

/// Pure status derivation for one plant.
///
/// Precedence:
/// 1. an explicit cloud status (`connectionStatus`) when it is not unknown;
/// 2. else the inverters' `deviceState`: any ALARM → alarm, all OFFLINE →
///    offline, any ONLINE → online, none known → unknown;
/// 3. freshness: when the newest *data* timestamp is older than [staleAfter]
///    an ONLINE/ALARM/UNKNOWN result becomes STALE. Fetch times are never
///    used for freshness.
StationStatus deriveStationStatus({
  required StationStatus apiStatus,
  required Iterable<DeviceStatus> inverterStates,
  required int? freshnessTs,
  required int now,
  required Duration staleAfter,
}) {
  StationStatus status;
  if (apiStatus != StationStatus.unknown) {
    status = apiStatus;
  } else {
    final states = inverterStates.toList();
    if (states.any((s) => s == DeviceStatus.alarm)) {
      status = StationStatus.alarm;
    } else if (states.isNotEmpty && states.every((s) => s == DeviceStatus.offline)) {
      status = StationStatus.offline;
    } else if (states.any((s) => s == DeviceStatus.online)) {
      status = StationStatus.online;
    } else {
      status = StationStatus.unknown;
    }
  }
  if (status != StationStatus.offline) {
    if (freshnessTs == null) {
      if (status == StationStatus.online) status = StationStatus.unknown;
    } else if (now - freshnessTs > staleAfter.inSeconds) {
      status = StationStatus.stale;
    }
  }
  return status;
}

/// Context needed to evaluate derived-alert rules for one plant.
class StationRuleContext {
  const StationRuleContext({
    required this.station,
    required this.status,
    required this.statusSince,
    required this.inverters,
    required this.latest,
    required this.now,
    this.staleAfter = const Duration(minutes: 60),
  });

  final Station station;
  final StationStatus status;

  /// Start of the current status event (epoch seconds), if known.
  final int? statusSince;

  /// Latest readings of the plant's inverters/batteries.
  final List<DeviceLatest> inverters;

  /// Aggregated plant power, if available.
  final StationSnapshot? latest;
  final int now;
  final Duration staleAfter;
}

/// Alarms synthesised locally from device readings and plant status. Each
/// rule yields a stable id so the alarm can be closed when the condition
/// clears.
class DerivedAlertRules {
  DerivedAlertRules._();

  static const _noise = {'', '0', 'none', 'normal', 'no', 'null', 'ok', '-', 'no alarm', 'no fault', 'noalarm', 'nofault'};

  static List<SolarAlert> evaluate(StationRuleContext c) {
    final out = <SolarAlert>[];
    final s = c.station;
    final loc = s.location;
    final hour = AppTime.hourOf(c.now, loc);
    final midday = hour >= 10 && hour < 14;

    // Plant offline / stale.
    if (c.status == StationStatus.offline || c.status == StationStatus.stale) {
      final since = c.statusSince ?? c.now;
      final age = c.now - since;
      if (age >= c.staleAfter.inSeconds) {
        out.add(_alert(
          id: 'derived:s${s.id}:PLANT_OFFLINE',
          station: s,
          level: age > 86400 ? AlertLevel.high : AlertLevel.medium,
          code: 'PLANT_OFFLINE',
          name: c.status == StationStatus.offline ? 'Plant offline' : 'No data from plant',
          description: 'No fresh data for ${Fmt.duration(Duration(seconds: age))}.',
          startTs: since,
          now: c.now,
        ));
      }
    }

    for (final d in c.inverters) {
      final isInverter = (d.deviceType ?? '').contains('INVERTER');
      // Device reports alarm state.
      if (d.status == DeviceStatus.alarm) {
        final msg = d.text(MeasureKeys.alertMessage);
        out.add(_alert(
          id: 'derived:d${d.deviceSn}:DEVICE_ALARM',
          station: s,
          deviceSn: d.deviceSn,
          deviceType: d.deviceType,
          level: AlertLevel.high,
          code: 'DEVICE_ALARM',
          name: '${_typeLabel(d.deviceType)} reports alarm state',
          description: msg != null && !_noise.contains(msg.trim().toLowerCase()) ? msg : null,
          startTs: d.collectionTs ?? c.now,
          now: c.now,
        ));
      } else {
        final msg = d.text(MeasureKeys.alertMessage);
        if (msg != null && !_noise.contains(msg.trim().toLowerCase())) {
          out.add(_alert(
            id: 'derived:d${d.deviceSn}:ALERT_MESSAGE',
            station: s,
            deviceSn: d.deviceSn,
            deviceType: d.deviceType,
            level: AlertLevel.high,
            code: 'ALERT_MESSAGE',
            name: msg.trim(),
            description: '${_typeLabel(d.deviceType)} alert message',
            startTs: d.collectionTs ?? c.now,
            now: c.now,
          ));
        }
      }
      if (d.status == DeviceStatus.offline || d.collectionTs == null) continue;
      final fresh = c.now - d.collectionTs! <= c.staleAfter.inSeconds;
      if (!fresh) continue;

      final soc = d.value(MeasureKeys.soc);
      if (soc != null && soc < 10) {
        out.add(_alert(
          id: 'derived:d${d.deviceSn}:LOW_SOC',
          station: s,
          deviceSn: d.deviceSn,
          deviceType: d.deviceType,
          level: soc < 5 ? AlertLevel.high : AlertLevel.medium,
          code: 'LOW_SOC',
          name: 'Battery critically low (${soc.toStringAsFixed(0)} %)',
          description: 'State of charge below 10 %. Loads may drop when the grid is absent.',
          startTs: d.collectionTs!,
          now: c.now,
        ));
      }
      final bTemp = d.value(MeasureKeys.batteryTemp);
      if (bTemp != null && bTemp > 50) {
        out.add(_alert(
          id: 'derived:d${d.deviceSn}:BATTERY_TEMP',
          station: s,
          deviceSn: d.deviceSn,
          deviceType: d.deviceType,
          level: AlertLevel.high,
          code: 'BATTERY_TEMP',
          name: 'Battery temperature high (${bTemp.toStringAsFixed(0)} °C)',
          description: 'Battery temperature above 50 °C. Check ventilation and cooling.',
          startTs: d.collectionTs!,
          now: c.now,
        ));
      }
      final iTemp = d.value(MeasureKeys.inverterTemp);
      if (iTemp != null && iTemp > 75) {
        out.add(_alert(
          id: 'derived:d${d.deviceSn}:INVERTER_TEMP',
          station: s,
          deviceSn: d.deviceSn,
          deviceType: d.deviceType,
          level: AlertLevel.medium,
          code: 'INVERTER_TEMP',
          name: 'Inverter temperature high (${iTemp.toStringAsFixed(0)} °C)',
          description: 'Heat-sink temperature above 75 °C.',
          startTs: d.collectionTs!,
          now: c.now,
        ));
      }

      // PV string fault at midday: one string far below its siblings.
      if (isInverter && midday) {
        final strings = <(String, double)>[
          for (final e in {'PV1': MeasureKeys.pv1, 'PV2': MeasureKeys.pv2, 'PV3': MeasureKeys.pv3, 'PV4': MeasureKeys.pv4}.entries)
            if (d.value(e.value) case final v?) (e.key, v),
        ];
        if (strings.length >= 2) {
          final maxW = strings.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
          if (maxW > 300) {
            for (final st in strings) {
              if (st.$2 < maxW * 0.05) {
                out.add(_alert(
                  id: 'derived:d${d.deviceSn}:STRING_${st.$1}',
                  station: s,
                  deviceSn: d.deviceSn,
                  deviceType: d.deviceType,
                  level: AlertLevel.medium,
                  code: 'STRING_FAULT',
                  name: 'PV string ${st.$1} not producing',
                  description: '${st.$1} delivers ${st.$2.toStringAsFixed(0)} W while the best string delivers ${maxW.toStringAsFixed(0)} W at midday.',
                  startTs: d.collectionTs!,
                  now: c.now,
                ));
              }
            }
          }
        }
      }
    }

    // Plant-level rules on aggregated power.
    final l = c.latest;
    if (l != null && c.status == StationStatus.online && c.now - l.ts <= c.staleAfter.inSeconds) {
      final kwp = s.installedCapacityKw;
      if (midday && kwp != null && kwp > 0 && (l.generationW ?? 0) < kwp * 1000 * 0.02) {
        out.add(_alert(
          id: 'derived:s${s.id}:NO_GENERATION',
          station: s,
          level: AlertLevel.low,
          code: 'NO_GENERATION',
          name: 'No PV generation at midday',
          description: 'Generation ${Fmt.power(l.generationW)} for ${Fmt.capacity(kwp)} installed. Could be weather, shading, a tripped DC switch or a fault.',
          startTs: l.ts,
          now: c.now,
        ));
      }
      if (l.batteryNetW < -200 && l.importW > 200) {
        out.add(_alert(
          id: 'derived:s${s.id}:DISCHARGE_WHILE_IMPORT',
          station: s,
          level: AlertLevel.low,
          code: 'DISCHARGE_WHILE_IMPORT',
          name: 'Battery discharging while importing from grid',
          description: 'Informational: battery ${Fmt.power(-l.batteryNetW)} out while grid import is ${Fmt.power(l.importW)}. Check work mode / time-of-use settings.',
          startTs: l.ts,
          now: c.now,
        ));
      }
    }
    return out;
  }

  static SolarAlert _alert({
    required String id,
    required Station station,
    String? deviceSn,
    String? deviceType,
    required AlertLevel level,
    required String code,
    required String name,
    String? description,
    required int startTs,
    required int now,
  }) =>
      SolarAlert(
        id: id,
        stationId: station.id,
        stationName: station.name,
        deviceSn: deviceSn,
        deviceType: deviceType,
        level: level,
        code: code,
        name: name,
        description: description,
        startTs: startTs,
        status: AlertStatus.active,
        firstSeenAt: now,
        source: AlertSource.derived,
      );

  static String _typeLabel(String? t) {
    final u = (t ?? '').toUpperCase();
    if (u.contains('INVERTER')) return 'Inverter';
    if (u.contains('BATTERY')) return 'Battery';
    if (u.contains('METER')) return 'Meter';
    if (u.contains('COLLECTOR')) return 'Logger';
    return 'Device';
  }
}

/// Aggregates the inverters of one plant into a station-level snapshot and
/// today's counters. Returns null when no inverter carries a data timestamp.
(StationSnapshot?, TodayEnergy) aggregateInverters(int stationId, List<DeviceLatest> devices, {required int fetchedAt}) {
  final inverters = devices.where((d) => d.collectionTs != null && ((d.deviceType ?? 'INVERTER').contains('INVERTER') || d.deviceType == null)).toList();
  if (inverters.isEmpty) return (null, TodayEnergy.empty);
  double? sum(Iterable<double?> xs) {
    double? acc;
    for (final x in xs) {
      if (x == null) continue;
      acc = (acc ?? 0) + x;
    }
    return acc;
  }

  double? mean(Iterable<double?> xs) {
    final vals = xs.whereType<double>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  final samples = inverters.map(DeviceSample.fromLatest).whereType<DeviceSample>().toList();
  if (samples.isEmpty) return (null, TodayEnergy.empty);
  final ts = samples.map((s) => s.ts).reduce((a, b) => a > b ? a : b);
  final grid = sum(samples.map((s) => s.gridW));
  final battery = sum(samples.map((s) => s.batteryW));
  final snap = StationSnapshot(
    stationId: stationId,
    ts: ts,
    fetchedAt: fetchedAt,
    source: SnapshotSource.device,
    generationW: sum(samples.map((s) => s.pvW)),
    consumptionW: sum(samples.map((s) => s.loadW)),
    // Deye hybrids report grid power positive when importing.
    gridImportW: grid == null ? null : (grid > 0 ? grid : 0),
    gridExportW: grid == null ? null : (grid < 0 ? -grid : 0),
    wireW: grid,
    // Deye hybrids report battery power positive when discharging; store
    // the app convention (positive = charging).
    batteryW: battery == null ? null : -battery,
    chargeW: battery == null ? null : (battery < 0 ? -battery : 0),
    dischargeW: battery == null ? null : (battery > 0 ? battery : 0),
    batterySoc: mean(samples.map((s) => s.soc)),
  );
  final today = TodayEnergy(
    generationKwh: sum(samples.map((s) => s.dailyGenKwh)),
    consumptionKwh: sum(samples.map((s) => s.dailyConsKwh)),
    gridImportKwh: sum(samples.map((s) => s.dailyImportKwh)),
    gridExportKwh: sum(samples.map((s) => s.dailyExportKwh)),
    chargeKwh: sum(samples.map((s) => s.dailyChargeKwh)),
    dischargeKwh: sum(samples.map((s) => s.dailyDischargeKwh)),
  );
  return (snap, today);
}
