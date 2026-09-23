import '../api/json_utils.dart';

/// What a managed GWN device is. The cloud reports a product type string that
/// varies by model line, so it is folded into the four roles the indicator
/// framework distinguishes: the gateway, the LAN switches, the Wi-Fi radios,
/// and anything else the account happens to carry.
enum GwnDeviceKind {
  accessPoint('Access point'),
  networkSwitch('Switch'),
  router('Router / firewall'),
  other('Other');

  const GwnDeviceKind(this.label);
  final String label;

  /// Folds a product type or model string into a role.
  static GwnDeviceKind fromAny(String? type, String? model) {
    final t = '${type ?? ''} ${model ?? ''}'.toLowerCase();
    if (t.contains('ap') || t.contains('gwn76') || t.contains('access')) return GwnDeviceKind.accessPoint;
    if (t.contains('switch') || t.contains('gwn78')) return GwnDeviceKind.networkSwitch;
    if (t.contains('router') || t.contains('gateway') || t.contains('firewall') || t.contains('gwn70')) return GwnDeviceKind.router;
    return GwnDeviceKind.other;
  }

  static GwnDeviceKind fromName(String? n) =>
      GwnDeviceKind.values.firstWhere((e) => e.name == n, orElse: () => GwnDeviceKind.other);
}

enum GwnDeviceStatus {
  online('Online'),
  offline('Offline'),
  unknown('Unknown');

  const GwnDeviceStatus(this.label);
  final String label;

  static GwnDeviceStatus fromAny(Object? v) {
    if (v == null) return GwnDeviceStatus.unknown;
    final s = v.toString().toLowerCase();
    if (s == '1' || s == 'true' || s.contains('online') || s.contains('up')) return GwnDeviceStatus.online;
    if (s == '0' || s == 'false' || s.contains('offline') || s.contains('down')) return GwnDeviceStatus.offline;
    return GwnDeviceStatus.unknown;
  }

  static GwnDeviceStatus fromName(String? n) =>
      GwnDeviceStatus.values.firstWhere((e) => e.name == n, orElse: () => GwnDeviceStatus.unknown);
}

/// One GWN network — in this deployment, one school's LAN.
class GwnNetwork {
  const GwnNetwork({
    required this.id,
    required this.name,
    this.cerd,
    this.linkConfidence,
    this.address,
    this.timezone,
    this.lastSeenTs,
  });

  final String id;
  final String name;

  /// The MEHE school this network belongs to, once matched by name.
  final int? cerd;
  final double? linkConfidence;
  final String? address;
  final String? timezone;
  final int? lastSeenTs;

  factory GwnNetwork.fromJson(Map<String, Object?> j) => GwnNetwork(
        id: asString(pick(j, ['id', 'networkId', 'network_id', 'nid'])) ?? '',
        name: asString(pick(j, ['name', 'networkName', 'network_name'])) ?? '',
        address: asString(pick(j, ['address', 'location', 'site'])),
        timezone: asString(pick(j, ['timezone', 'timeZone', 'tz'])),
        lastSeenTs: asEpochSeconds(pick(j, ['lastSeen', 'updateTime', 'updatedAt'])),
      );

  factory GwnNetwork.fromRow(Map<String, Object?> r) => GwnNetwork(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        cerd: r['cerd'] as int?,
        linkConfidence: (r['link_confidence'] as num?)?.toDouble(),
        address: r['address'] as String?,
        timezone: r['timezone'] as String?,
        lastSeenTs: r['last_seen_ts'] as int?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'cerd': cerd,
        'link_confidence': linkConfidence,
        'address': address,
        'timezone': timezone,
        'last_seen_ts': lastSeenTs,
      };

  GwnNetwork withLink(int? cerd, double? confidence) => GwnNetwork(
        id: id,
        name: name,
        cerd: cerd,
        linkConfidence: confidence,
        address: address,
        timezone: timezone,
        lastSeenTs: lastSeenTs,
      );
}

