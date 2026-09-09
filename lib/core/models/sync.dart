/// Phases of a synchronisation sweep, in execution order.
enum SyncPhase {
  idle('Idle'),
  auth('Signing in'),
  stations('Plant list'),
  devices('Device list'),
  deviceLatest('Device measurements'),
  status('Plant status'),
  latest('Live plant data'),
  daily('Energy history'),
  frames('Intraday backfill'),
  alerts('Alarms'),
  rollup('Aggregates'),
  retention('Housekeeping'),
  paused('Paused (API back-off)'),
  done('Done');

  const SyncPhase(this.label);
  final String label;
}

/// Progress snapshot emitted by the sync engine.
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.running = false,
    this.current = 0,
    this.total = 0,
    this.message,
    this.lastSuccessAt,
    this.lastError,
    this.errorCount = 0,
    this.requestCount = 0,
    this.startedAt,
    this.pausedUntil,
    this.alertsUnsupportedReason,
    this.stationsSynced = 0,
  });

  final SyncPhase phase;
  final bool running;
  final int current;
  final int total;
  final String? message;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final int errorCount;
  final int requestCount;
  final DateTime? startedAt;

  /// Set while the engine waits out an API back-off.
  final DateTime? pausedUntil;

  /// Non-null when the cloud alert endpoints could not be resolved.
  final String? alertsUnsupportedReason;
  final int stationsSynced;

  double? get progress => total <= 0 ? null : (current / total).clamp(0, 1);

  SyncStatus copyWith({
    SyncPhase? phase,
    bool? running,
    int? current,
    int? total,
    String? message,
    bool clearMessage = false,
    DateTime? lastSuccessAt,
    String? lastError,
    bool clearError = false,
    int? errorCount,
    int? requestCount,
    DateTime? startedAt,
    DateTime? pausedUntil,
    bool clearPaused = false,
    String? alertsUnsupportedReason,
    bool clearAlertsUnsupported = false,
    int? stationsSynced,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        running: running ?? this.running,
        current: current ?? this.current,
        total: total ?? this.total,
        message: clearMessage ? null : (message ?? this.message),
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        errorCount: errorCount ?? this.errorCount,
        requestCount: requestCount ?? this.requestCount,
        startedAt: startedAt ?? this.startedAt,
        pausedUntil: clearPaused ? null : (pausedUntil ?? this.pausedUntil),
        alertsUnsupportedReason: clearAlertsUnsupported ? null : (alertsUnsupportedReason ?? this.alertsUnsupportedReason),
        stationsSynced: stationsSynced ?? this.stationsSynced,
      );
}

/// Row of the `sync_log` table.
class SyncLogEntry {
  const SyncLogEntry({
    this.id,
    required this.kind,
    required this.startedAt,
    this.finishedAt,
    this.ok,
    this.items,
    this.message,
  });

  final int? id;
  final String kind;
  final int startedAt;
  final int? finishedAt;
  final bool? ok;
  final int? items;
  final String? message;

  Duration? get duration => finishedAt == null ? null : Duration(seconds: finishedAt! - startedAt);

  factory SyncLogEntry.fromRow(Map<String, Object?> r) => SyncLogEntry(
        id: r['id'] as int?,
        kind: r['kind'] as String,
        startedAt: r['started_at'] as int,
        finishedAt: r['finished_at'] as int?,
        ok: r['ok'] == null ? null : (r['ok'] as int) == 1,
        items: r['items'] as int?,
        message: r['message'] as String?,
      );
}
