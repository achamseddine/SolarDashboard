import '../db/alert_dao.dart';
import '../db/station_dao.dart';
import 'alert.dart';
import 'station.dart';

/// Everything the dashboard knows about one school.
class StationInsight {
  const StationInsight({
    required this.station,
    this.latest,
    required this.status,
    this.statusSince,
    this.dataAgeSeconds,
    this.todayGenKwh,
    this.todayConsKwh,
    this.todayImportKwh,
    this.todayExportKwh,
    this.yieldTodaySoFar,
    this.yieldLastDay,
    this.yield7d,
    this.yield30d,
    this.peerMedianYield7d,
    this.performanceRatio7d,
    this.selfSufficiency7d,
    this.availability7d,
    this.availability30d,
    this.outages30d = 0,
    this.currentOutage,
    this.activeAlerts = 0,
    this.highestAlert,
    this.socNow,
    this.socMinToday,
    this.hoursBelow20Today,
    this.batteryCyclesProxy7d,
    this.completeness7d,
    this.daysWithData7d = 0,
    this.gridHoursToday,
    this.lastError,
    this.devices = 0,
    this.devicesOffline = 0,
    this.trend = const [],
  });

  final Station station;
  final StationLatest? latest;
  final StationStatus status;
  final int? statusSince;
  final int? dataAgeSeconds;
  final double? todayGenKwh;
  final double? todayConsKwh;
  final double? todayImportKwh;
  final double? todayExportKwh;

  /// kWh/kWp so far today (not comparable across schools before sunset).
  final double? yieldTodaySoFar;

  /// kWh/kWp on the last complete day.
  final double? yieldLastDay;

  /// Mean kWh/kWp/day over the last 7 / 30 complete days with data.
  final double? yield7d;
  final double? yield30d;

  /// Median 7-day yield of peers in the same governorate (≥ 5 peers) or the fleet.
  final double? peerMedianYield7d;

  /// yield7d / peerMedianYield7d.
  final double? performanceRatio7d;
  final double? selfSufficiency7d;

  /// Share of time not OFFLINE/STALE over the last 7 / 30 days (0–1).
  final double? availability7d;
  final double? availability30d;
  final int outages30d;

  /// Duration of the current outage when the plant is down.
  final Duration? currentOutage;
  final int activeAlerts;
  final AlertLevel? highestAlert;
  final double? socNow;
  final double? socMinToday;
  final double? hoursBelow20Today;

  /// 7-day discharge kWh / nominal battery kWh (equivalent full cycles).
  final double? batteryCyclesProxy7d;

  /// Mean intraday data completeness over the last 7 days (0–100).
  final double? completeness7d;
  final int daysWithData7d;

  /// Hours today with grid voltage/frequency present (EDL availability).
  final double? gridHoursToday;
  final String? lastError;

  /// Devices known for this plant, and how many report offline.
  final int devices;
  final int devicesOffline;

  /// Today's generation curve (mean W per hour), for the list sparkline.
  final List<double> trend;

  /// Some devices offline while the plant itself still reports — what the
  /// DeyeCloud console calls "partial offline".
  bool get isPartiallyOffline => devicesOffline > 0 && devicesOffline < devices && !status.isDown;

  int get id => station.id;
  String get name => station.name;
  String get region => station.region ?? 'Unassigned';
  double? get kwp => station.installedCapacityKw;
  StationSnapshot? get snapshot => latest?.snapshot;
  bool get isDown => status.isDown;
  bool get isUnderPerformer => performanceRatio7d != null && performanceRatio7d! < 0.5 && daysWithData7d >= 3 && !isDown;
}

/// Governorate roll-up.
class RegionInsight {
  const RegionInsight({
    required this.name,
    required this.stations,
    required this.online,
    required this.offline,
    required this.alarm,
    required this.stale,
    required this.unknown,
    required this.kwp,
    required this.generationNowW,
    required this.consumptionNowW,
    required this.todayGenKwh,
    required this.todayConsKwh,
    required this.activeAlerts,
    this.availability7d,
    this.medianYield7d,
    this.selfSufficiency7d,
  });

  final String name;
  final int stations;
  final int online;
  final int offline;
  final int alarm;
  final int stale;
  final int unknown;
  final double kwp;
  final double generationNowW;
  final double consumptionNowW;
  final double todayGenKwh;
  final double todayConsKwh;
  final int activeAlerts;
  final double? availability7d;
  final double? medianYield7d;
  final double? selfSufficiency7d;

  double get onlineShare => stations == 0 ? 0 : (online + alarm) / stations;
}

/// Fleet-wide picture computed from the local database.
class FleetInsights {
  const FleetInsights({
    required this.generatedAt,
    required this.stations,
    required this.regions,
    required this.counts,
    required this.reportingStations,
    this.dataTsMin,
    this.dataTsMax,
    required this.generationNowW,
    required this.consumptionNowW,
    required this.importNowW,
    required this.exportNowW,
    required this.chargeNowW,
    required this.dischargeNowW,
    this.socMedian,
    required this.socHistogram,
    required this.installedKwp,
    required this.reportingKwp,
    this.capacityUtilisation,
    required this.today,
    required this.last7d,
    required this.last30d,
    required this.lifetime,
    required this.dailySeries30d,
    required this.monthlySeries12m,
    required this.co2FactorKgPerKwh,
    required this.dieselLitresPerKwh,
    required this.activeAlertsByLevel,
    required this.topAlertNames,
    required this.mostAlarmingStations,
    required this.newAlertsPerDay,
    this.alertMttrMedianSeconds,
    required this.alertsOpenOver7d,
    this.availability7d,
    this.availability30d,
    required this.outages7d,
    this.outageMttrMedianSeconds,
    required this.dataAgeHistogram,
    required this.stationsWithErrors,
    this.fleetMedianYield7d,
    this.gridHoursTodayMean,
    required this.completenessMean7d,
  });