/// One managed device (AP, switch or gateway) in a network.
class GwnDevice {
  const GwnDevice({
    required this.networkId,
    required this.mac,
    required this.name,
    required this.kind,
    required this.status,
    this.model,
    this.firmware,
    this.ip,
    this.uptimeSeconds,
    this.clientCount,
    this.cpuPercent,
    this.memoryPercent,
    this.poePortsTotal,
    this.poePortsActive,
    this.poePortsFailed,
    this.portsUp,
    this.portsDown,
    this.portsError,
    this.lastSeenTs,
  });

  final String networkId;
  final String mac;
  final String name;
  final GwnDeviceKind kind;
  final GwnDeviceStatus status;
  final String? model;
  final String? firmware;
  final String? ip;
  final int? uptimeSeconds;
  final int? clientCount;
  final double? cpuPercent;
  final double? memoryPercent;
  final int? poePortsTotal;
  final int? poePortsActive;
  final int? poePortsFailed;
  final int? portsUp;
  final int? portsDown;
  final int? portsError;
  final int? lastSeenTs;

  bool get isOnline => status == GwnDeviceStatus.online;

  factory GwnDevice.fromJson(Map<String, Object?> j, {String? networkId}) {
    final type = asString(pick(j, ['type', 'deviceType', 'productType', 'product_type']));
    final model = asString(pick(j, ['model', 'productModel', 'deviceModel']));
    return GwnDevice(
      networkId: networkId ?? asString(pick(j, ['networkId', 'network_id', 'nid'])) ?? '',
      mac: (asString(pick(j, ['mac', 'macAddress', 'mac_address', 'deviceMac'])) ?? '').toUpperCase(),
      name: asString(pick(j, ['name', 'deviceName', 'alias'])) ?? '',
      kind: GwnDeviceKind.fromAny(type, model),
      status: GwnDeviceStatus.fromAny(pick(j, ['status', 'online', 'state', 'deviceStatus'])),
      model: model,
      firmware: asString(pick(j, ['firmware', 'version', 'firmwareVersion', 'swVersion'])),
      ip: asString(pick(j, ['ip', 'ipAddress', 'ipv4'])),
      uptimeSeconds: asInt(pick(j, ['uptime', 'upTime', 'runTime'])),
      clientCount: asInt(pick(j, ['clientCount', 'clients', 'clientNum', 'staCount'])),
      cpuPercent: asDouble(pick(j, ['cpu', 'cpuUsage', 'cpuPercent'])),
      memoryPercent: asDouble(pick(j, ['memory', 'memUsage', 'memoryPercent'])),
      poePortsTotal: asInt(pick(j, ['poePortTotal', 'poeTotal'])),
      poePortsActive: asInt(pick(j, ['poePortActive', 'poeActive'])),
      poePortsFailed: asInt(pick(j, ['poePortFault', 'poeFailed'])),
      portsUp: asInt(pick(j, ['portUp', 'portsUp', 'linkUp'])),
      portsDown: asInt(pick(j, ['portDown', 'portsDown', 'linkDown'])),
      portsError: asInt(pick(j, ['portError', 'portsError', 'errPorts'])),
      lastSeenTs: asEpochSeconds(pick(j, ['lastSeen', 'updateTime', 'lastOnline'])),
    );
  }

  factory GwnDevice.fromRow(Map<String, Object?> r) => GwnDevice(
        networkId: r['network_id'] as String,
        mac: r['mac'] as String,
        name: r['name'] as String? ?? '',
        kind: GwnDeviceKind.fromName(r['kind'] as String?),
        status: GwnDeviceStatus.fromName(r['status'] as String?),
        model: r['model'] as String?,
        firmware: r['firmware'] as String?,
        ip: r['ip'] as String?,
        uptimeSeconds: r['uptime_s'] as int?,
        clientCount: r['client_count'] as int?,
        cpuPercent: (r['cpu_percent'] as num?)?.toDouble(),
        memoryPercent: (r['memory_percent'] as num?)?.toDouble(),
        poePortsTotal: r['poe_total'] as int?,
        poePortsActive: r['poe_active'] as int?,
        poePortsFailed: r['poe_failed'] as int?,
        portsUp: r['ports_up'] as int?,
        portsDown: r['ports_down'] as int?,
        portsError: r['ports_error'] as int?,
        lastSeenTs: r['last_seen_ts'] as int?,
      );

