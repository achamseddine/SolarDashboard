import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../api/deye_api.dart';
import '../models/alert.dart';
import '../models/device.dart';
import '../models/station.dart';
import '../utils/app_time.dart';

/// Synthetic DeyeCloud for demos, screenshots and tests: ~60 Lebanese public
/// schools with realistic PV / load / battery behaviour, a few faults, and
/// history. Deterministic for a given [seed].
class DemoDeyeApi implements DeyeApi {
  DemoDeyeApi({int seed = 7, DateTime Function()? clock, this.latency = const Duration(milliseconds: 15), int schools = 60})
      : _clock = clock ?? DateTime.now {
    _schools = _buildSchools(math.Random(seed), schools);
  }

  final DateTime Function() _clock;
  final Duration latency;
  late final List<_School> _schools;
  int _requests = 0;

  @override
  int get requestCount => _requests;
  @override
  bool get alertsUnsupported => false;
  @override
  String? get alertsUnsupportedReason => null;

  /// Station ids of the synthetic fleet.
  List<int> get stationIds => [for (final s in _schools) s.id];

  Future<void> _tick() async {
    _requests++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<void> authenticate() => _tick();

  @override
  Future<Map<String, Object?>> accountInfo() async {
    await _tick();
    return {'code': '1000000', 'success': true, 'email': 'demo@unicef.org', 'orgInfoList': [{'companyId': 1000001, 'companyName': 'UNICEF Lebanon (demo)'}]};
  }

  @override
  Future<List<Station>> listStations() async {
    await _tick();
    final now = _nowTs();
    return [
      for (final s in _schools)
        Station.fromApi({
          'id': s.id,
          'name': s.name,
          'locationAddress': s.address,
          'locationLat': s.lat,
          'locationLng': s.lng,
          'regionTimezone': 'Asia/Beirut',
          'gridInterconnectionType': 'BATTERY_BACKUP',
          'installedCapacity': s.kwp,
          'startOperatingTime': s.commissionedTs,
          'createdDate': s.commissionedTs - 86400 * 20,
          'ownerName': 'MEHE',
          'contactPhone': '+961 1 000 000',
          'batterySOC': s.state(now).soc,
          'generationPower': s.isOffline ? null : s.state(now).pvW,
          'lastUpdateTime': s.dataTs(now),
        }),
    ];
  }

  @override
  Future<List<Device>> listStationDevices(List<int> stationIds) async {
    await _tick();
    final now = _nowTs();
    final out = <Device>[];
    for (final s in _schools.where((s) => stationIds.contains(s.id))) {
      for (var i = 0; i < s.inverters; i++) {
        out.add(Device.fromApi({
          'deviceSn': s.inverterSn(i),
          'deviceId': s.id * 10 + i,
          'deviceType': 'INVERTER',
          'productId': 'SUN-12K-SG04LP3-EU',
          'productName': 'Deye SUN-12K-SG04LP3 hybrid',
          'collectorSn': '27${s.id.toString().padLeft(6, '0')}$i',
          'connectStatus': s.deviceState,
          'stationId': s.id,
          'collectionTime': s.dataTs(now),
        })!);
      }
      out.add(Device.fromApi({
        'deviceSn': s.batterySn,
        'deviceId': s.id * 10 + 9,
        'deviceType': 'BATTERY',
        'productId': 'SE-G5.1-PRO',
        'productName': 'Deye SE-G5.1 Pro ×${s.batteryModules}',
        'capacity': s.batteryKwh,
        'connectStatus': s.deviceState,
        'stationId': s.id,
        'collectionTime': s.dataTs(now),
      })!);
      out.add(Device.fromApi({
        'deviceSn': '27${s.id.toString().padLeft(6, '0')}0',
        'deviceType': 'COLLECTOR',
        'productName': 'Deye Wi-Fi logger',
        'connectStatus': s.isOffline ? 3 : 1,
        'stationId': s.id,
      })!);
    }
    return out;
  }

  @override
  Future<StationLatestResult> stationLatest(int stationId, {tz.Location? location}) async {
    await _tick();
    final s = _school(stationId);
    final now = _nowTs();
    final st = s.state(now);
    final raw = <String, Object?>{
      'code': '1000000',
      'success': true,
      'requestId': 'demo-$stationId-$now',
      'generationPower': st.pvW,
      'consumptionPower': st.loadW,
      'gridPower': st.gridW < 0 ? -st.gridW : 0.0,
      'purchasePower': st.gridW > 0 ? st.gridW : 0.0,
      'wirePower': st.gridW,
      'chargePower': st.batteryW > 0 ? st.batteryW : 0.0,
      'dischargePower': st.batteryW < 0 ? -st.batteryW : 0.0,
      'batteryPower': st.batteryW,
      'batterySOC': st.soc,
      'lastUpdateTime': s.dataTs(now),
    };
    return StationLatestResult(snapshot: StationSnapshot.fromApi(raw, stationId: stationId, fetchedAt: now, location: location), raw: raw);
  }

  @override
  Future<List<StationSnapshot>> stationFrames(int stationId, String day, {tz.Location? location}) async {
    await _tick();
    final s = _school(stationId);
    final loc = location ?? AppTime.beirut;
    final start = AppTime.dayStart(day, loc);
    final end = math.min(AppTime.dayEnd(day, loc), s.dataTs(_nowTs()));
    final out = <StationSnapshot>[];
    for (var t = start; t < end; t += 600) {
      final st = s.state(t);
      out.add(StationSnapshot(
        stationId: stationId,
        ts: t,
        fetchedAt: _nowTs(),
        source: SnapshotSource.history,
        generationW: st.pvW,
        consumptionW: st.loadW,
        gridImportW: st.gridW > 0 ? st.gridW : 0,
        gridExportW: st.gridW < 0 ? -st.gridW : 0,
        wireW: st.gridW,
        chargeW: st.batteryW > 0 ? st.batteryW : 0,
        dischargeW: st.batteryW < 0 ? -st.batteryW : 0,
        batteryW: st.batteryW,
        batterySoc: st.soc,
      ));
    }
    return out;
  }

  @override
  Future<List<StationEnergy>> stationDaily(int stationId, String startDay, String endDayExclusive, {tz.Location? location}) async {
    await _tick();
    final s = _school(stationId);
    final out = <StationEnergy>[];
    var day = startDay;
    while (day.compareTo(endDayExclusive) < 0) {
      out.add(s.dayEnergy(day));
      day = AppTime.addDays(day, 1);
    }
    return out;
  }

  @override
  Future<List<StationEnergy>> stationMonthly(int stationId, String startMonth, String endMonth) async {
    await _tick();
    final s = _school(stationId);
    final out = <StationEnergy>[];
    var m = startMonth;
    final commissioned = AppTime.monthOf(s.commissionedTs);
    while (m.compareTo(endMonth) <= 0) {
      if (m.compareTo(commissioned) >= 0) {
        final days = DateTime.utc(int.parse(m.substring(0, 4)), int.parse(m.substring(5, 7)) + 1, 0).day;
        var g = 0.0, c = 0.0, i = 0.0, e = 0.0, ch = 0.0, dc = 0.0;
        for (var d = 1; d <= days; d++) {
          final de = s.dayEnergy('$m-${d.toString().padLeft(2, '0')}');
          g += de.generationKwh ?? 0;
          c += de.consumptionKwh ?? 0;
          i += de.gridImportKwh ?? 0;
          e += de.gridExportKwh ?? 0;
          ch += de.chargeKwh ?? 0;
          dc += de.dischargeKwh ?? 0;
        }
        out.add(StationEnergy(stationId: stationId, period: m, generationKwh: g, consumptionKwh: c, gridImportKwh: i, gridExportKwh: e, chargeKwh: ch, dischargeKwh: dc, source: EnergySource.history));
      }
      m = AppTime.addMonths(m, 1);
    }
    return out;
  }

  @override
  Future<List<DeviceLatest>> deviceLatest(List<String> serials, {tz.Location? location}) async {
    await _tick();
    final now = _nowTs();
    final out = <DeviceLatest>[];
    for (final sn in serials) {
      final s = _schools.where((s) => s.ownsSn(sn)).firstOrNull;
      if (s == null) continue;
      final st = s.state(now);
      final today = s.dayEnergySoFar(now);
      if (sn == s.batterySn) {
        out.add(DeviceLatest.fromApi({
          'deviceSn': sn,
          'deviceType': 'BATTERY',
          'deviceState': s.deviceState,
          'stationId': s.id,
          'collectionTime': s.dataTs(now),
          'dataList': [
            {'key': 'BMS_SOC', 'value': st.soc.toStringAsFixed(1), 'unit': '%', 'name': 'BMS SOC'},
            {'key': 'BMSVoltage', 'value': (48 + st.soc / 100 * 6).toStringAsFixed(1), 'unit': 'V'},
            {'key': 'BMSCurrent', 'value': (st.batteryW / 52).toStringAsFixed(1), 'unit': 'A'},
            {'key': 'BMSTemperature', 'value': st.batteryTemp.toStringAsFixed(1), 'unit': '℃'},
            {'key': 'BMSChargeVoltage', 'value': '56.0', 'unit': 'V'},
            {'key': 'BMSDisChargeVoltage', 'value': '46.0', 'unit': 'V'},
          ],
        }, fetchedAt: now, location: location)!);
        continue;
      }
      final idx = s.inverterIndex(sn);
      final share = 1 / s.inverters;
      final pv = st.pvW * share;
      final strings = s.stringPowers(idx, pv, now);
      out.add(DeviceLatest.fromApi({
        'deviceSn': sn,
        'deviceType': 'INVERTER',
        'deviceState': s.deviceState,
        'stationId': s.id,
        'productId': 1,
        'collectionTime': s.dataTs(now),
        'dataList': [
          {'key': 'SN', 'value': sn, 'unit': ''},
          {'key': 'RunningStatus', 'value': s.deviceState == 2 ? 'Fault' : 'Normal'},
          {'key': 'WorkMode', 'value': 'Zero export to load'},
          {'key': 'AlertMessage', 'value': s.alertMessage ?? ''},
          {'key': 'SOC', 'value': st.soc.toStringAsFixed(1), 'unit': '%'},
          {'key': 'BatteryPower', 'value': (-st.batteryW * share).toStringAsFixed(0), 'unit': 'W'},
          {'key': 'BatteryVoltage', 'value': (48 + st.soc / 100 * 6).toStringAsFixed(1), 'unit': 'V'},
          {'key': 'Temperature- Battery', 'value': st.batteryTemp.toStringAsFixed(1), 'unit': '℃'},
          {'key': 'TotalDCInputPower', 'value': pv.toStringAsFixed(0), 'unit': 'W'},
          {'key': 'DCPowerPV1', 'value': strings[0].toStringAsFixed(0), 'unit': 'W'},
          {'key': 'DCPowerPV2', 'value': strings[1].toStringAsFixed(0), 'unit': 'W'},
          {'key': 'DCVoltagePV1', 'value': (strings[0] > 10 ? 380 + strings[0] / 100 : 0).toStringAsFixed(0), 'unit': 'V'},
          {'key': 'DCVoltagePV2', 'value': (strings[1] > 10 ? 375 + strings[1] / 100 : 0).toStringAsFixed(0), 'unit': 'V'},
          {'key': 'TotalConsumptionPower', 'value': (st.loadW * share).toStringAsFixed(0), 'unit': 'W'},
          {'key': 'TotalGridPower', 'value': (st.gridW * share).toStringAsFixed(0), 'unit': 'W'},
          {'key': 'GridFrequency', 'value': st.gridPresent ? '50.0' : '0.0', 'unit': 'Hz'},
          {'key': 'GridVoltageL1', 'value': st.gridPresent ? '228' : '0', 'unit': 'V'},
          {'key': 'AC Temperature', 'value': st.inverterTemp.toStringAsFixed(1), 'unit': '℃'},
          {'key': 'DailyActiveProduction', 'value': ((today.generationKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'DailyConsumption', 'value': ((today.consumptionKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'DailyEnergyBuy', 'value': ((today.gridImportKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'DailyEnergySell', 'value': ((today.gridExportKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'DailyBatteryCharge', 'value': ((today.chargeKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'DailyBatteryDischarge', 'value': ((today.dischargeKwh ?? 0) * share).toStringAsFixed(2), 'unit': 'kWh'},
          {'key': 'TotalActiveProduction', 'value': (s.lifetimeKwh(now) * share).toStringAsFixed(0), 'unit': 'kWh'},
        ],
      }, fetchedAt: now, location: location)!);
    }
    return out;
  }

  @override
  Future<List<String>> deviceMeasurePoints(String deviceSn) async {
    await _tick();
    return MeasureKeys.soc.take(1).followedBy(['BatteryPower', 'TotalDCInputPower', 'TotalConsumptionPower', 'TotalGridPower', 'DailyActiveProduction']).toList();
  }

  @override
  Future<List<DeviceLatest>> deviceHistory(String deviceSn, String day, List<String> measurePoints, {tz.Location? location}) async {
    await _tick();
    return const [];
  }

  @override
  Future<List<SolarAlert>> stationAlerts(int stationId, {required int from, required int to, String? stationName, tz.Location? location}) async {
    await _tick();
    final s = _school(stationId);
    final now = _nowTs();
    return [
      for (final a in s.cloudAlerts(now))
        if (a.startTs != null && a.startTs! >= from && a.startTs! <= to) a,
    ];
  }

  @override
  Future<List<SolarAlert>> deviceAlerts(String deviceSn, {required int from, required int to, tz.Location? location}) async {
    await _tick();
    return const [];
  }

  _School _school(int id) => _schools.firstWhere((s) => s.id == id, orElse: () => throw StateError('unknown station $id'));

  int _nowTs() => _clock().millisecondsSinceEpoch ~/ 1000;

  // ------------------------------------------------------------------ data

  static const List<(String, String, double, double)> _towns = [
    // (town, governorate, lat, lng)
    ('Achrafieh', 'Beirut', 33.8886, 35.5163), ('Ras Beirut', 'Beirut', 33.8975, 35.4795), ('Mazraa', 'Beirut', 33.8760, 35.4930), ('Bachoura', 'Beirut', 33.8890, 35.5060),
    ('Baabda', 'Mount Lebanon', 33.8339, 35.5442), ('Aley', 'Mount Lebanon', 33.8070, 35.5967), ('Beit Mery', 'Mount Lebanon', 33.8520, 35.6050), ('Broummana', 'Mount Lebanon', 33.8810, 35.6210),
    ('Deir el Qamar', 'Mount Lebanon', 33.6980, 35.5620), ('Damour', 'Mount Lebanon', 33.7300, 35.4490), ('Bourj Hammoud', 'Mount Lebanon', 33.8910, 35.5410), ('Choueifat', 'Mount Lebanon', 33.8120, 35.5200),
    ('Bhamdoun', 'Mount Lebanon', 33.7960, 35.6520), ('Barouk', 'Mount Lebanon', 33.6870, 35.6640),
    ('Jounieh', 'Keserwan-Jbeil', 33.9808, 35.6178), ('Jbeil', 'Keserwan-Jbeil', 34.1230, 35.6510), ('Ajaltoun', 'Keserwan-Jbeil', 33.9770, 35.6800), ('Amchit', 'Keserwan-Jbeil', 34.1440, 35.6440), ('Ghazir', 'Keserwan-Jbeil', 34.0110, 35.6620),
    ('Tripoli', 'North', 34.4367, 35.8497), ('Zgharta', 'North', 34.3980, 35.8960), ('Batroun', 'North', 34.2550, 35.6580), ('Amioun', 'North', 34.3000, 35.8090), ('Bcharre', 'North', 34.2510, 36.0120), ('Minieh', 'North', 34.4620, 35.9370), ('Sir el Danniyeh', 'North', 34.3910, 36.0600),
    ('Halba', 'Akkar', 34.5480, 36.0790), ('Qoubaiyat', 'Akkar', 34.5670, 36.2740), ('Bebnine', 'Akkar', 34.4990, 35.9760), ('Wadi Khaled', 'Akkar', 34.6120, 36.3960), ('Fnaydek', 'Akkar', 34.5270, 36.2520),
    ('Baalbek', 'Baalbek-Hermel', 34.0060, 36.2110), ('Hermel', 'Baalbek-Hermel', 34.3940, 36.3850), ('Deir el Ahmar', 'Baalbek-Hermel', 34.1170, 36.1300), ('Arsal', 'Baalbek-Hermel', 34.1780, 36.4200), ('Labweh', 'Baalbek-Hermel', 34.1950, 36.3530),
    ('Zahle', 'Bekaa', 33.8463, 35.9020), ('Rachaya', 'Bekaa', 33.5030, 35.8440), ('Joub Jannine', 'Bekaa', 33.6290, 35.7830), ('Bar Elias', 'Bekaa', 33.7770, 35.9000), ('Anjar', 'Bekaa', 33.7280, 35.9330), ('Machghara', 'Bekaa', 33.5330, 35.6500), ('Qab Elias', 'Bekaa', 33.7900, 35.8240),
    ('Saida', 'South', 33.5630, 35.3690), ('Tyre', 'South', 33.2700, 35.2040), ('Jezzine', 'South', 33.5430, 35.5850), ('Ghazieh', 'South', 33.5220, 35.3660), ('Sarafand', 'South', 33.4530, 35.2930), ('Bint Jbeil', 'South', 33.1210, 35.4320), ('Qana', 'South', 33.2090, 35.2990),
    ('Nabatieh', 'Nabatieh', 33.3770, 35.4840), ('Marjayoun', 'Nabatieh', 33.3610, 35.5910), ('Hasbaya', 'Nabatieh', 33.3980, 35.6850), ('Khiam', 'Nabatieh', 33.3280, 35.6110), ('Kfar Tebnit', 'Nabatieh', 33.3550, 35.5220), ('Chebaa', 'Nabatieh', 33.3300, 35.7700),
    ('Douma', 'North', 34.2060, 35.8500), ('Ehden', 'North', 34.2930, 35.9640), ('Kfardebian', 'Keserwan-Jbeil', 33.9990, 35.8130), ('Tebnine', 'South', 33.2000, 35.4090), ('Taanayel', 'Bekaa', 33.7920, 35.8720),
  ];

  static const _schoolTypes = ['Public School', 'Public High School', 'Intermediate Public School', 'Mixed Public School', 'Technical Public School'];

  static List<_School> _buildSchools(math.Random rnd, int count) {
    final out = <_School>[];
    for (var i = 0; i < count; i++) {
      final t = _towns[i % _towns.length];
      final kwp = [8.0, 10.0, 12.0, 15.0, 18.0, 20.0, 24.0, 30.0][rnd.nextInt(8)];
      final inverters = kwp > 12 ? 2 : 1;
      final modules = (kwp / 4).round().clamp(2, 8);
      final fault = rnd.nextDouble();
      out.add(_School(
        id: 3000 + i,
        name: '${_schoolTypes[rnd.nextInt(_schoolTypes.length)]} of ${t.$1}${i >= _towns.length ? ' ${i ~/ _towns.length + 1}' : ''}',
        address: '${t.$1}, ${t.$2}, Lebanon',
        lat: t.$3 + (rnd.nextDouble() - 0.5) * 0.01,
        lng: t.$4 + (rnd.nextDouble() - 0.5) * 0.01,
        kwp: kwp,
        inverters: inverters,
        batteryModules: modules,
        commissionedTs: DateTime.utc(2024, 1 + rnd.nextInt(18) ~/ 2, 1 + rnd.nextInt(27)).millisecondsSinceEpoch ~/ 1000,
        isOffline: fault < 0.05,
        isStale: fault >= 0.05 && fault < 0.08,
        hasFault: fault >= 0.08 && fault < 0.13,
        weakBattery: fault >= 0.13 && fault < 0.18,
        stringFault: fault >= 0.18 && fault < 0.22,
        shading: 0.75 + rnd.nextDouble() * 0.25,
        loadFactor: 0.25 + rnd.nextDouble() * 0.35,
        gridSeed: rnd.nextInt(1 << 30),
        rndSeed: rnd.nextInt(1 << 30),
      ));
    }
    return out;
  }
}

class _State {
  const _State({required this.pvW, required this.loadW, required this.gridW, required this.batteryW, required this.soc, required this.gridPresent, required this.batteryTemp, required this.inverterTemp});
  final double pvW;
  final double loadW;

  /// + import / − export.
  final double gridW;

  /// + charging / − discharging.
  final double batteryW;
  final double soc;
  final bool gridPresent;
  final double batteryTemp;
  final double inverterTemp;
}

class _School {
  _School({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.kwp,
    required this.inverters,
    required this.batteryModules,
    required this.commissionedTs,
    required this.isOffline,
    required this.isStale,
    required this.hasFault,
    required this.weakBattery,
    required this.stringFault,
    required this.shading,
    required this.loadFactor,
    required this.gridSeed,
    required this.rndSeed,
  });

  final int id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double kwp;
  final int inverters;
  final int batteryModules;
  final int commissionedTs;
  final bool isOffline;
  final bool isStale;
  final bool hasFault;
  final bool weakBattery;
  final bool stringFault;
  final double shading;
  final double loadFactor;
  final int gridSeed;
  final int rndSeed;

  double get batteryKwh => batteryModules * 5.12;
  String inverterSn(int i) => '$id${(i + 1).toString().padLeft(2, '0')}SG04';
  String get batterySn => '${id}BAT';
  bool ownsSn(String sn) => sn == batterySn || inverterIndex(sn) >= 0;
  int inverterIndex(String sn) {
    for (var i = 0; i < inverters; i++) {
      if (inverterSn(i) == sn) return i;
    }
    return -1;
  }

  int get deviceState => isOffline ? 3 : (hasFault ? 2 : 1);
  String? get alertMessage => hasFault ? 'F13 Grid mode changed / DC over-voltage' : null;

  /// Data timestamp: offline plants froze days ago, stale ones hours ago.
  int dataTs(int now) {
    if (isOffline) return now - 3 * 86400 - (id % 7) * 3600;
    if (isStale) return now - 2 * 3600 - (id % 50) * 60;
    return now - (now % 300) - 60;
  }

  /// Deterministic per-day weather factor 0.35–1.0.
  double weather(String day) {
    final h = day.hashCode ^ rndSeed;
    final r = math.Random(h).nextDouble();
    return r < 0.15 ? 0.35 + r * 2 : 0.7 + (r - 0.15) * 0.35;
  }

  bool gridAt(int ts) {
    // EDL supply: ~6 h/day in a few windows, varying by day and plant.
    final loc = AppTime.beirut;
    final d = AppTime.fromEpoch(ts, loc);
    final r = math.Random(gridSeed ^ (d.year * 400 + d.month * 31 + d.day));
    final start1 = r.nextInt(6);
    final start2 = 10 + r.nextInt(6);
    final len = 2 + r.nextInt(3);
    final h = d.hour;
    return (h >= start1 && h < start1 + len) || (h >= start2 && h < start2 + len);
  }

  _State state(int ts) {
    final loc = AppTime.beirut;
    final d = AppTime.fromEpoch(ts, loc);
    final day = AppTime.formatDay(d);
    final hour = d.hour + d.minute / 60;
    final sun = math.max(0.0, math.sin((hour - 6) / 13 * math.pi));
    var pv = kwp * 1000 * sun * sun * weather(day) * shading;
    if (stringFault) pv *= 0.6;
    if (isOffline) pv = 0;
    final weekday = d.weekday <= 5;
    final schoolHours = weekday && hour >= 7.5 && hour < 14.5;
    var load = kwp * 1000 * loadFactor * (schoolHours ? 1.0 : 0.12) * (1 + 0.15 * math.sin(hour * 3));
    if (isOffline) load = 0;
    final grid = gridAt(ts);
    // SOC follows a daily cycle: charges through the day, discharges evening/night.
    var soc = 35 + 55 * (0.5 + 0.5 * math.sin((hour - 9) / 24 * 2 * math.pi));
    if (weakBattery) soc = math.max(8, soc - 40);
    soc = soc.clamp(5, 100).toDouble();
    var battery = pv - load; // surplus charges
    if (battery > 0 && soc >= 99) battery = 0;
    if (battery < 0 && soc <= 10) battery = 0;
    battery = battery.clamp(-kwp * 500, kwp * 500).toDouble();
    var gridW = load - pv - (-battery);
    // What battery can't cover comes from the grid (if present) or is shed.
    gridW = pv + (battery < 0 ? -battery : 0) >= load + (battery > 0 ? battery : 0) ? 0 : load + (battery > 0 ? battery : 0) - pv - (battery < 0 ? -battery : 0);
    if (!grid) {
      gridW = 0;
    } else if (gridW <= 0 && soc < 60 && hour < 9) {
      gridW = kwp * 200; // grid charging at night
      battery = gridW;
    }
    final export = grid && soc >= 99 && pv > load ? pv - load : 0.0;
    if (export > 0) {
      gridW = -export;
      battery = 0;
    }
    return _State(
      pvW: pv.roundToDouble(),
      loadW: load.roundToDouble(),
      gridW: gridW.roundToDouble(),
      batteryW: battery.roundToDouble(),
      soc: soc,
      gridPresent: grid,
      batteryTemp: 24 + soc / 20 + (weakBattery ? 12 : 0) + 4 * sun,
      inverterTemp: 32 + 25 * sun + (hasFault ? 20 : 0),
    );
  }

  StationEnergy dayEnergy(String day) {
    final loc = AppTime.beirut;
    final start = AppTime.dayStart(day, loc);
    if (start < commissionedTs) return StationEnergy(stationId: id, period: day, generationKwh: 0, consumptionKwh: 0, gridImportKwh: 0, gridExportKwh: 0, chargeKwh: 0, dischargeKwh: 0, source: EnergySource.history);
    return _integrate(start, AppTime.dayEnd(day, loc), day);
  }

  StationEnergy dayEnergySoFar(int now) {
    final loc = AppTime.beirut;
    final day = AppTime.dayOf(now, loc);
    return _integrate(AppTime.dayStart(day, loc), math.min(now, AppTime.dayEnd(day, loc)), day);
  }

  StationEnergy _integrate(int start, int end, String day) {
    var g = 0.0, c = 0.0, imp = 0.0, exp = 0.0, ch = 0.0, dc = 0.0;
    const step = 900;
    for (var t = start; t < end; t += step) {
      final s = state(t);
      final h = step / 3600 / 1000;
      g += s.pvW * h;
      c += s.loadW * h;
      if (s.gridW > 0) imp += s.gridW * h;
      if (s.gridW < 0) exp += -s.gridW * h;
      if (s.batteryW > 0) ch += s.batteryW * h;
      if (s.batteryW < 0) dc += -s.batteryW * h;
    }
    return StationEnergy(
      stationId: id,
      period: day,
      generationKwh: _r(g),
      consumptionKwh: _r(c),
      gridImportKwh: _r(imp),
      gridExportKwh: _r(exp),
      chargeKwh: _r(ch),
      dischargeKwh: _r(dc),
      fullPowerHours: _r(g / kwp),
      source: EnergySource.history,
    );
  }

  double lifetimeKwh(int now) => math.max(0, (now - commissionedTs) / 86400) * kwp * 4.2;

  List<double> stringPowers(int inverterIdx, double pv, int now) {
    if (stringFault && inverterIdx == 0) return [pv, pv * 0.02];
    return [pv * 0.52, pv * 0.48];
  }

  List<SolarAlert> cloudAlerts(int now) {
    final out = <SolarAlert>[];
    final r = math.Random(rndSeed);
    if (hasFault) {
      out.add(SolarAlert(
        id: 'cloud:demo-$id-f13',
        stationId: id,
        stationName: name,
        deviceSn: inverterSn(0),
        deviceType: 'INVERTER',
        level: AlertLevel.high,
        code: 'F13',
        name: 'DC over-voltage / grid mode changed',
        description: 'Check PV string voltage and grid configuration.',
        startTs: now - 3600 * (6 + r.nextInt(40)),
        status: AlertStatus.active,
        firstSeenAt: now,
        source: AlertSource.cloud,
        raw: const {'demo': true},
      ));
    }
    if (weakBattery) {
      out.add(SolarAlert(
        id: 'cloud:demo-$id-bms',
        stationId: id,
        stationName: name,
        deviceSn: batterySn,
        deviceType: 'BATTERY',
        level: AlertLevel.medium,
        code: 'W31',
        name: 'BMS communication warning',
        description: 'Battery reported repeated low-voltage warnings.',
        startTs: now - 3600 * (2 + r.nextInt(20)),
        status: AlertStatus.active,
        firstSeenAt: now,
        source: AlertSource.cloud,
        raw: const {'demo': true},
      ));
    }
    // A recovered alarm from the past few days for most plants.
    if (r.nextDouble() < 0.6) {
      final start = now - 86400 * (1 + r.nextInt(6)) - 3600 * r.nextInt(12);
      out.add(SolarAlert(
        id: 'cloud:demo-$id-gridloss-$start',
        stationId: id,
        stationName: name,
        deviceSn: inverterSn(0),
        deviceType: 'INVERTER',
        level: AlertLevel.low,
        code: 'F62',
        name: 'Grid loss',
        description: 'Grid voltage out of range (EDL cut).',
        startTs: start,
        endTs: start + 1800 + r.nextInt(7200),
        status: AlertStatus.recovered,
        firstSeenAt: now,
        source: AlertSource.cloud,
        raw: const {'demo': true},
      ));
    }
    return out;
  }

  static double _r(double v) => (v * 100).round() / 100;
}
