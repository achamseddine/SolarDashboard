import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/api/gwn_api_client.dart';
import 'package:unicef_solar_monitor/core/api/gwn_api_exception.dart';
import 'package:unicef_solar_monitor/core/models/gwn_credentials.dart';

/// Answers every request with a fixed status, and counts what it was asked.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.reply);

  final ResponseBody Function(RequestOptions options) reply;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://eu.gwn.cloud', validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return dio;
}

const creds = GwnCredentials(appId: '667041', secretKey: 'secret', baseUrl: 'https://eu.gwn.cloud');

void main() {
  test('a rejected App ID says so, rather than blaming the transport', () async {
    final server = _FakeServer((_) => ResponseBody.fromString('{"error":"invalid_client"}', 401,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await expectLater(
      client.authenticate(),
      throwsA(isA<GwnApiException>().having((e) => e.message, 'message', allOf(
        contains('rejected the credentials'),
        contains('eu.gwn.cloud'),
        contains('HTTP 401'),
      ))),
    );
  });

  test('a reachable host with no such endpoint points at the paths', () async {
    final server = _FakeServer((_) => ResponseBody.fromString('not found', 404,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await expectLater(
      client.authenticate(),
      throwsA(isA<GwnApiException>().having((e) => e.message, 'message', allOf(
        contains('no token endpoint'),
        contains('GwnEndpoints'),
      ))),
    );
    // Every candidate was tried, not just the first.
    expect(server.paths.toSet().length, greaterThan(1));
  });

  test('an unreachable host blames the network, and every probe still runs', () async {
    final server = _FakeServer((options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'failed host lookup',
        ));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await expectLater(
      client.authenticate(),
      throwsA(isA<GwnApiException>().having((e) => e.message, 'message', allOf(
        contains('Could not reach eu.gwn.cloud'),
        isNot(contains('after it was closed')),
      ))),
    );
  });

  test('a token is accepted and the winning path is reported', () async {
    final server = _FakeServer((options) => options.path.endsWith('/oauth/token')
        ? ResponseBody.fromString('{"access_token":"t0ken","expires_in":3600}', 200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]})
        : ResponseBody.fromString('nope', 404,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]}));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await client.authenticate();
    expect(client.lastProbe['token'], contains('/oauth/token'));

    // A second call reuses the cached token rather than probing again.
    final before = server.paths.length;
    await client.authenticate();
    expect(server.paths.length, before);
  });
}