  Map<String, Object?> toRow() => {
        'network_id': networkId,
        'mac': mac,
        'name': name,
        'kind': kind.name,
        'status': status.name,
        'model': model,
        'firmware': firmware,
        'ip': ip,
        'uptime_s': uptimeSeconds,
        'client_count': clientCount,
        'cpu_percent': cpuPercent,
        'memory_percent': memoryPercent,
        'poe_total': poePortsTotal,
        'poe_active': poePortsActive,
        'poe_failed': poePortsFailed,
        'ports_up': portsUp,
        'ports_down': portsDown,
        'ports_error': portsError,
        'last_seen_ts': lastSeenTs,
      };
}

/// One network's counters for one day — the grain every usage and uptime
/// indicator in the framework is computed from.
class GwnNetworkDay {
  const GwnNetworkDay({
    required this.networkId,
    required this.day,
    this.wanUpMinutes,
    this.expectedMinutes,
    this.rxBytes,
    this.txBytes,
    this.uniqueClients,
    this.peakClients,
    this.apsOnline,
    this.apsTotal,
    this.activeAps,
    this.teachingHoursBytes,
    this.observations,
    this.onlineObservations,
  });

  final String networkId;

  /// `yyyy-MM-dd`.
  final String day;
  final int? wanUpMinutes;
  final int? expectedMinutes;
  final int? rxBytes;
  final int? txBytes;
  final int? uniqueClients;
  final int? peakClients;
  final int? apsOnline;
  final int? apsTotal;

  /// APs that carried any client traffic that day.
  final int? activeAps;

  /// Bytes inside the defined teaching hours, when the source can split it.
  final int? teachingHoursBytes;

  /// How many times the app looked at this network during the day, and how
  /// many of those it was up. The cloud exposes no history, so uptime is
  /// sampled from the app's own observations rather than reported.
  final int? observations;
  final int? onlineObservations;

  int? get totalBytes => rxBytes == null && txBytes == null ? null : (rxBytes ?? 0) + (txBytes ?? 0);

  double? get uptimeShare {
    // Minutes when the source reports them; otherwise the share of the app's
    // own observations that found the network up.
    final up = wanUpMinutes, exp = expectedMinutes;
    if (up != null && exp != null && exp > 0) return (up / exp).clamp(0.0, 1.0);
    final n = observations, on = onlineObservations;
    if (n == null || on == null || n <= 0) return null;
    return (on / n).clamp(0.0, 1.0);
  }

  factory GwnNetworkDay.fromRow(Map<String, Object?> r) => GwnNetworkDay(
        networkId: r['network_id'] as String,
        day: r['day'] as String,
        wanUpMinutes: r['wan_up_minutes'] as int?,
        expectedMinutes: r['expected_minutes'] as int?,
        rxBytes: r['rx_bytes'] as int?,
        txBytes: r['tx_bytes'] as int?,
        uniqueClients: r['unique_clients'] as int?,
        peakClients: r['peak_clients'] as int?,
        apsOnline: r['aps_online'] as int?,
        apsTotal: r['aps_total'] as int?,
        activeAps: r['active_aps'] as int?,
        teachingHoursBytes: r['teaching_bytes'] as int?,
        observations: r['observations'] as int?,
        onlineObservations: r['online_observations'] as int?,
      );

