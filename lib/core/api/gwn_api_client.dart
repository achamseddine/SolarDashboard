import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/gwn.dart';
import '../models/gwn_credentials.dart';
import 'gwn_api.dart';
import 'gwn_api_exception.dart';
import 'gwn_endpoints.dart';
import 'json_utils.dart';

/// Hands the response body back as text, whatever content type it claims.
///
/// Dio's default transformer parses anything labelled `application/json`, so
/// an HTML error page raises a `FormatException` that surfaces as a
/// transport failure with no status code — which reads as "the network is
/// down" when the server in fact answered 404. Probing endpoints nobody has
/// documented means meeting exactly those bodies, so the client decodes the
/// text itself and keeps the status.
class _TextTransformer extends Transformer {
  @override
  Future<String> transformRequest(RequestOptions options) async {
    final data = options.data;
    return data is String ? data : jsonEncode(data);
  }

  @override
  Future<Object?> transformResponse(RequestOptions options, ResponseBody responseBody) async {
    final bytes = <int>[];
    await for (final chunk in responseBody.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// HTTP client for the GWN Cloud Open API.
///
/// The exact paths, token field names and paging spellings are not confirmed
/// (see [GwnEndpoints]), so the client probes the candidates once per path and
/// remembers the first that answers. [lastProbe] reports what it settled on,
/// which Settings shows so an operator can see what the account actually
/// accepted.
class GwnApiClient implements GwnApi {
  GwnApiClient({required GwnCredentials credentials, Dio? dio})
      : _credentials = credentials,
        _probeAdapter = dio?.httpClientAdapter,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: credentials.baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 40),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              responseType: ResponseType.json,
              validateStatus: (_) => true,
            )) {
    _dio.transformer = _TextTransformer();
  }

  final Dio _dio;

  /// When a transport was injected (tests), probes borrow its adapter so they
  /// reach the same place the client does.
  final HttpClientAdapter? _probeAdapter;
  GwnCredentials _credentials;

  String? _token;
  int? _tokenExpiresAt;
  Future<void>? _authInFlight;

  /// Path that answered, per logical endpoint — for diagnostics.
  final Map<String, String> lastProbe = {};

  /// Paging spelling proven to work, per path.
  final Map<String, ({String page, String size})> _paging = {};

  int _requestCount = 0;
  int get requestCount => _requestCount;

  void updateCredentials(GwnCredentials c) {
    _credentials = c;
    _dio.options.baseUrl = c.baseUrl;
    _token = null;
    _tokenExpiresAt = null;
  }

  @override
  void close() => _dio.close(force: true);

  // -------------------------------------------------------------- auth

