import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api/json_utils.dart';

enum AlertLevel {
  low(1, 'Low'),
  medium(2, 'Medium'),
  high(3, 'High');

  const AlertLevel(this.value, this.label);
  final int value;
  final String label;

  static AlertLevel fromValue(int? v) => AlertLevel.values.firstWhere((l) => l.value == v, orElse: () => AlertLevel.medium);

  static AlertLevel fromApi(Object? v) {
    if (v == null) return AlertLevel.medium;
    final n = asInt(v);
    if (n != null) {
      if (n <= 1) return AlertLevel.low;
      if (n >= 3) return AlertLevel.high;
      return AlertLevel.medium;
    }
    final s = v.toString().toUpperCase();
    if (s.contains('HIGH') || s.contains('CRIT') || s.contains('SEVERE') || s.contains('ERROR') || s.contains('FAULT') || s.contains('URGENT')) {
      return AlertLevel.high;
    }
    if (s.contains('LOW') || s.contains('INFO') || s.contains('NOTICE') || s.contains('PROMPT')) return AlertLevel.low;
    return AlertLevel.medium;
  }
}

/// Origin of an alarm row.
enum AlertSource {
  cloud, // DeyeCloud alert list endpoints
  derived, // synthesised locally from device state / rules
  demo;

  String get db => name;
  static AlertSource fromDb(String? v) => AlertSource.values.firstWhere((s) => s.name == v, orElse: () => AlertSource.cloud);
}

enum AlertStatus {
  active,
  recovered;

  String get db => name.toUpperCase();
  static AlertStatus fromDb(String? v) => (v ?? '').toUpperCase() == 'RECOVERED' ? AlertStatus.recovered : AlertStatus.active;
}

/// An alarm reported by DeyeCloud for a plant or device.
class SolarAlert {
  const SolarAlert({
    required this.id,
    this.stationId,
    this.stationName,
    this.deviceSn,
    this.deviceType,
    this.level = AlertLevel.medium,
    this.code,
    this.name,
    this.description,
    this.startTs,
    this.endTs,
    this.status = AlertStatus.active,
    this.acknowledged = false,
    this.firstSeenAt = 0,
    this.source = AlertSource.cloud,
    this.raw,
  });

  final String id;
  final int? stationId;
  final String? stationName;
  final String? deviceSn;
  final String? deviceType;
  final AlertLevel level;
  final String? code;
  final String? name;
  final String? description;
  final int? startTs;
  final int? endTs;
  final AlertStatus status;
  final bool acknowledged;
  final int firstSeenAt;
  final AlertSource source;
  final Map<String, Object?>? raw;

  bool get isActive => status == AlertStatus.active;

  String get title => name ?? code ?? 'Alarm';

  /// Parses one alert row. [stationId]/[stationName] come from the request
  /// context when the row does not repeat them.
  static SolarAlert? fromApi(Map<String, Object?> j, {int? stationId, String? stationName, String? deviceSn, required int now, tz.Location? location}) {
    final sn = asString(pick(j, ['deviceSn', 'sn', 'serialNo'])) ?? deviceSn;
    final code = asString(pick(j, ['alertCode', 'code', 'alarmCode', 'faultCode', 'errorCode']));
    final name = asString(pick(j, ['alertName', 'name', 'alarmName', 'alertContent', 'content', 'title', 'message', 'msg']));
    final startTs = asEpochSeconds(pick(j, ['startTime', 'alertTime', 'occurTime', 'startTimestamp', 'createTime', 'time', 'timestamp']), location: location);
    final endTs = asEpochSeconds(pick(j, ['endTime', 'recoverTime', 'recoveryTime', 'endTimestamp', 'clearTime']), location: location);
    if (code == null && name == null && startTs == null) return null;
    final explicitId = asString(pick(j, ['alertId', 'id', 'alarmId', 'recordId']));
    final id = explicitId != null ? 'cloud:$explicitId' : 'cloud:${sha1.convert(utf8.encode('${sn ?? stationId}|${code ?? name}|${startTs ?? 'undated'}')).toString()}';
    final statusRaw = asString(pick(j, ['status', 'state', 'alertStatus']))?.toUpperCase();
    AlertStatus status;
    if (endTs != null && endTs > 0) {
      status = AlertStatus.recovered;
    } else if (statusRaw != null &&
        (statusRaw.contains('RECOVER') || statusRaw.contains('CLEAR') || statusRaw.contains('RESOLVE') || statusRaw.contains('CLOSED') || statusRaw == '0')) {
      status = AlertStatus.recovered;
    } else {
      status = AlertStatus.active;
    }
    return SolarAlert(
      id: id,
      stationId: asInt(pick(j, ['stationId', 'plantId'])) ?? stationId,
      stationName: asString(pick(j, ['stationName', 'plantName'])) ?? stationName,
      deviceSn: sn,
      deviceType: asString(pick(j, ['deviceType', 'type']))?.toUpperCase(),
      level: AlertLevel.fromApi(pick(j, ['level', 'alertLevel', 'alarmLevel', 'severity', 'grade'])),
      code: code,
      name: name,
      description: asString(pick(j, ['description', 'desc', 'suggestion', 'detail', 'reason', 'solution'])),
      startTs: startTs,
      endTs: endTs,
      status: status,
      firstSeenAt: now,
      raw: j,
    );
  }

  factory SolarAlert.fromRow(Map<String, Object?> r) => SolarAlert(
        id: r['id'] as String,
        stationId: asInt(r['station_id']),
        stationName: r['station_name'] as String?,
        deviceSn: r['device_sn'] as String?,
        deviceType: r['device_type'] as String?,
        level: AlertLevel.fromValue(asInt(r['level'])),
        code: r['code'] as String?,
        name: r['name'] as String?,
        description: r['description'] as String?,
        startTs: asInt(r['start_ts']),
        endTs: asInt(r['end_ts']),
        status: AlertStatus.fromDb(r['status'] as String?),
        acknowledged: (asInt(r['acknowledged']) ?? 0) == 1,
        firstSeenAt: asInt(r['first_seen_at']) ?? 0,
        source: AlertSource.fromDb(r['source'] as String?),
        raw: r['raw_json'] is String ? asMap(jsonDecode(r['raw_json'] as String)) : null,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'station_id': stationId,
        'station_name': stationName,
        'device_sn': deviceSn,
        'device_type': deviceType,
        'level': level.value,
        'code': code,
        'name': name,
        'description': description,
        'start_ts': startTs,
        'end_ts': endTs,
        'status': status.db,
        'acknowledged': acknowledged ? 1 : 0,
        'first_seen_at': firstSeenAt,
        'source': source.db,
        'raw_json': raw == null ? null : jsonEncode(raw),
      };

  SolarAlert copyWith({AlertStatus? status, bool? acknowledged, int? endTs, String? stationName}) => SolarAlert(
        id: id,
        stationId: stationId,
        stationName: stationName ?? this.stationName,
        deviceSn: deviceSn,
        deviceType: deviceType,
        level: level,
        code: code,
        name: name,
        description: description,
        startTs: startTs,
        endTs: endTs ?? this.endTs,
        status: status ?? this.status,
        acknowledged: acknowledged ?? this.acknowledged,
        firstSeenAt: firstSeenAt,
        source: source,
        raw: raw,
      );
}
