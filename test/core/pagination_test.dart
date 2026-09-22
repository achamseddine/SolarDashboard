import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/api/deye_api_client.dart';
import 'package:unicef_solar_monitor/core/api/deye_endpoints.dart';
import 'package:unicef_solar_monitor/core/models/credentials.dart';
import 'package:unicef_solar_monitor/core/models/sync.dart';
import 'package:unicef_solar_monitor/core/sync/rate_limiter.dart';

/// The real account behind this app holds 219 plants.
const int kFleetSize = 219;

/// A stand-in DeyeCloud that answers `/account/token` and `/station/list`.
///
/// Each instance models one of the paging behaviours seen in the wild: it
/// honours exactly one page key and one size key (or none at all) and may
/// enforce a maximum page size. Anything it does not recognise is ignored —
/// which is precisely how a real backend ends up replaying page one forever.
class FakeDeyeServer extends Interceptor {
  FakeDeyeServer({
    this.rows = kFleetSize,
    this.pageKey,
    this.sizeKey,
    this.offsetBased = false,
    this.sizeCap,
    this.defaultSize = 20,
    this.reportTotal = true,
  });

  /// Number of plants the account holds.
  final int rows;

  /// Body key the server reads the page (or row offset) from; null means it
  /// ignores every spelling and always answers with the first page.
  final String? pageKey;

  /// Body key the server reads the page size from; unknown keys fall back to
  /// [defaultSize].
  final String? sizeKey;

  /// True when [pageKey] carries a row offset instead of a page number.
  final bool offsetBased;

  /// Largest page the server is willing to return, whatever was asked.
  final int? sizeCap;
  final int defaultSize;

  /// False for a server that never reports how many rows exist.
  final bool reportTotal;

  /// Bodies of every `/station/list` request received, in order.
  final List<Map<String, Object?>> listRequests = [];
  int tokenRequests = 0;

  int get listCalls => listRequests.length;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.startsWith(DeyeEndpoints.token)) {
      tokenRequests++;
      handler.resolve(_envelope(options, {'accessToken': 't', 'expiresIn': 3600}));
      return;
    }
    if (!options.path.startsWith(DeyeEndpoints.stationList)) {
      handler.resolve(_envelope(options, const {}));
      return;
    }
    final body = options.data is Map ? Map<String, Object?>.from(options.data as Map) : <String, Object?>{};
    listRequests.add(body);

    var size = (sizeKey == null ? null : body[sizeKey] as int?) ?? defaultSize;
    final cap = sizeCap;
    if (cap != null && size > cap) size = cap;

    var start = 0;
    final key = pageKey;
    if (key != null) {
      final raw = body[key];
      if (raw is int) start = offsetBased ? raw : (raw - 1) * size;
    }
    final end = start + size > rows ? rows : start + size;
    final page = <Map<String, Object?>>[
      for (var i = start; i < end; i++)
        {'id': 1000 + i, 'name': 'Plant $i', 'installedCapacity': 5.5, 'locationAddress': 'Beirut'},
    ];
    handler.resolve(_envelope(options, {
      if (reportTotal) 'total': rows,
      'stationList': page,
    }));
  }

  Response<Object?> _envelope(RequestOptions options, Map<String, Object?> payload) => Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: {'code': '1000000', 'success': true, 'msg': 'OK', ...payload},
      );
}

/// Builds a client wired to [server] with no rate-limit delay.
({DeyeApiClient client, List<String> logs}) clientFor(FakeDeyeServer server) {
  final dio = Dio(BaseOptions(baseUrl: 'https://fake.deyecloud.test/v1.0', validateStatus: (_) => true))
    ..interceptors.add(server);
  final logs = <String>[];
  final client = DeyeApiClient(
    credentials: DeyeCredentials(appId: 'app', appSecret: 'secret', email: 'ops@unicef.test', passwordSha256: 'a' * 64),
    dio: dio,
    limiter: RateLimiter(minGap: Duration.zero),
    log: logs.add,
  );
  return (client: client, logs: logs);
}

