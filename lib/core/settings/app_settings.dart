import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret user preferences.
class AppSettings {
  const AppSettings({
    this.pollIntervalMinutes = 5,
    this.alertIntervalMinutes = 15,
    this.staleAfterMinutes = 60,
    this.retentionDays = 90,
    this.demoMode = false,
    this.keepScreenOn = true,
    this.co2FactorKgPerKwh = 0.70,
    this.dieselLitresPerKwh = 0.27,
    this.schoolDayStartHour = 8,
    this.schoolDayEndHour = 14,
    this.darkMode = false,
    this.autoSync = true,
    this.collectDeviceReadings = true,
    this.maxConcurrentRequests = 4,
    this.stationLatestIntervalMinutes = 15,
    this.alertFleetIntervalMinutes = 60,
    this.backfillFrames = true,
    this.alertStationPath,
    this.alertDevicePath,
  });

  final int pollIntervalMinutes;
  final int alertIntervalMinutes;
  final int staleAfterMinutes;
  final int retentionDays;
  final bool demoMode;
  final bool keepScreenOn;

  /// Grid emission factor. Lebanon's grid plus diesel generators is
  /// carbon-intensive; 0.70 kg CO₂/kWh is a conservative blended figure.
  final double co2FactorKgPerKwh;

  /// Litres of diesel a generator burns per kWh (typical 0.25–0.30).
  final double dieselLitresPerKwh;
  final int schoolDayStartHour;
  final int schoolDayEndHour;
  final bool darkMode;
  final bool autoSync;
  final bool collectDeviceReadings;
  final int maxConcurrentRequests;

  /// How often `/station/latest` is polled for every plant (heavier than the
  /// batched device sweep, so slower by default).
  final int stationLatestIntervalMinutes;

  /// How often cloud alarms are fetched for *all* plants (alarm plants are
  /// refreshed every [alertIntervalMinutes]).
  final int alertFleetIntervalMinutes;

  /// Fetch yesterday's intraday frames for every plant once a night.
  final bool backfillFrames;

  /// Advanced: override the alert endpoint paths (null = auto-probe).
  final String? alertStationPath;
  final String? alertDevicePath;

  Duration get stationLatestInterval => Duration(minutes: stationLatestIntervalMinutes);
  Duration get alertFleetInterval => Duration(minutes: alertFleetIntervalMinutes);

  Duration get pollInterval => Duration(minutes: pollIntervalMinutes);
  Duration get alertInterval => Duration(minutes: alertIntervalMinutes);
  Duration get staleAfter => Duration(minutes: staleAfterMinutes);

  AppSettings copyWith({
    int? pollIntervalMinutes,
    int? alertIntervalMinutes,
    int? staleAfterMinutes,
    int? retentionDays,
    bool? demoMode,
    bool? keepScreenOn,
    double? co2FactorKgPerKwh,
    double? dieselLitresPerKwh,
    int? schoolDayStartHour,
    int? schoolDayEndHour,
    bool? darkMode,
    bool? autoSync,
    bool? collectDeviceReadings,
    int? maxConcurrentRequests,
    int? stationLatestIntervalMinutes,
    int? alertFleetIntervalMinutes,
    bool? backfillFrames,
    String? alertStationPath,
    String? alertDevicePath,
    bool clearAlertPaths = false,
  }) =>
      AppSettings(
        pollIntervalMinutes: pollIntervalMinutes ?? this.pollIntervalMinutes,
        alertIntervalMinutes: alertIntervalMinutes ?? this.alertIntervalMinutes,
        staleAfterMinutes: staleAfterMinutes ?? this.staleAfterMinutes,
        retentionDays: retentionDays ?? this.retentionDays,
        demoMode: demoMode ?? this.demoMode,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        co2FactorKgPerKwh: co2FactorKgPerKwh ?? this.co2FactorKgPerKwh,
        dieselLitresPerKwh: dieselLitresPerKwh ?? this.dieselLitresPerKwh,
        schoolDayStartHour: schoolDayStartHour ?? this.schoolDayStartHour,
        schoolDayEndHour: schoolDayEndHour ?? this.schoolDayEndHour,
        darkMode: darkMode ?? this.darkMode,
        autoSync: autoSync ?? this.autoSync,
        collectDeviceReadings: collectDeviceReadings ?? this.collectDeviceReadings,
        maxConcurrentRequests: maxConcurrentRequests ?? this.maxConcurrentRequests,
        stationLatestIntervalMinutes: stationLatestIntervalMinutes ?? this.stationLatestIntervalMinutes,
        alertFleetIntervalMinutes: alertFleetIntervalMinutes ?? this.alertFleetIntervalMinutes,
        backfillFrames: backfillFrames ?? this.backfillFrames,
        alertStationPath: clearAlertPaths ? null : (alertStationPath ?? this.alertStationPath),
        alertDevicePath: clearAlertPaths ? null : (alertDevicePath ?? this.alertDevicePath),
      );

