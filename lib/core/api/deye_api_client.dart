import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/alert.dart';
import '../models/credentials.dart';
import '../models/device.dart';
import '../models/station.dart';
import '../sync/rate_limiter.dart';
import '../utils/app_time.dart';
import 'deye_api.dart';
import 'deye_api_exception.dart';
import 'deye_endpoints.dart';
import 'json_utils.dart';

/// Persists the access token between launches (secure storage in the app,
/// memory in tests).
abstract class TokenCache {
  Future<String?> read();
  Future<void> write(String token, {int? expiresAtEpoch});
  Future<void> clear();
}

class MemoryTokenCache implements TokenCache {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token, {int? expiresAtEpoch}) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

/// What a paged list call actually brought back.
///
/// [total] is the row count the cloud claimed; [received] is what the client
/// managed to collect. They differ when the backend caps a list, refuses to
/// advance past the first page under every paging spelling, or simply stops
/// answering — cases the UI must warn about rather than silently show a
/// shorter fleet.
class ListFetchReport {
  const ListFetchReport({
    required this.path,
    required this.received,
    required this.spelling,
    this.total,
  });

  final String path;
  final int received;

  /// Row count reported by the server, when it reported one.
  final int? total;

  /// Paging parameter naming that produced [received] (for logs/diagnostics).
  final String spelling;

  bool get truncated => total != null && received < total!;

  /// Human-readable shortfall, e.g. `DeyeCloud reported 219 plants, 20 were
  /// fetched`. Null when nothing was lost.
  String? message(String noun) => truncated ? 'DeyeCloud reported $total $noun, $received were fetched' : null;

  @override
  String toString() => '$path: received $received of ${total ?? received} items (paging: $spelling)';
}

/// One listing attempt with a single paging spelling.
class _ListAttempt {
  _ListAttempt({required this.items, required this.total, required this.spelling, required this.stalled});

  final List<Map<String, Object?>> items;
  final int? total;
  final PagingSpelling spelling;

  /// True when a page repeated rows the client already had while the server
  /// still claimed more existed.
  final bool stalled;

  /// Nothing is missing: either the server never gave a total, or we got it all.
  bool get isComplete => total == null || items.length >= total!;
}

/// Optional overrides for the alert endpoints (Settings → Advanced).
class AlertEndpointConfig {
  const AlertEndpointConfig({this.stationPath, this.devicePath});
  final String? stationPath;
  final String? devicePath;
}