void main() {
  test('a server that honours page/size returns the whole fleet in two requests', () async {
    final server = FakeDeyeServer(pageKey: 'page', sizeKey: 'size');
    final (:client, :logs) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(kFleetSize));
    expect(stations.map((s) => s.id).toSet(), hasLength(kFleetSize));
    // 219 rows at the default page size of 200: one full page plus the tail.
    expect(server.listCalls, 2);
    expect(client.resolvedPagingSpelling(DeyeEndpoints.stationList), 'page/size');
    final report = client.lastStationListReport!;
    expect(report.truncated, isFalse);
    expect(report.total, kFleetSize);
    expect(client.lastListTotal, kFleetSize);
    expect(logs, contains('/station/list: received 219 of 219 items (paging: page/size)'));
  });

  test('a server that ignores page but honours pageNo is detected and still yields every plant', () async {
    final server = FakeDeyeServer(pageKey: 'pageNo', sizeKey: 'pageSize');
    final (:client, :logs) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(kFleetSize), reason: 'the stall must not truncate the fleet');
    expect(client.resolvedPagingSpelling(DeyeEndpoints.stationList), 'pageNo/pageSize');
    expect(client.lastStationListReport!.truncated, isFalse);
    // Two wasted requests proving page/size does not advance, then two good ones.
    expect(server.listCalls, 4);
    expect(server.listRequests.first.containsKey('page'), isTrue);
    expect(server.listRequests[2]['pageNo'], 1);
    expect(logs.any((l) => l.contains('paging stalled at 20/219 with page/size')), isTrue);
    expect(logs, contains('/station/list: paging advances with pageNo/pageSize'));
  });

  test('a server that caps the page size keeps paging with the size it gave', () async {
    final server = FakeDeyeServer(pageKey: 'page', sizeKey: 'size', sizeCap: 20);
    final (:client, :logs) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(kFleetSize));
    expect(client.lastStationListReport!.truncated, isFalse);
    // 219 rows in pages of 20 = 11 requests, all with the first spelling.
    expect(server.listCalls, 11);
    expect(server.listRequests.last['page'], 11);
    expect(server.listRequests.last['size'], 20);
    expect(logs.any((l) => l.contains('capped the page at 20 rows (asked 200)')), isTrue);
  });

  test('a server that never advances reports the shortfall instead of looping', () async {
    // Recognises no paging key at all: every request replays the first 20 rows.
    final server = FakeDeyeServer();
    final (:client, :logs) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(20), reason: 'only the rows the server would hand over');
    // Every spelling probed exactly twice — bounded, not an infinite loop.
    expect(server.listCalls, DeyeEndpoints.pagingSpellings.length * 2);
    expect(client.resolvedPagingSpelling(DeyeEndpoints.stationList), isNull, reason: 'nothing won, so nothing is cached');
    final report = client.lastStationListReport!;
    expect(report.truncated, isTrue);
    expect(report.received, 20);
    expect(report.total, kFleetSize);
    expect(report.message('plants'), 'DeyeCloud reported 219 plants, 20 were fetched');
    expect(logs.any((l) => l.startsWith('/station/list: received 20 of 219 items (paging: ')), isTrue);
  });

  test('the winning spelling is reused on the next sync without re-probing', () async {
    final server = FakeDeyeServer(pageKey: 'pageNo', sizeKey: 'pageSize');
    final (:client, logs: _) = clientFor(server);

    await client.listStations();
    final afterProbe = server.listCalls;
    final second = await client.listStations();

    expect(second, hasLength(kFleetSize));
    expect(server.listCalls - afterProbe, 2, reason: 'straight to pageNo/pageSize, no probing');
    expect(server.listRequests.skip(afterProbe).every((b) => b.containsKey('pageNo')), isTrue);
    expect(server.tokenRequests, 1, reason: 'the token is cached across calls');
  });

  test('an offset-based server is covered by the spelling list', () async {
    final server = FakeDeyeServer(pageKey: 'offset', sizeKey: 'limit', offsetBased: true);
    final (:client, logs: _) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(kFleetSize));
    expect(client.resolvedPagingSpelling(DeyeEndpoints.stationList), 'offset/limit (offset)');
    expect(server.listRequests.last['offset'], 200);
  });

  test('a server that never reports a total still stops at the short page', () async {
    final server = FakeDeyeServer(pageKey: 'page', sizeKey: 'size', reportTotal: false, rows: 150);
    final (:client, logs: _) = clientFor(server);

    final stations = await client.listStations();

    expect(stations, hasLength(150));
    expect(server.listCalls, 1, reason: 'a page shorter than asked ends the listing');
    expect(client.lastStationListReport!.truncated, isFalse);
  });

  test('SyncStatus carries and clears the truncation warning', () {
    const base = SyncStatus();
    expect(base.truncation, isNull);
    expect(base.isTruncated, isFalse);

    final warned = base.copyWith(truncation: 'DeyeCloud reported 219 plants, 20 were fetched');
    expect(warned.isTruncated, isTrue);
    // Unrelated updates keep the warning on screen.
    expect(warned.copyWith(phase: SyncPhase.done).truncation, warned.truncation);
    expect(warned.copyWith(clearTruncation: true).truncation, isNull);
  });
}