  static const _prefix = 'settings.';

  static Future<AppSettings> load(SharedPreferences prefs) async {
    const d = AppSettings();
    return AppSettings(
      pollIntervalMinutes: prefs.getInt('${_prefix}pollIntervalMinutes') ?? d.pollIntervalMinutes,
      alertIntervalMinutes: prefs.getInt('${_prefix}alertIntervalMinutes') ?? d.alertIntervalMinutes,
      staleAfterMinutes: prefs.getInt('${_prefix}staleAfterMinutes') ?? d.staleAfterMinutes,
      retentionDays: prefs.getInt('${_prefix}retentionDays') ?? d.retentionDays,
      demoMode: prefs.getBool('${_prefix}demoMode') ?? d.demoMode,
      keepScreenOn: prefs.getBool('${_prefix}keepScreenOn') ?? d.keepScreenOn,
      co2FactorKgPerKwh: prefs.getDouble('${_prefix}co2FactorKgPerKwh') ?? d.co2FactorKgPerKwh,
      dieselLitresPerKwh: prefs.getDouble('${_prefix}dieselLitresPerKwh') ?? d.dieselLitresPerKwh,
      schoolDayStartHour: prefs.getInt('${_prefix}schoolDayStartHour') ?? d.schoolDayStartHour,
      schoolDayEndHour: prefs.getInt('${_prefix}schoolDayEndHour') ?? d.schoolDayEndHour,
      darkMode: prefs.getBool('${_prefix}darkMode') ?? d.darkMode,
      autoSync: prefs.getBool('${_prefix}autoSync') ?? d.autoSync,
      collectDeviceReadings: prefs.getBool('${_prefix}collectDeviceReadings') ?? d.collectDeviceReadings,
      maxConcurrentRequests: prefs.getInt('${_prefix}maxConcurrentRequests') ?? d.maxConcurrentRequests,
      stationLatestIntervalMinutes: prefs.getInt('${_prefix}stationLatestIntervalMinutes') ?? d.stationLatestIntervalMinutes,
      alertFleetIntervalMinutes: prefs.getInt('${_prefix}alertFleetIntervalMinutes') ?? d.alertFleetIntervalMinutes,
      backfillFrames: prefs.getBool('${_prefix}backfillFrames') ?? d.backfillFrames,
      alertStationPath: prefs.getString('${_prefix}alertStationPath'),
      alertDevicePath: prefs.getString('${_prefix}alertDevicePath'),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setInt('${_prefix}pollIntervalMinutes', pollIntervalMinutes);
    await prefs.setInt('${_prefix}alertIntervalMinutes', alertIntervalMinutes);
    await prefs.setInt('${_prefix}staleAfterMinutes', staleAfterMinutes);
    await prefs.setInt('${_prefix}retentionDays', retentionDays);
    await prefs.setBool('${_prefix}demoMode', demoMode);
    await prefs.setBool('${_prefix}keepScreenOn', keepScreenOn);
    await prefs.setDouble('${_prefix}co2FactorKgPerKwh', co2FactorKgPerKwh);
    await prefs.setDouble('${_prefix}dieselLitresPerKwh', dieselLitresPerKwh);
    await prefs.setInt('${_prefix}schoolDayStartHour', schoolDayStartHour);
    await prefs.setInt('${_prefix}schoolDayEndHour', schoolDayEndHour);
    await prefs.setBool('${_prefix}darkMode', darkMode);
    await prefs.setBool('${_prefix}autoSync', autoSync);
    await prefs.setBool('${_prefix}collectDeviceReadings', collectDeviceReadings);
    await prefs.setInt('${_prefix}maxConcurrentRequests', maxConcurrentRequests);
    await prefs.setInt('${_prefix}stationLatestIntervalMinutes', stationLatestIntervalMinutes);
    await prefs.setInt('${_prefix}alertFleetIntervalMinutes', alertFleetIntervalMinutes);
    await prefs.setBool('${_prefix}backfillFrames', backfillFrames);
    if (alertStationPath == null || alertStationPath!.isEmpty) {
      await prefs.remove('${_prefix}alertStationPath');
    } else {
      await prefs.setString('${_prefix}alertStationPath', alertStationPath!);
    }
    if (alertDevicePath == null || alertDevicePath!.isEmpty) {
      await prefs.remove('${_prefix}alertDevicePath');
    } else {
      await prefs.setString('${_prefix}alertDevicePath', alertDevicePath!);
    }
  }
}
