import 'package:timezone/timezone.dart' as tz;

import '../models/alert.dart';
import '../models/device.dart';
import '../models/station.dart';

/// Result of `/station/latest`: the parsed snapshot (null when the payload
/// carried no data timestamp) plus the raw envelope for diagnostics.
class StationLatestResult {
  const StationLatestResult({this.snapshot, required this.raw});
  final StationSnapshot? snapshot;
  final Map<String, Object?> raw;
}

/// Abstract DeyeCloud gateway used by the sync engine. Implemented by
/// [DeyeApiClient] (real HTTP) and `DemoDeyeApi` (synthetic data).
abstract class DeyeApi {
  /// Ensures a valid access token exists (no-op when cached).
  Future<void> authenticate();

  /// Raw `/account/info` payload (organisations, company ids …).
  Future<Map<String, Object?>> accountInfo();

  /// Every plant visible to the account (all pages).
  Future<List<Station>> listStations();

  /// Devices of the given plants (all pages, ids chunked as needed).
  Future<List<Device>> listStationDevices(List<int> stationIds);

  /// Real-time power flow of one plant.
  Future<StationLatestResult> stationLatest(int stationId, {tz.Location? location});

  /// Intra-day power frames (granularity 1) of one plant for [day] (`yyyy-MM-dd`).
  Future<List<StationSnapshot>> stationFrames(int stationId, String day, {tz.Location? location});

  /// Daily energy totals (granularity 2) from [startDay] to [endDayExclusive].
  Future<List<StationEnergy>> stationDaily(int stationId, String startDay, String endDayExclusive, {tz.Location? location});

  /// Monthly energy totals (granularity 3) from [startMonth] to [endMonth] inclusive.
  Future<List<StationEnergy>> stationMonthly(int stationId, String startMonth, String endMonth);

  /// Latest measure points of any number of devices (batched by 10). Devices
  /// missing from the response are simply absent from the result.
  Future<List<DeviceLatest>> deviceLatest(List<String> serials, {tz.Location? location});

  /// Measure-point keys a device supports.
  Future<List<String>> deviceMeasurePoints(String deviceSn);

  /// Intra-day measure-point history of one device for [day].
  Future<List<DeviceLatest>> deviceHistory(String deviceSn, String day, List<String> measurePoints, {tz.Location? location});

  /// Alarms of a plant between [from] and [to] (epoch seconds, all pages).
  Future<List<SolarAlert>> stationAlerts(int stationId, {required int from, required int to, String? stationName, tz.Location? location});

  /// Alarms of a device between [from] and [to] (epoch seconds).
  Future<List<SolarAlert>> deviceAlerts(String deviceSn, {required int from, required int to, tz.Location? location});

  /// Number of HTTP requests issued since creation (for the status bar).
  int get requestCount;

  /// True when the alert endpoints were probed and none answered.
  bool get alertsUnsupported;

  /// Human-readable reason when [alertsUnsupported] is true.
  String? get alertsUnsupportedReason;
}
