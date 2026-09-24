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
  GwnApiClient({required GwnCredentials credentials, Dio? dio, this.lastSuccess, this.onAuthenticated})
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
    final id = GwnCredentials.clean(_credentials.appId);
    final secret = GwnCredentials.clean(_credentials.secretKey);
    final basic = base64Encode(utf8.encode('$id:$secret'));

    // A query string is written to every access log between here and the
    // origin, so the strategy that puts the Secret Key in the URL is tried
    // LAST — only if the deployment accepts nothing else. The rest of this
    // client never transmits the key at all: it is hashed into a signature.
    //
    // The remaining two are the standard client_credentials spellings; a
    // deployment may accept one and not another.
    final strategies = <({String label, String method, Map<String, Object?>? query, Object? body, Map<String, String>? headers})>[
      // Each value is percent-encoded: a key carrying a '+', '&' or '=' would
      // otherwise be a different key by the time the server parsed the body.
      (
        label: 'POST form',
        method: 'POST',
        query: null,
        body: 'grant_type=client_credentials'
            '&client_id=${Uri.encodeQueryComponent(id)}'
            '&client_secret=${Uri.encodeQueryComponent(secret)}',
        headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
      ),
      (label: 'POST basic auth', method: 'POST', query: null, body: 'grant_type=client_credentials', headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Authorization': 'Basic $basic'}),
      // Last: the only strategy that puts the key in a URL.
      (label: 'GET query', method: 'GET', query: {'grant_type': 'client_credentials', 'client_id': id, 'client_secret': secret}, body: null, headers: null),
    ];

    final attempts = <String>[];
    for (final st in strategies) {
      final probe = _newDio();
      try {
        final json = await _raw(st.method, GwnEndpoints.token, dio: probe, query: st.query, body: st.body, headers: st.headers);
        final token = asString(pick(json, ['access_token', 'accessToken', 'token'])) ??
            asString(pick(asMap(pick(json, ['data', 'result'])), ['access_token', 'accessToken', 'token']));
        if (token == null || token.isEmpty) {
          attempts.add('${GwnEndpoints.token} (${st.label}): answered, but carried no access_token');
          continue;
        }
        _token = token;
        final ttl = asInt(pick(json, ['expires_in', 'expiresIn', 'expire'])) ??
            asInt(pick(asMap(pick(json, ['data', 'result'])), ['expires_in', 'expiresIn']));
        _tokenExpiresAt = ttl == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 + (ttl * 0.8).round();
        lastProbe['token'] = '${GwnEndpoints.token} (${st.label})';
        onAuthenticated?.call(GwnLastAuth(
          appId: id,
          host: _host,
          keyLength: secret.length,
          fingerprint: gwnKeyFingerprint(secret),
          ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          strategy: st.label,
        ));
        return;
      } on GwnApiException catch (e) {
        attempts.add('${GwnEndpoints.token} (${st.label}): ${e.message}');
      } catch (e) {
        attempts.add('${GwnEndpoints.token} (${st.label}): $e');
      } finally {
        probe.close(force: true);
      }
    }
    throw GwnApiException(gwnLoginDiagnosis(_credentials, attempts, lastSuccess: lastSuccess), code: 'AUTH');
  }

  String get _host => Uri.tryParse(_credentials.baseUrl)?.host ?? _credentials.baseUrl;

  /// What the last successful login on this device used, when it is known.
  /// A rejection reads very differently against it: the same key failing now
  /// means it was changed at the portal, a different one means what is
  /// stored here changed.
  final GwnLastAuth? lastSuccess;

  /// Called when a login succeeds, so the facts above can be kept.
  final void Function(GwnLastAuth auth)? onAuthenticated;

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
    final appId = GwnCredentials.clean(_credentials.appId);
    final bodyHash = sha256.convert(utf8.encode(jsonEncode(body))).toString();
    final params = 'access_token=$_token&appID=$appId&secretKey=${GwnCredentials.clean(_credentials.secretKey)}&timestamp=$ts';
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

  Future<Map<String, Object?>> _raw(String method, String path, {Object? body, Map<String, Object?>? query, bool auth = false, Dio? dio, Map<String, String>? headers}) async {
    _requestCount++;
    Response<Object?> res;
    try {
      res = await (dio ?? _dio).request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            ...?headers,
            if (auth && _token != null) 'Authorization': 'Bearer $_token',
          },
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
    // The server's own words are the most useful thing it returns on a
    // rejection, so carry them rather than a generic "rejected".
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GwnApiException('HTTP ${res.statusCode}${_detail(res.data)}', endpoint: path, status: res.statusCode, code: 'AUTH');
    }
    if ((res.statusCode ?? 500) >= 400) {
      throw GwnApiException('HTTP ${res.statusCode}${_detail(res.data)}', endpoint: path, status: res.statusCode);
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
        _noteFields(key, rows);
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
    final sp = GwnEndpoints.paging;
    final all = <Map<String, Object?>>[];
    final seen = <String>{};
    var page = 1;
    int? total;
    for (var guard = 0; guard < 200; guard++) {
      final json = await _call(ep.method, ep.path, body: {...body, sp.page: page, sp.size: GwnEndpoints.pageSize});
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
    return all;
  }

  /// Field names the first row of each endpoint carried. Names only, never
  /// values — enough to confirm the mapping without moving any data.
  final Map<String, List<String>> fieldsSeen = {};

  void _noteFields(String key, List<Map<String, Object?>> rows) {
    if (rows.isEmpty || fieldsSeen.containsKey(key)) return;
    fieldsSeen[key] = rows.first.keys.toList()..sort();
  }

  // --------------------------------------------------------------- calls

  @override
  Future<List<GwnNetwork>> listNetworks() async {
    final rows = await _pagedCall('networks', [GwnEndpoints.networkList], body: {...GwnEndpoints.listBody(), 'type': ''});
    return [
      for (final r in rows)
        if ((asString(pick(r, ['id', 'networkId', 'network_id', 'nid'])) ?? '').isNotEmpty) GwnNetwork.fromJson(r),
    ];
  }

  @override
  Future<List<GwnDevice>> listDevices(String networkId) async {
    final body = GwnEndpoints.listBody(networkId: networkId);
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
          var d = GwnDevice.fromJson(r, networkId: networkId);
          // Rows from ap/list are access points whatever their type field
          // says; without this a payload with no type reads as "other" and
          // disappears from AP availability.
          if (entry.$1 == 'aps' && d.kind == GwnDeviceKind.other) {
            d = d.asKind(GwnDeviceKind.accessPoint);
          }
          if (d.mac.isEmpty) {
            // A device whose address sits under a key this build does not
            // know still counts; any stable identifier will key the row.
            final id = asString(pick(r, ['id', 'deviceId', 'sn', 'serialNumber', 'serial', 'uuid']));
            if (id == null || id.isEmpty) continue;
            d = GwnDevice(
              networkId: d.networkId,
              mac: id.toUpperCase(),
              name: d.name,
              kind: d.kind,
              status: d.status,
              model: d.model,
              firmware: d.firmware,
              ip: d.ip,
              uptimeSeconds: d.uptimeSeconds,
              clientCount: d.clientCount,
              cpuPercent: d.cpuPercent,
              memoryPercent: d.memoryPercent,
              poePortsTotal: d.poePortsTotal,
              poePortsActive: d.poePortsActive,
              poePortsFailed: d.poePortsFailed,
              portsUp: d.portsUp,
              portsDown: d.portsDown,
              portsError: d.portsError,
              lastSeenTs: d.lastSeenTs,
            );
          }
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

  /// This API version has no statistics family, so there is no history to
  /// fetch: the best it can give is the network as it stands right now.
  /// One row is returned, for today, and [NetworkSync] merges it into the
  /// day's accruing counters. The series the framework needs therefore grows
  /// from the app's own observations, one sync at a time.
  @override
  Future<List<GwnNetworkDay>> networkDaily(String networkId, String fromDay, String toDay) async {
    final detail = await _networkDetail(networkId);
    if (detail.isEmpty) return const [];
    _noteFields('networkDetail', [detail]);

    // Named keys first; then a match on what the key means, because this
    // payload has no published field list and a guessed name is why these
    // counters read zero.
    final clients = asInt(pick(detail, ['clientCount', 'clientNum', 'clients', 'staCount', 'onlineClient', 'userCount'])) ??
        findInt(detail, ['client', 'sta', 'user', 'terminal'], not: ['ssid', 'max', 'limit', 'total_ap']);
    final apsOnline = asInt(pick(detail, ['onlineAp', 'apOnline', 'apsOnline', 'onlineDevice', 'onlineNum'])) ??
        findInt(detail, ['online'], not: ['client', 'user', 'offline']);
    final apsTotal = asInt(pick(detail, ['apTotal', 'totalAp', 'apsTotal', 'deviceCount', 'totalNum'])) ??
        findInt(detail, ['aptotal', 'totalap', 'devicecount', 'devicenum'], not: ['online', 'offline']);
    final rx = asInt(pick(detail, ['rxBytes', 'downloadBytes', 'download', 'rx', 'downTraffic'])) ??
        findInt(detail, ['download', 'rxbyte', 'downtraffic']);
    final tx = asInt(pick(detail, ['txBytes', 'uploadBytes', 'upload', 'tx', 'upTraffic'])) ??
        findInt(detail, ['upload', 'txbyte', 'uptraffic']);
    final usage = asInt(pick(detail, ['usage', 'traffic', 'totalTraffic', 'flow'])) ??
        findInt(detail, ['traffic', 'usage', 'flow', 'byte'], not: ['download', 'upload', 'rx', 'tx']);

    return [
      GwnNetworkDay(
        networkId: networkId,
        day: toDay,
        rxBytes: rx ?? (usage == null ? null : (usage * 0.8).round()),
        txBytes: tx ?? (usage == null ? null : (usage * 0.2).round()),
        uniqueClients: clients,
        peakClients: clients,
        apsOnline: apsOnline,
        apsTotal: apsTotal,
        activeAps: clients == null || clients == 0 ? 0 : apsOnline,
      ),
    ];
  }

  Future<Map<String, Object?>> _networkDetail(String networkId) async {
    await authenticate();
    try {
      final json = await _call(GwnEndpoints.networkDetail.method, GwnEndpoints.networkDetail.path, body: {'id': networkId});
      final inner = asMap(pick(json, ['data', 'result']));
      return inner.isNotEmpty ? inner : json;
    } on GwnApiException catch (e) {
      if (e.isAuthError) rethrow;
      return const {};
    }
  }

  /// Per-SSID traffic is not exposed by this API version. The SSID list is
  /// fetched so the names are known, but it carries no traffic, and the
  /// dashboards say so rather than showing an empty chart.
  @override
  Future<List<GwnSsidDay>> ssidDaily(String networkId, String fromDay, String toDay) async {
    final rows = await _pagedCall('ssids', [GwnEndpoints.ssidList], body: GwnEndpoints.listBody(networkId: networkId));
    return [
      for (final r in rows)
        if ((asString(pick(r, ['ssid', 'ssidName', 'name'])) ?? '').isNotEmpty)
          GwnSsidDay(
            networkId: networkId,
            day: toDay,
            ssid: asString(pick(r, ['ssid', 'ssidName', 'name']))!,
            bytes: asInt(pick(r, ['bytes', 'totalBytes', 'traffic', 'usage'])),
            clients: asInt(pick(r, ['clients', 'clientCount', 'clientNum'])),
          ),
    ];
  }

  @override
  Future<List<GwnAlarm>> listAlarms({String? networkId, int? sinceTs}) async {
    final rows = await _pagedCall('alarms', GwnEndpoints.alarmCandidates, body: {
      ...GwnEndpoints.listBody(networkId: networkId),
      'startTime': ?sinceTs,
    });
    return [
      for (final r in rows)
        if ((asString(pick(r, ['id', 'alarmId', 'eventId'])) ?? '').isNotEmpty) GwnAlarm.fromJson(r, networkId: networkId),
    ];
  }

  /// Whatever the server said about a failure, trimmed to one readable line.
  ///
  /// An error page from the servlet container starts with a stylesheet, so
  /// truncating it raw hands the operator a screenful of CSS and cuts off the
  /// one line that says what went wrong. Its title and headings carry that
  /// line, and they come first.
  static String _detail(Object? data) {
    final text = data is String ? data : (data == null ? '' : jsonEncode(data));
    var trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('<')) {
      final said = [
        for (final m in RegExp(r'<(?:title|h1|h2|h3|b|p)[^>]*>(.*?)</(?:title|h1|h2|h3|b|p)>', caseSensitive: false).allMatches(trimmed))
          m.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      ].where((t) => t.isNotEmpty).toList();
      if (said.isNotEmpty) trimmed = said.take(4).join(' · ');
    }
    return ' — ${trimmed.length > 240 ? '${trimmed.substring(0, 240)}…' : trimmed}';
  }

}