  @override
  Future<void> authenticate() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_token != null && (_tokenExpiresAt == null || now < _tokenExpiresAt! - 60)) return;
    return _authInFlight ??= _login().whenComplete(() => _authInFlight = null);
  }

  Future<void> _login() async {
    if (!_credentials.isComplete) {
      throw GwnApiException('GWN Cloud credentials are incomplete', code: 'AUTH');
    }
    // Each probe gets its own transport: a failed attempt used to close the
    // shared one, so every later candidate reported "Dio can't establish a
    // new connection after it was closed" and buried the real first error.
    final attempts = <String>[];
    for (final path in GwnEndpoints.tokenCandidates) {
      for (final fields in GwnEndpoints.tokenFieldSpellings) {
        final probe = _newDio();
        try {
          final json = await _raw('POST', path, dio: probe, body: {
            fields.id: _credentials.appId.trim(),
            fields.secret: _credentials.secretKey.trim(),
            'grant_type': 'client_credentials',
          });
          final token = asString(pick(json, ['access_token', 'accessToken', 'token'])) ??
              asString(pick(asMap(pick(json, ['data', 'result'])), ['access_token', 'accessToken', 'token']));
          if (token == null || token.isEmpty) {
            attempts.add('$path (${fields.id}): answered, but carried no token');
            continue;
          }
          _token = token;
          final ttl = asInt(pick(json, ['expires_in', 'expiresIn', 'expire'])) ??
              asInt(pick(asMap(pick(json, ['data', 'result'])), ['expires_in', 'expiresIn']));
          _tokenExpiresAt = ttl == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 + (ttl * 0.8).round();
          lastProbe['token'] = '$path (${fields.id})';
          return;
        } on GwnApiException catch (e) {
          attempts.add('$path (${fields.id}): ${e.status == null ? e.message : 'HTTP ${e.status}'}');
        } catch (e) {
          attempts.add('$path (${fields.id}): $e');
        } finally {
          probe.close(force: true);
        }
      }
    }
    throw GwnApiException(_loginDiagnosis(attempts), code: 'AUTH');
  }

  /// Turns the probe log into something an operator can act on: whether the
  /// host was reachable at all, whether it rejected the credentials, or
  /// whether it simply has no endpoint at these paths.
  String _loginDiagnosis(List<String> attempts) {
    final joined = attempts.join('; ');
    final host = Uri.tryParse(_credentials.baseUrl)?.host ?? _credentials.baseUrl;
    final unreachable = attempts.every((a) => a.contains('Network error'));
    final rejected = attempts.any((a) => a.contains('HTTP 401') || a.contains('HTTP 403'));
    final notFound = attempts.every((a) => a.contains('HTTP 404') || a.contains('HTTP 405'));

    final String lead;
    if (unreachable) {
      lead = 'Could not reach $host at all. Check the tablet has internet, and that the Region matches the data centre '
          'your GWN account lives on.';
    } else if (rejected) {
      lead = '$host answered but rejected the credentials. Check the App ID and Secret Key, and that the Open API is '
          'enabled for this account.';
    } else if (notFound) {
      lead = '$host is reachable but has no token endpoint at any path this build knows. The Open API paths in '
          'GwnEndpoints need to be set from the developer portal.';
    } else {
      lead = 'Could not obtain a GWN Cloud token from $host.';
    }
    return '$lead\n\nTried: $joined';
  }

  /// A transport configured for this account. Probes take one each so a
  /// failure cannot poison the client's own.
  Dio _newDio() {
    final d = Dio(BaseOptions(
      baseUrl: _credentials.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
      // Plain, not json: an unknown endpoint may answer with an HTML error
      // page, and a decode failure inside Dio would hide its status code.
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ));
    if (_probeAdapter != null) d.httpClientAdapter = _probeAdapter;
    d.transformer = _TextTransformer();
    return d;
  }

  // ------------------------------------------------------------ requests

  Future<Map<String, Object?>> _raw(String method, String path, {Map<String, Object?>? body, Map<String, Object?>? query, bool auth = false, Dio? dio}) async {
    _requestCount++;
    Response<Object?> res;
    try {
      res = await (dio ?? _dio).request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: auth && _token != null ? {'Authorization': 'Bearer $_token'} : null,
          // Always take the body as text and decode it here. Letting Dio
          // parse it means a non-JSON error page raises a transport error
          // with no status code, which reads as "the network is down" when
          // the server in fact answered 404.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      // The server answering with a body Dio could not decode (an HTML error
      // page, say) is not a network failure — report its status, so the
      // diagnosis does not blame the tablet's connection for a wrong path.
      final status = e.response?.statusCode;
      if (status != null) {
        throw GwnApiException('HTTP $status', endpoint: path, status: status);
      }
      throw GwnApiException('Network error: ${e.message ?? e.type.name}', endpoint: path);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GwnApiException('Rejected by GWN Cloud', endpoint: path, status: res.statusCode, code: 'AUTH');
    }
    if ((res.statusCode ?? 500) >= 400) {
      throw GwnApiException('HTTP ${res.statusCode}', endpoint: path, status: res.statusCode);
    }
    var data = res.data;
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) {
        throw GwnApiException('Empty response', endpoint: path, status: res.statusCode);
      }
      try {
        data = jsonDecode(text) as Object?;
      } catch (_) {
        throw GwnApiException('HTTP ${res.statusCode} — the response was not JSON', endpoint: path, status: res.statusCode);
      }
    }
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    if (data is List) return {'data': data};
    throw GwnApiException('Unexpected payload of type ${data.runtimeType}', endpoint: path, status: res.statusCode);
  }

  /// Fetches every page of a list endpoint, probing the candidate paths on the
  /// first call and the paging spelling until one actually advances.
  Future<List<Map<String, Object?>>> _list(String key, List<String> candidates, {Map<String, Object?>? query}) async {
    await authenticate();
    final known = lastProbe[key];
    final paths = known == null ? candidates : [known, ...candidates.where((p) => p != known)];
    Object? lastError;
    for (final path in paths) {
      try {
        final rows = await _paged(path, query ?? const {});
        lastProbe[key] = path;
        return rows;
      } on GwnApiException catch (e) {
        if (e.isAuthError) rethrow;
        lastError = e;
      }
    }
    throw GwnApiException(
      'No GWN Cloud path answered for "$key". Confirm it in GwnEndpoints'
      '${lastError == null ? '' : ' (last error: $lastError)'}',
      endpoint: candidates.first,
    );
  }

  Future<List<Map<String, Object?>>> _paged(String path, Map<String, Object?> query) async {
    final spellings = _paging[path] == null ? GwnEndpoints.pagingSpellings : [_paging[path]!];
    for (final sp in spellings) {
      final all = <Map<String, Object?>>[];
      final seen = <String>{};
      var page = sp.page == 'offset' ? 0 : 1;
      int? total;
      for (var guard = 0; guard < 200; guard++) {
        final json = await _raw('GET', path, auth: true, query: {
          ...query,
          sp.page: sp.page == 'offset' ? all.length : page,
          sp.size: GwnEndpoints.pageSize,
        });
        total ??= asInt(pick(json, GwnEndpoints.totalKeys)) ??
            asInt(pick(asMap(pick(json, ['data', 'result'])), GwnEndpoints.totalKeys));
        var rows = firstList(json, GwnEndpoints.listKeys);
        if (rows.isEmpty) {
          final inner = asMap(pick(json, ['data', 'result']));
          if (inner.isNotEmpty) rows = firstList(inner, GwnEndpoints.listKeys);
        }
        if (rows.isEmpty) break;
        // A server that ignores the paging parameters keeps replying with the
        // same rows; detect that rather than looping forever.
        final fingerprint = rows.map((r) => r.values.take(3).join('|')).join(';');
        if (!seen.add(fingerprint)) break;
        all.addAll(rows);
        if (rows.length < GwnEndpoints.pageSize) break;
        if (total != null && all.length >= total) break;
        page++;
      }
      if (all.isNotEmpty) {
        _paging[path] = sp;
        return all;
      }
    }
    return const [];
  }

  // --------------------------------------------------------------- calls

  @override
  Future<List<GwnNetwork>> listNetworks() async {
    final rows = await _list('networks', GwnEndpoints.networkListCandidates);
    return [
      for (final r in rows)
        if ((asString(pick(r, ['id', 'networkId', 'network_id', 'nid'])) ?? '').isNotEmpty) GwnNetwork.fromJson(r),
    ];
  }

  @override
  Future<List<GwnDevice>> listDevices(String networkId) async {
    final rows = await _list('devices', GwnEndpoints.deviceListCandidates, query: {'network_id': networkId, 'networkId': networkId});
    return [
      for (final r in rows)
        if ((asString(pick(r, ['mac', 'macAddress', 'mac_address', 'deviceMac'])) ?? '').isNotEmpty)
          GwnDevice.fromJson(r, networkId: networkId),
    ];
  }

  @override
  Future<List<GwnNetworkDay>> networkDaily(String networkId, String fromDay, String toDay) async {
    final rows = await _list('networkStats', GwnEndpoints.networkStatsCandidates, query: {
      'network_id': networkId,
      'networkId': networkId,
      'start': fromDay,
      'end': toDay,
      'granularity': 'day',
    });
    return [
      for (final r in rows)
        if (_day(r) != null)
          GwnNetworkDay(
            networkId: networkId,
            day: _day(r)!,
            wanUpMinutes: asInt(pick(r, ['upMinutes', 'onlineMinutes', 'uptimeMinutes'])),
            expectedMinutes: asInt(pick(r, ['expectedMinutes', 'totalMinutes'])) ?? 1440,
            rxBytes: asInt(pick(r, ['rxBytes', 'rx', 'downloadBytes', 'download'])),
            txBytes: asInt(pick(r, ['txBytes', 'tx', 'uploadBytes', 'upload'])),
            uniqueClients: asInt(pick(r, ['clients', 'clientCount', 'uniqueClients', 'staCount'])),
            peakClients: asInt(pick(r, ['peakClients', 'maxClients', 'concurrentMax'])),
            apsOnline: asInt(pick(r, ['apsOnline', 'onlineAp', 'apOnline'])),
            apsTotal: asInt(pick(r, ['apsTotal', 'totalAp', 'apTotal'])),
            activeAps: asInt(pick(r, ['activeAps', 'apActive'])),
          ),
    ];
  }

  @override
  Future<List<GwnSsidDay>> ssidDaily(String networkId, String fromDay, String toDay) async {
    final rows = await _list('ssidStats', GwnEndpoints.ssidStatsCandidates, query: {
      'network_id': networkId,
      'networkId': networkId,
      'start': fromDay,
      'end': toDay,
      'granularity': 'day',
    });
    return [
      for (final r in rows)
        if (_day(r) != null && (asString(pick(r, ['ssid', 'ssidName'])) ?? '').isNotEmpty)
          GwnSsidDay(
            networkId: networkId,
            day: _day(r)!,
            ssid: asString(pick(r, ['ssid', 'ssidName']))!,
            bytes: asInt(pick(r, ['bytes', 'totalBytes', 'traffic'])),
            clients: asInt(pick(r, ['clients', 'clientCount'])),
          ),
    ];
  }

  @override
  Future<List<GwnAlarm>> listAlarms({String? networkId, int? sinceTs}) async {
    final rows = await _list('alarms', GwnEndpoints.alarmListCandidates, query: {
      'network_id': ?networkId,
      'networkId': ?networkId,
      'startTime': ?sinceTs,
    });
    return [
      for (final r in rows)
        if ((asString(pick(r, ['id', 'alarmId', 'eventId'])) ?? '').isNotEmpty) GwnAlarm.fromJson(r, networkId: networkId),
    ];
  }

  /// A statistics row's day, however the payload spells it.
  static String? _day(Map<String, Object?> r) {
    final raw = pick(r, ['day', 'date', 'statDate', 'time', 'timestamp']);
    final s = asString(raw);
    if (s != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.substring(0, 10);
    final ts = asEpochSeconds(raw);
    if (ts == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
    return ymd(d);
  }
}