/// HTTP client for the DeyeCloud Open API v1.
class DeyeApiClient implements DeyeApi {
  DeyeApiClient({
    required DeyeCredentials credentials,
    Dio? dio,
    TokenCache? tokenCache,
    RateLimiter? limiter,
    this.maxRetries = 3,
    this.log,
    DateTime Function()? clock,
    AlertEndpointConfig alertConfig = const AlertEndpointConfig(),
  })  : _credentials = credentials,
        _tokenCache = tokenCache ?? MemoryTokenCache(),
        _limiter = limiter ?? RateLimiter(),
        _clock = clock ?? DateTime.now,
        _stationAlertPath = alertConfig.stationPath,
        _deviceAlertPath = alertConfig.devicePath,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: credentials.baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 40),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              responseType: ResponseType.json,
              validateStatus: (_) => true,
            ));

  final Dio _dio;
  final TokenCache _tokenCache;
  final RateLimiter _limiter;
  final DateTime Function() _clock;
  final int maxRetries;
  final void Function(String message)? log;

  DeyeCredentials _credentials;
  String? _token;
  int? _tokenExpiresAt;
  Future<void>? _authInFlight;
  int _requestCount = 0;
  int _consecutiveAuthFailures = 0;
  String? _stationAlertPath;
  String? _deviceAlertPath;
  bool _alertsUnsupported = false;
  String? _alertsUnsupportedReason;
  DateTime? _backoffUntil;

  /// Paging spelling that was proven to work, per list path (index into
  /// [DeyeEndpoints.pagingSpellings]). Probing happens once per client.
  final Map<String, int> _pagingSpelling = {};

  /// Result of the most recent paged call, per list path.
  final Map<String, ListFetchReport> _listReports = {};

  /// Token lifetime assumed when the server does not say (24 h).
  static const Duration defaultTokenLifetime = Duration(hours: 24);

  DeyeCredentials get credentials => _credentials;
  set credentials(DeyeCredentials c) {
    _credentials = c;
    _dio.options.baseUrl = c.baseUrl;
    _token = null;
    _tokenExpiresAt = null;
    _consecutiveAuthFailures = 0;
  }

  @override
  int get requestCount => _requestCount;

  @override
  bool get alertsUnsupported => _alertsUnsupported;

  @override
  String? get alertsUnsupportedReason => _alertsUnsupportedReason;

  /// Resolved alert endpoint paths (for diagnostics in Settings).
  String? get stationAlertPath => _stationAlertPath;
  String? get deviceAlertPath => _deviceAlertPath;

  /// When non-null the client is pausing all requests until this time.
  DateTime? get backoffUntil => _backoffUntil;

  /// Diagnostics of the last paged call on [path] (null before the first one).
  ListFetchReport? listReport(String path) => _listReports[path];

  /// Diagnostics of the last [listStations] sweep: how many plants the cloud
  /// said it had versus how many were actually fetched.
  ListFetchReport? get lastStationListReport => _listReports[DeyeEndpoints.stationList];

  /// Plant count reported by the cloud during the last [listStations], or null
  /// when the server did not say.
  int? get lastListTotal => lastStationListReport?.total;

  /// Paging spelling proven to work for [path], once one has been found.
  String? resolvedPagingSpelling(String path) {
    final i = _pagingSpelling[path];
    return i == null ? null : DeyeEndpoints.pagingSpellings[i].label;
  }

  /// Lets the alert probe run again (e.g. after the user edited the paths).
  void resetAlertProbe({String? stationPath, String? devicePath}) {
    _alertsUnsupported = false;
    _alertsUnsupportedReason = null;
    _stationAlertPath = stationPath;
    _deviceAlertPath = devicePath;
  }

  // ---------------------------------------------------------------- auth

  @override
  Future<void> authenticate() async {
    final now = _nowEpoch();
    if (_token != null && (_tokenExpiresAt == null || now < _tokenExpiresAt! - 60)) return;
    if (_token == null) {
      _token = await _tokenCache.read();
      if (_token != null) return;
    }
    await _login();
  }

  Future<void> _login() {
    // Collapse concurrent re-login attempts into one request.
    return _authInFlight ??= _doLogin().whenComplete(() => _authInFlight = null);
  }

  Future<void> _doLogin() async {
    if (!_credentials.isComplete) {
      throw DeyeApiException('DeyeCloud credentials are incomplete', endpoint: DeyeEndpoints.token);
    }
    if (_consecutiveAuthFailures >= 2) {
      throw DeyeApiException('Credentials rejected twice in a row – check App ID/secret, e-mail, password and company id',
          endpoint: DeyeEndpoints.token, code: 'AUTH_LOCKED');
    }
    final Map<String, Object?> json;
    try {
      json = await _rawPost(
        '${DeyeEndpoints.token}?appId=${Uri.encodeQueryComponent(_credentials.appId.trim())}',
        _credentials.toTokenBody(),
        auth: false,
      );
    } on DeyeApiException catch (e) {
      if (!e.isNetworkError && !e.isServerError) _consecutiveAuthFailures++;
      rethrow;
    }
    final token = asString(pick(json, ['accessToken', 'access_token', 'token']));
    if (token == null) {
      _consecutiveAuthFailures++;
      throw DeyeApiException('Login succeeded but no accessToken in response', endpoint: DeyeEndpoints.token, code: asString(json['code']));
    }
    _consecutiveAuthFailures = 0;
    _token = token;
    final expiresIn = asInt(pick(json, ['expiresIn', 'expires_in']));
    // Refresh proactively at 80 % of the lifetime.
    final lifetime = expiresIn != null && expiresIn > 0 ? expiresIn : defaultTokenLifetime.inSeconds;
    _tokenExpiresAt = _nowEpoch() + (lifetime * 0.8).round();
    await _tokenCache.write(token, expiresAtEpoch: _tokenExpiresAt);
    log?.call('DeyeCloud login OK (companyId=${_credentials.companyId ?? '-'}, lifetime=${lifetime}s)');
  }

  /// Forgets the cached token so the next call logs in again.
  Future<void> invalidateToken() async {
    _token = null;
    _tokenExpiresAt = null;
    await _tokenCache.clear();
  }

  // ------------------------------------------------------------- transport

  /// Sends a POST, unwraps the DeyeCloud envelope, retries on transient
  /// failures and re-authenticates once on token errors.
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body) async {
    await _waitForBackoff();
    await authenticate();
    var reauthed = false;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final json = await _rawPost(path, body, auth: true);
        _backoffUntil = null;
        return json;
      } on DeyeApiException catch (e) {
        if (e.isAuthError && !reauthed) {
          reauthed = true;
          log?.call('Token rejected on $path – re-authenticating');
          await invalidateToken();
          await _login();
          continue;
        }
        final transient = e.isRateLimited || e.isServerError || e.isNetworkError;
        if (transient && attempt <= maxRetries) {
          final backoff = Duration(milliseconds: (500 * math.pow(2, attempt - 1)).round() + math.Random().nextInt(250));
          if (e.isRateLimited) {
            _backoffUntil = _clock().add(Duration(seconds: math.min(300, 15 * attempt * attempt)));
          }
          log?.call('Transient failure on $path (${e.message}); retry $attempt in ${backoff.inMilliseconds} ms');
          await Future<void>.delayed(backoff);
          await _waitForBackoff();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _waitForBackoff() async {
    final until = _backoffUntil;
    if (until == null) return;
    final wait = until.difference(_clock());
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  Future<Map<String, Object?>> _rawPost(String path, Map<String, Object?> body, {required bool auth}) {
    return _limiter.run(() async {
      _requestCount++;
      Response<Object?> res;
      try {
        res = await _dio.post<Object?>(
          path,
          data: body,
          options: Options(headers: auth && _token != null ? {'Authorization': 'bearer $_token'} : null),
        );
      } on DioException catch (e) {
        throw DeyeApiException(e.message ?? e.type.name, endpoint: path, cause: e);
      }
      final status = res.statusCode ?? 0;
      final data = res.data;
      final json = data is Map ? asMap(data) : <String, Object?>{};
      final code = asString(json['code']);
      final success = asBool(json['success']);
      final msg = asString(json['msg']) ?? asString(json['message']);
      if (status < 200 || status >= 300) {
        throw DeyeApiException(msg ?? 'HTTP $status', code: code, httpStatus: status, endpoint: path);
      }
      if (data is! Map) {
        throw DeyeApiException('Empty or non-JSON response', httpStatus: status, endpoint: path);
      }
      final ok = success == true || code == '1000000' || (success == null && code == null);
      if (!ok) {
        throw DeyeApiException(msg ?? 'DeyeCloud error ${code ?? ''}', code: code, httpStatus: status, endpoint: path);
      }
      return json;
    });
  }

  /// Generic pagination that refuses to truncate silently.
  ///
  /// DeyeCloud installations disagree on how a page is requested, and a server
  /// that does not recognise our parameters simply keeps answering with the
  /// first page. The old "stop when a page adds no new ids" rule turned that
  /// into a fleet of 20 plants out of 219. So: when a page adds nothing while
  /// the reported `total` is still larger, the listing is restarted with the
  /// next spelling in [DeyeEndpoints.pagingSpellings]; the first spelling that
  /// reaches `total` is cached per path for the rest of the client's life.
  /// Whatever happens, the outcome is recorded in [listReport] so the UI can
  /// say that plants are missing.
  Future<List<Map<String, Object?>>> _paginate(
    String path,
    Map<String, Object?> body,
    List<String> listKeys, {
    required String Function(Map<String, Object?>) idOf,
    int size = DeyeEndpoints.pageSize,
    int maxPages = 200,
  }) async {
    final spellings = DeyeEndpoints.pagingSpellings;
    final cached = _pagingSpelling[path];
    final order = <int>[
      ?cached,
      for (var i = 0; i < spellings.length; i++)
        if (i != cached) i,
    ];
    _ListAttempt? best;
    for (final index in order) {
      final attempt = await _listPages(path, body, listKeys, idOf: idOf, size: size, maxPages: maxPages, spelling: spellings[index]);
      if (best == null || attempt.items.length > best.items.length) best = attempt;
      if (attempt.isComplete) {
        best = attempt;
        if (_pagingSpelling[path] != index) {
          _pagingSpelling[path] = index;
          log?.call('$path: paging advances with ${spellings[index].label}');
        }
        break;
      }
      if (attempt.stalled) {
        log?.call('$path: paging stalled at ${attempt.items.length}/${attempt.total} with ${spellings[index].label}');
      }
    }
    final result = best!;
    final report = ListFetchReport(path: path, received: result.items.length, total: result.total, spelling: result.spelling.label);
    _listReports[path] = report;
    log?.call(report.toString());
    return result.items;
  }

  /// Walks every page of [path] with one [spelling].
  Future<_ListAttempt> _listPages(
    String path,
    Map<String, Object?> body,
    List<String> listKeys, {
    required String Function(Map<String, Object?>) idOf,
    required int size,
    required int maxPages,
    required PagingSpelling spelling,
  }) async {
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    int? total;
    var pageSize = size;
    var stalled = false;
    for (var page = 1; page <= maxPages; page++) {
      final json = await post(path, {...body, ...spelling.params(page, pageSize)});
      final items = firstList(json, listKeys);
      total ??= asInt(pick(json, ['total', 'totalCount', 'count']));
      final reported = total;
      if (page == 1 && items.isNotEmpty && items.length < pageSize && reported != null && reported > items.length) {
        // The server enforces a smaller page than we asked for; keep paging
        // with the size it actually gave instead of calling it a short page.
        log?.call('$path: server capped the page at ${items.length} rows (asked $pageSize)');
        pageSize = items.length;
      }
      var added = 0;
      for (final it in items) {
        if (seen.add(idOf(it))) {
          out.add(it);
          added++;
        }
      }
      if (items.isEmpty || added == 0) {
        // No progress. Only a server that still claims more rows is "stalled";
        // otherwise this is simply the end of the list.
        stalled = items.isNotEmpty && reported != null && out.length < reported;
        break;
      }
      if (reported != null && out.length >= reported) break;
      if (reported == null && items.length < pageSize) break;
    }
    return _ListAttempt(items: out, total: total, spelling: spelling, stalled: stalled);
  }

  // --------------------------------------------------------------- account

  @override
  Future<Map<String, Object?>> accountInfo() => post(DeyeEndpoints.accountInfo, const {});

  // -------------------------------------------------------------- stations

  @override
  Future<List<Station>> listStations() async {
    final items = await _paginate(
      DeyeEndpoints.stationList,
      const {},
      const ['stationList', 'stations', 'list', 'records'],
      idOf: (j) => asString(pick(j, ['id', 'stationId', 'plantId'])) ?? j.hashCode.toString(),
    );
    final out = <Station>[];
    for (final item in items) {
      try {
        out.add(Station.fromApi(item));
      } catch (e) {
        log?.call('Skipping unparsable station: $e');
      }
    }
    return out;
  }

  @override
  Future<List<Device>> listStationDevices(List<int> stationIds) async {
    final out = <Device>[];
    final seen = <String>{};
    for (final chunk in _chunks(stationIds, DeyeEndpoints.stationDeviceIdBatch)) {
      final items = await _paginate(
        DeyeEndpoints.stationDevice,
        {'stationIds': chunk},
        const ['deviceListItems', 'deviceList', 'devices', 'list'],
        idOf: (j) => asString(pick(j, ['deviceSn', 'sn', 'serialNo'])) ?? j.hashCode.toString(),
        size: 100,
      );
      for (final item in items) {
        final d = Device.fromApi(item, stationId: chunk.length == 1 ? chunk.first : null);
        if (d != null && seen.add(d.deviceSn)) out.add(d);
      }
    }
    return out;
  }

  @override
  Future<StationLatestResult> stationLatest(int stationId, {tz.Location? location}) async {
    final json = await post(DeyeEndpoints.stationLatest, {'stationId': stationId});
    return StationLatestResult(snapshot: StationSnapshot.fromApi(json, stationId: stationId, fetchedAt: _nowEpoch(), location: location), raw: json);
  }

  @override
  Future<List<StationSnapshot>> stationFrames(int stationId, String day, {tz.Location? location}) async {
    final json = await post(DeyeEndpoints.stationHistory, {'stationId': stationId, 'granularity': 1, 'startAt': day});
    final items = firstList(json, ['stationDataItems', 'dataList', 'list']);
    final fetched = _nowEpoch();
    final out = <StationSnapshot>[];
    for (final item in items) {
      final snap = StationSnapshot.fromApi(item, stationId: stationId, fetchedAt: fetched, location: location, source: SnapshotSource.history);
      if (snap != null && !snap.isEmpty) out.add(snap);
    }
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return out;
  }

  @override
  Future<List<StationEnergy>> stationDaily(int stationId, String startDay, String endDayExclusive, {tz.Location? location}) async {
    final out = <StationEnergy>[];
    var cursor = startDay;
    while (cursor.compareTo(endDayExclusive) < 0) {
      var chunkEnd = AppTime.addDays(cursor, 31);
      if (chunkEnd.compareTo(endDayExclusive) > 0) chunkEnd = endDayExclusive;
      final json = await post(DeyeEndpoints.stationHistory, {
        'stationId': stationId,
        'granularity': 2,
        'startAt': cursor,
        'endAt': chunkEnd,
      });
      final items = firstList(json, ['stationDataItems', 'dataList', 'list']);
      for (var i = 0; i < items.length; i++) {
        // Positional fallback: undated rows are assumed to be consecutive days from startAt.
        final e = StationEnergy.fromApi(items[i], stationId: stationId, monthly: false, fallbackPeriod: AppTime.addDays(cursor, i), location: location);
        if (e != null) out.add(e);
      }
      cursor = chunkEnd;
    }
    return out;
  }

  @override
  Future<List<StationEnergy>> stationMonthly(int stationId, String startMonth, String endMonth) async {
    final out = <StationEnergy>[];
    var cursor = startMonth;
    while (cursor.compareTo(endMonth) <= 0) {
      var chunkEnd = AppTime.addMonths(cursor, 11);
      if (chunkEnd.compareTo(endMonth) > 0) chunkEnd = endMonth;
      final json = await post(DeyeEndpoints.stationHistory, {
        'stationId': stationId,
        'granularity': 3,
        'startAt': cursor,
        'endAt': chunkEnd,
      });
      final items = firstList(json, ['stationDataItems', 'dataList', 'list']);
      for (var i = 0; i < items.length; i++) {
        final e = StationEnergy.fromApi(items[i], stationId: stationId, monthly: true, fallbackPeriod: AppTime.addMonths(cursor, i));
        if (e != null) out.add(e);
      }
      cursor = AppTime.addMonths(chunkEnd, 1);
    }
    return out;
  }

  // --------------------------------------------------------------- devices

  @override
  Future<List<DeviceLatest>> deviceLatest(List<String> serials, {tz.Location? location}) async {
    final out = <DeviceLatest>[];
    for (final batch in _chunks(serials, DeyeEndpoints.deviceLatestBatchSize)) {
      final json = await post(DeyeEndpoints.deviceLatest, {'deviceList': batch});
      final fetched = _nowEpoch();
      for (final item in firstList(json, ['deviceDataList', 'deviceList', 'dataList', 'list'])) {
        final d = DeviceLatest.fromApi(item, fetchedAt: fetched, location: location);
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  @override
  Future<List<String>> deviceMeasurePoints(String deviceSn) async {
    final json = await post(DeyeEndpoints.deviceMeasurePoints, {'deviceSn': deviceSn});
    final raw = pick(json, ['measurePoints', 'measurePointList', 'list', 'data']);
    if (raw is List) {
      return [
        for (final e in raw)
          if (e is String) e else if (e is Map) ?asString(pick(asMap(e), ['key', 'name', 'code'])),
      ];
    }
    return const [];
  }

  @override
  Future<List<DeviceLatest>> deviceHistory(String deviceSn, String day, List<String> measurePoints, {tz.Location? location}) async {
    final json = await post(DeyeEndpoints.deviceHistory, {
      'deviceSn': deviceSn,
      'granularity': 1,
      'startAt': day,
      'endAt': day,
      'measurePoints': measurePoints,
    });
    final fetched = _nowEpoch();
    final out = <DeviceLatest>[];
    for (final item in firstList(json, ['paramDataList', 'dataList', 'list', 'deviceDataList'])) {
      final d = DeviceLatest.fromApi({...item, 'deviceSn': deviceSn}, fetchedAt: fetched, location: location);
      if (d != null) out.add(d);
    }
    return out;
  }

  // ---------------------------------------------------------------- alerts

  @override
  Future<List<SolarAlert>> stationAlerts(int stationId, {required int from, required int to, String? stationName, tz.Location? location}) async {
    final out = <SolarAlert>[];
    final seen = <String>{};
    for (var page = 1; page <= 50; page++) {
      final body = {'stationId': stationId, 'startTimestamp': from, 'endTimestamp': to, 'page': page, 'size': 100};
      final json = await _postAlert(DeyeEndpoints.stationAlertCandidates, body, isStation: true);
      final items = firstList(json, ['alertList', 'stationAlertList', 'alertItems', 'alarmList', 'list', 'records']);
      final now = _nowEpoch();
      var added = 0;
      for (final item in items) {
        final a = SolarAlert.fromApi(item, stationId: stationId, stationName: stationName, now: now, location: location);
        if (a != null && seen.add(a.id)) {
          out.add(a);
          added++;
        }
      }
      final total = asInt(pick(json, ['total', 'totalCount']));
      if (items.isEmpty || added == 0 || items.length < 100 || (total != null && out.length >= total)) break;
    }
    return out;
  }

  @override
  Future<List<SolarAlert>> deviceAlerts(String deviceSn, {required int from, required int to, tz.Location? location}) async {
    final body = {'deviceSn': deviceSn, 'startTimestamp': from, 'endTimestamp': to};
    final json = await _postAlert(DeyeEndpoints.deviceAlertCandidates, body, isStation: false);
    final now = _nowEpoch();
    return [
      for (final item in firstList(json, ['alertList', 'deviceAlertList', 'alertItems', 'alarmList', 'list', 'records']))
        ?SolarAlert.fromApi(item, deviceSn: deviceSn, now: now, location: location),
    ];
  }

  /// Tries each candidate path until one answers with a *successful*
  /// DeyeCloud envelope. Business errors on a well-formed request (e.g. no
  /// permission) still count as "path exists" so the probe does not keep
  /// hammering the API; unknown-path errors move on to the next candidate.
  Future<Map<String, Object?>> _postAlert(List<String> candidates, Map<String, Object?> body, {required bool isStation}) async {
    final known = isStation ? _stationAlertPath : _deviceAlertPath;
    if (known != null) return post(known, body);
    if (_alertsUnsupported) {
      throw DeyeApiException(_alertsUnsupportedReason ?? 'Alert endpoint unavailable', endpoint: candidates.first, code: 'ALERTS_UNSUPPORTED');
    }
    DeyeApiException? last;
    for (final path in candidates) {
      try {
        final json = await post(path, body);
        if (isStation) {
          _stationAlertPath = path;
        } else {
          _deviceAlertPath = path;
        }
        log?.call('Alert endpoint resolved: $path');
        return json;
      } on DeyeApiException catch (e) {
        last = e;
        if (e.isAuthError || e.code == 'AUTH_LOCKED') rethrow;
        final pathExists = e.code != null && !e.isNotFound && !_looksLikeUnknownPath(e);
        if (pathExists) {
          if (isStation) {
            _stationAlertPath = path;
          } else {
            _deviceAlertPath = path;
          }
          log?.call('Alert endpoint $path exists but answered: ${e.message}');
          rethrow;
        }
      }
    }
    _alertsUnsupported = true;
    _alertsUnsupportedReason = 'No alert endpoint answered (tried ${candidates.join(', ')}); last: ${last?.message}';
    throw DeyeApiException(_alertsUnsupportedReason!, endpoint: candidates.first, httpStatus: last?.httpStatus, code: last?.code);
  }

  static bool _looksLikeUnknownPath(DeyeApiException e) {
    final m = e.message.toLowerCase();
    return m.contains('not found') || m.contains('no handler') || m.contains('not exist') || m.contains('404') || m.contains('unsupported') || m.contains('no mapping');
  }

  int _nowEpoch() => _clock().millisecondsSinceEpoch ~/ 1000;

  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, math.min(i + size, list.length));
    }
  }
}