/// Turns a failed login into something an operator can act on, without ever
/// putting the Secret Key in a message that gets photographed and sent on.
///
/// Top-level and pure so the wording can be tested against each failure
/// shape rather than only against whatever the network happens to do.
/// Six hex characters of the key's SHA-256. Enough to tell two entries
/// apart, nowhere near enough to recover a 32-character random key, and it
/// keeps the secret out of a message that gets photographed and sent on.
String gwnKeyFingerprint(String key) =>
    key.isEmpty ? '–' : sha256.convert(utf8.encode(key)).toString().substring(0, 6);

/// "3 days ago", for a diagnosis that has to be read on a tablet.
String _ago(int ts) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
  if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}

/// Turns the probe log into something an operator can act on: whether the
/// host was reachable at all, whether it rejected the credentials, or
/// whether it simply has no endpoint at these paths.
String gwnLoginDiagnosis(GwnCredentials credentials, List<String> attempts, {GwnLastAuth? lastSuccess}) {
  final joined = attempts.join('; ');
  final host = Uri.tryParse(credentials.baseUrl)?.host ?? credentials.baseUrl;
  final unreachable = attempts.every((a) => a.contains('Network error'));
  final rejected = attempts.any((a) => a.contains('HTTP 401') || a.contains('HTTP 403'));
  final notFound = attempts.every((a) => a.contains('HTTP 404') || a.contains('HTTP 405'));

  final String lead;
  if (unreachable) {
    lead = 'Could not reach $host at all. Check the tablet has internet, and that the Region matches the data centre '
        'your GWN account lives on.';
  } else if (rejected) {
    final key = GwnCredentials.clean(credentials.secretKey);
    final appId = GwnCredentials.clean(credentials.appId);
    final tooShort = key.length < GwnCredentials.usualKeyLength;
    final tooLong = key.length > GwnCredentials.usualKeyLength;
    // A fingerprint of a short key could be walked back; below this length
    // the length alone is the finding anyway.
    final fp = key.length >= 16 ? gwnKeyFingerprint(key) : 'not shown for a key this short';
    final sameKey = lastSuccess != null && lastSuccess.fingerprint == fp;
    final sameHost = lastSuccess != null && lastSuccess.host == host;
    // "invalid_client" is the server saying it could not authenticate the
    // client at all, which a disabled grant type would not do — that fails
    // later, after the client has been accepted.
    final invalidClient = attempts.any((a) => a.contains('invalid_client'));

    lead = [
      '$host answered and rejected these credentials.',
      '',
      // Facts about the key, never the key: its length catches a half-typed
      // one, and the fingerprint is a one-way hash, so two entries can be
      // compared without either being shown.
      'App ID $appId · Secret Key ${key.length} characters'
          '${tooShort || tooLong ? ' (GWN issues ${GwnCredentials.usualKeyLength})' : ''} · fingerprint $fp · $host',
      if (lastSuccess == null)
        'This tablet has not authenticated with GWN Cloud since the app was installed, so there is nothing to compare '
            'against. Reinstalling clears that history along with the credentials.'
      else
        'Last worked ${_ago(lastSuccess.ts)}: App ID ${lastSuccess.appId} · ${lastSuccess.keyLength} characters · '
            'fingerprint ${lastSuccess.fingerprint} · ${lastSuccess.host}',
      '',
      if (tooShort)
        'The key stored here is ${key.length} characters and GWN issues ${GwnCredentials.usualKeyLength}, so part of '
            'it is missing. Copy the key from GWN Cloud and use Paste — the field is narrower than the key, so a short '
            'one looks complete.'
      else if (tooLong)
        'The key stored here is ${key.length} characters and GWN issues ${GwnCredentials.usualKeyLength}, so something '
            'extra came along with it. Clear the field and paste the key again.'
      else if (sameKey)
        'This is the same key that last worked, so it was changed at the portal. Issue or copy the current Secret Key '
            'in GWN Cloud and paste it here — rotating a key kills the old one the moment the new one appears.'
      else if (lastSuccess != null)
        'This is not the key that last worked here. Either it was re-issued at the portal, or what was entered is not '
            'the current key — copy it from GWN Cloud and paste it rather than typing it.'
      else
        'Most likely the Secret Key was re-issued: rotating a key in GWN Cloud kills the old one the moment the new '
            'one appears. Copy the current key from the portal and paste it here rather than typing it.',
      if (lastSuccess != null && !sameHost)
        'The Region has also changed since then — it last worked on ${lastSuccess.host}.'
      else if (lastSuccess == null)
        'If the key is current, check the Region: a GWN account belongs to one data centre, and this App ID may have '
            'been issued on ${GwnEndpoints.hosts.entries.where((e) => !e.value.contains(host)).map((e) => e.key).join(' or ')}.',
      if (!invalidClient)
        'If it keeps failing, check that the Open API is enabled for this account and that this App ID may use the '
            'client-credentials grant.',
    ].join('\n');
  } else if (notFound) {
    lead = '$host is reachable but has no token endpoint at any path this build knows. The Open API paths in '
        'GwnEndpoints need to be set from the developer portal.';
  } else {
    lead = 'Could not obtain a GWN Cloud token from $host.';
  }
  return '$lead\n\nTried: $joined';
}