  Map<String, Object?> toRow() => {
        'network_id': networkId,
        'day': day,
        'wan_up_minutes': wanUpMinutes,
        'expected_minutes': expectedMinutes,
        'rx_bytes': rxBytes,
        'tx_bytes': txBytes,
        'unique_clients': uniqueClients,
        'peak_clients': peakClients,
        'aps_online': apsOnline,
        'aps_total': apsTotal,
        'active_aps': activeAps,
        'teaching_bytes': teachingHoursBytes,
        'observations': observations,
        'online_observations': onlineObservations,
      };
}

/// Traffic split by SSID for one network and day — the framework uses it to
/// separate teacher, student and admin use.
class GwnSsidDay {
  const GwnSsidDay({required this.networkId, required this.day, required this.ssid, this.bytes, this.clients});

  final String networkId;
  final String day;
  final String ssid;
  final int? bytes;
  final int? clients;

  factory GwnSsidDay.fromRow(Map<String, Object?> r) => GwnSsidDay(
        networkId: r['network_id'] as String,
        day: r['day'] as String,
        ssid: r['ssid'] as String,
        bytes: r['bytes'] as int?,
        clients: r['clients'] as int?,
      );

  Map<String, Object?> toRow() => {
        'network_id': networkId,
        'day': day,
        'ssid': ssid,
        'bytes': bytes,
        'clients': clients,
      };
}

enum GwnAlarmLevel {
  critical('Critical'),
  major('Major'),
  minor('Minor'),
  info('Info');

  const GwnAlarmLevel(this.label);
  final String label;

  static GwnAlarmLevel fromAny(Object? v) {
    final s = (v ?? '').toString().toLowerCase();
    if (s.contains('crit') || s == '1' || s == 'high') return GwnAlarmLevel.critical;
    if (s.contains('major') || s == '2' || s == 'medium') return GwnAlarmLevel.major;
    if (s.contains('minor') || s == '3' || s == 'low') return GwnAlarmLevel.minor;
    return GwnAlarmLevel.info;
  }

  static GwnAlarmLevel fromName(String? n) =>
      GwnAlarmLevel.values.firstWhere((e) => e.name == n, orElse: () => GwnAlarmLevel.info);
}

/// One alarm raised by the cloud for a network or device.
class GwnAlarm {
  const GwnAlarm({
    required this.id,
    required this.networkId,
    required this.level,
    required this.message,
    required this.startTs,
    this.deviceMac,
    this.endTs,
  });

  final String id;
  final String networkId;
  final GwnAlarmLevel level;
  final String message;
  final int startTs;
  final String? deviceMac;
  final int? endTs;

  bool get isOpen => endTs == null;

  factory GwnAlarm.fromJson(Map<String, Object?> j, {String? networkId}) => GwnAlarm(
        id: asString(pick(j, ['id', 'alarmId', 'eventId'])) ?? '',
        networkId: networkId ?? asString(pick(j, ['networkId', 'network_id'])) ?? '',
        level: GwnAlarmLevel.fromAny(pick(j, ['level', 'severity', 'priority'])),
        message: asString(pick(j, ['message', 'content', 'description', 'detail'])) ?? '',
        startTs: asEpochSeconds(pick(j, ['time', 'startTime', 'createTime', 'occurTime'])) ?? 0,
        deviceMac: asString(pick(j, ['mac', 'deviceMac', 'macAddress']))?.toUpperCase(),
        endTs: asEpochSeconds(pick(j, ['endTime', 'recoverTime', 'clearTime'])),
      );

  factory GwnAlarm.fromRow(Map<String, Object?> r) => GwnAlarm(
        id: r['id'] as String,
        networkId: r['network_id'] as String,
        level: GwnAlarmLevel.fromName(r['level'] as String?),
        message: r['message'] as String? ?? '',
        startTs: r['start_ts'] as int? ?? 0,
        deviceMac: r['device_mac'] as String?,
        endTs: r['end_ts'] as int?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'network_id': networkId,
        'level': level.name,
        'message': message,
        'start_ts': startTs,
        'device_mac': deviceMac,
        'end_ts': endTs,
      };
}
