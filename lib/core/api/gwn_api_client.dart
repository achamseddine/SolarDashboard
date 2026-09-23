import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    // The token sits at the host root, not under the API prefix, and takes
    // its arguments as query parameters on a GET.
    final probe = _newDio();
    try {
      final json = await _raw('GET', GwnEndpoints.token, dio: probe, query: {
        'grant_type': 'client_credentials',
        'client_id': _credentials.appId.trim(),
        'client_secret': _credentials.secretKey.trim(),
      });
      final token = asString(pick(json, ['access_token', 'accessToken', 'token'])) ??
          asString(pick(asMap(pick(json, ['data', 'result'])), ['access_token', 'accessToken', 'token']));
      if (token == null || token.isEmpty) {
        throw GwnApiException(
          '$_host answered the token request but returned no access_token. '
          'Check that the Open API is enabled for this App ID.',
          code: 'AUTH',
        );
      }
      _token = token;
      final ttl = asInt(pick(json, ['expires_in', 'expiresIn', 'expire'])) ??
          asInt(pick(asMap(pick(json, ['data', 'result'])), ['expires_in', 'expiresIn']));
      _tokenExpiresAt = ttl == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 + (ttl * 0.8).round();
      lastProbe['token'] = GwnEndpoints.token;
    } on GwnApiException catch (e) {
      if (e.code == 'AUTH' && e.status == null) rethrow;
      throw GwnApiException(_loginDiagnosis(['${GwnEndpoints.token}: ${e.status == null ? e.message : 'HTTP ${e.status}'}']), code: 'AUTH');
    } finally {
      probe.close(force: true);
    }
  }

  String get _host => Uri.tryParse(_credentials.baseUrl)?.host ?? _credentials.baseUrl;

  /// Signs a call the way the Open API expects: the secret key takes part in
  /// the signature but is never transmitted.
  ///
  ///   params    = access_token=..&appID=..&secretKey=..&timestamp=..
  ///   bodyHash  = sha256(compact json body)
  ///   signature = sha256("&" + params + "&" + bodyHash + "&")
  ///
  /// and the query carries access_token, appID, timestamp and signature.
  Map<String, Object?> _signedQuery(Map<String, Object?> body) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final appId = _credentials.appId.trim();
    final bodyHash = sha256.convert(utf8.encode(jsonEncode(body))).toString();
    final params = 'access_token=$_token&appID=$appId&secretKey=${_credentials.secretKey.trim()}&timestamp=$ts';
    final signature = sha256.convert(utf8.encode('&$params&$bodyHash&')).toString();
    return {'access_token': _token, 'appID': appId, 'timestamp': ts, 'signature': signature};
  }

  /// One signed call. Retries with the other verb when the endpoint answers
  /// 404/405, since the reference examples disagree on GET vs POST.
  Future<Map<String, Object?>> _call(String method, String path, {Map<String, Object?> body = const {}}) async {
    await authenticate();
    try {
      return await _raw(method, path, query: _signedQuery(body), body: body);
    } on GwnApiException catch (e) {
      if (e.status != 404 && e.status != 405) rethrow;
      final other = method == 'GET' ? 'POST' : 'GET';
      return _raw(other, path, query: _signedQuery(body), body: body);
    }
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

  /// Every page of a signed list endpoint. Paging parameters travel in the
  /// body, so they take part in the signature.
  Future<List<Map<String, Object?>>> _pagedCall(
    String key,
    List<({String path, String method})> candidates, {
    Map<String, Object?> body = const {},
  }) async {
    final known = lastProbe[key];
    final ordered = known == null
        ? candidates
        : [...candidates.where((c) => c.path == known), ...candidates.where((c) => c.path != known)];
    final attempts = <String>[];
    for (final ep in ordered) {
      try {
        final rows = await _pages(ep, body);
        lastProbe[key] = ep.path;
        return rows;
      } on GwnApiException catch (e) {
        if (e.isAuthError) rethrow;
        attempts.add('${ep.path}: ${e.status == null ? e.message : 'HTTP ${e.status}'}');
      }
    }
    throw GwnApiException(
      'No GWN Cloud endpoint answered for "$key" on $_host. Tried: ${attempts.join('; ')}',
      endpoint: candidates.first.path,
    );
  }

  Future<List<Map<String, Object?>>> _pages(({String path, String method}) ep, Map<String, Object?> body) async {
    final spellings = _paging[ep.path] == null ? GwnEndpoints.pagingSpellings : [_paging[ep.path]!];
    for (final sp in spellings) {
      final all = <Map<String, Object?>>[];
      final seen = <String>{};
      var page = sp.page == 'offset' ? 0 : 1;
      int? total;
      for (var guard = 0; guard < 200; guard++) {
        final json = await _call(ep.method, ep.path, body: {
          ...body,
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
        // A server ignoring the paging parameters repeats the same rows.
        final fingerprint = rows.map((r) => r.values.take(3).join('|')).join(';');
        if (!seen.add(fingerprint)) break;
        all.addAll(rows);
        if (rows.length < GwnEndpoints.pageSize) break;
        if (total != null && all.length >= total) break;
        page++;
      }
      if (all.isNotEmpty) {
        _paging[ep.path] = sp;
        return all;
      }
    }
    return const [];
  }

  // --------------------------------------------------------------- calls

  @override
  Future<List<GwnNetwork>> listNetworks() async {
    final rows = await _pagedCall('networks', [GwnEndpoints.networkList]);
    return [
      for (final r in rows)
        if ((asString(pick(r, ['id', 'networkId', 'network_id', 'nid'])) ?? '').isNotEmpty) GwnNetwork.fromJson(r),
    ];
  }

  @override
  Future<List<GwnDevice>> listDevices(String networkId) async {
    final body = {'network_id': networkId, 'networkId': networkId};
    final out = <GwnDevice>[];
    // Access points come from their own endpoint; switches and the gateway
    // from whichever device list the account exposes.
    for (final entry in [
      ('aps', [GwnEndpoints.apList]),
      ('devices', GwnEndpoints.switchListCandidates),
    ]) {
      try {
        final rows = await _pagedCall(entry.$1, entry.$2, body: body);
        for (final r in rows) {
          if ((asString(pick(r, ['mac', 'macAddress', 'mac_address', 'deviceMac'])) ?? '').isEmpty) continue;
          final d = GwnDevice.fromJson(r, networkId: networkId);
          if (out.any((x) => x.mac == d.mac)) continue;
          out.add(d);
        }
      } on GwnApiException catch (e) {
        if (e.isAuthError) rethrow;
        // One of the two lists missing is not fatal: the other still counts.
      }
    }
    return out;
  }

  @override
  Future<List<GwnNetworkDay>> networkDaily(String networkId, String fromDay, String toDay) async {
    final rows = await _pagedCall('networkStats', GwnEndpoints.clientStatsCandidates, body: {
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
    final rows = await _pagedCall('ssidStats', GwnEndpoints.ssidStatsCandidates, body: {
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
    final rows = await _pagedCall('alarms', GwnEndpoints.alarmCandidates, body: {
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