  final DateTime generatedAt;
  final List<StationInsight> stations;
  final List<RegionInsight> regions;
  final Map<StationStatus, int> counts;

  /// Stations whose newest data is within the stale threshold.
  final int reportingStations;
  final int? dataTsMin;
  final int? dataTsMax;
  final double generationNowW;
  final double consumptionNowW;
  final double importNowW;
  final double exportNowW;
  final double chargeNowW;
  final double dischargeNowW;
  final double? socMedian;

  /// SOC buckets 0-20, 20-40, 40-60, 60-80, 80-100 (reporting plants).
  final List<int> socHistogram;
  final double installedKwp;
  final double reportingKwp;

  /// generation_now / reporting kWp (0–1+).
  final double? capacityUtilisation;
  final FleetEnergyDay today;
  final FleetEnergyDay last7d;
  final FleetEnergyDay last30d;
  final FleetEnergyDay lifetime;
  final List<FleetEnergyDay> dailySeries30d;
  final List<FleetEnergyDay> monthlySeries12m;
  final double co2FactorKgPerKwh;
  final double dieselLitresPerKwh;
  final Map<AlertLevel, int> activeAlertsByLevel;
  final List<AlertNameCount> topAlertNames;
  final List<StationAlertCount> mostAlarmingStations;
  final Map<String, int> newAlertsPerDay;
  final double? alertMttrMedianSeconds;
  final int alertsOpenOver7d;
  final double? availability7d;
  final double? availability30d;
  final int outages7d;
  final double? outageMttrMedianSeconds;

  /// Buckets: `<15 min`, `15–60 min`, `1–6 h`, `6–24 h`, `>24 h`, `never`.
  final Map<String, int> dataAgeHistogram;
  final int stationsWithErrors;
  final double? fleetMedianYield7d;
  final double? gridHoursTodayMean;
  final double? completenessMean7d;

  int get totalStations => stations.length;
  int count(StationStatus s) => counts[s] ?? 0;
  int get activeAlerts => activeAlertsByLevel.values.fold(0, (a, b) => a + b);

  // Environmental (self-consumed generation only).
  /// Plants reporting but with at least one device offline.
  int get partiallyOffline => stations.where((s) => s.isPartiallyOffline).length;

  /// Plants with at least one active alarm, and those with none.
  int get withAlerts => stations.where((s) => s.activeAlerts > 0).length;
  int get withoutAlerts => stations.length - withAlerts;

  /// Generation of the current calendar month (kWh), from the monthly series.
  double get monthGenerationKwh => monthlySeries12m.isEmpty ? 0 : monthlySeries12m.last.generationKwh;

  double get co2AvoidedTodayKg => today.selfConsumedKwh * co2FactorKgPerKwh;
  double get co2Avoided30dKg => last30d.selfConsumedKwh * co2FactorKgPerKwh;
  double get co2AvoidedLifetimeKg => lifetime.selfConsumedKwh * co2FactorKgPerKwh;
  double get dieselAvoided30dL => last30d.selfConsumedKwh * dieselLitresPerKwh;
  double get dieselAvoidedLifetimeL => lifetime.selfConsumedKwh * dieselLitresPerKwh;

  double? get selfSufficiencyToday => today.selfSufficiency;
  double? get selfSufficiency7d => last7d.selfSufficiency;
  double? get selfSufficiency30d => last30d.selfSufficiency;
  double? get selfConsumption30d => last30d.generationKwh < 1 ? null : (last30d.selfConsumedKwh / last30d.generationKwh).clamp(0, 1);

  List<StationInsight> get underPerformers => stations.where((s) => s.isUnderPerformer).toList()
    ..sort((a, b) => (a.performanceRatio7d ?? 0).compareTo(b.performanceRatio7d ?? 0));

  List<StationInsight> get downStations => stations.where((s) => s.isDown).toList()
    ..sort((a, b) => (b.currentOutage ?? Duration.zero).compareTo(a.currentOutage ?? Duration.zero));

  List<StationInsight> get lowSocStations => stations.where((s) => s.socNow != null && s.socNow! < 20 && !s.isDown).toList()
    ..sort((a, b) => a.socNow!.compareTo(b.socNow!));

  List<StationInsight> topByYield7d(int n) {
    final ranked = stations.where((s) => s.yield7d != null && s.daysWithData7d >= 3).toList()..sort((a, b) => b.yield7d!.compareTo(a.yield7d!));
    return ranked.take(n).toList();
  }

  List<StationInsight> bottomByYield7d(int n) {
    final ranked = stations.where((s) => s.yield7d != null && s.daysWithData7d >= 3).toList()..sort((a, b) => a.yield7d!.compareTo(b.yield7d!));
    return ranked.take(n).toList();
  }

  List<StationInsight> topByGenerationToday(int n) {
    final ranked = stations.where((s) => s.todayGenKwh != null).toList()..sort((a, b) => b.todayGenKwh!.compareTo(a.todayGenKwh!));
    return ranked.take(n).toList();
  }

  /// Plants with active high-level alarms.
  List<StationInsight> get criticalStations => stations.where((s) => s.highestAlert == AlertLevel.high).toList()
    ..sort((a, b) => b.activeAlerts.compareTo(a.activeAlerts));
}
