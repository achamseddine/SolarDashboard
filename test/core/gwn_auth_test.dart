import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/api/gwn_api_client.dart';
import 'package:unicef_solar_monitor/core/api/gwn_api_exception.dart';
import 'package:unicef_solar_monitor/core/api/gwn_endpoints.dart';
import 'package:unicef_solar_monitor/core/models/gwn_credentials.dart';

/// Records every request and answers from a supplied handler.
class _FakeServer implements HttpClientAdapter {
  _FakeServer(this.reply);

  final ResponseBody Function(RequestOptions options) reply;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) =>
    ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.gwn.cloud', validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return dio;
}

const creds = GwnCredentials(appId: '667041', secretKey: 's3cret', baseUrl: 'https://www.gwn.cloud');

void main() {
  test('the token is fetched from /oauth/token with client_credentials', () async {
    final server = _FakeServer((o) => o.path == GwnEndpoints.token
        ? _json('{"access_token":"t0ken","expires_in":3600}', 200)
        : _json('{"data":[]}', 200));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await client.authenticate();

    final token = server.seen.single;
    expect(token.path, '/oauth/token');
    expect(token.method, 'GET');
    expect(token.queryParameters, {
      'grant_type': 'client_credentials',
      'client_id': '667041',
      'client_secret': 's3cret',
    });
    expect(client.lastProbe['token'], startsWith('/oauth/token'));
  });

  test('signed calls carry appID, timestamp and a signature — never the secret', () async {
    final server = _FakeServer((o) => o.path == GwnEndpoints.token
        ? _json('{"access_token":"t0ken"}', 200)
        : _json('{"data":[{"id":"n1","name":"A School"}]}', 200));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    final networks = await client.listNetworks();
    expect(networks.single.id, 'n1');

    final call = server.seen.firstWhere((o) => o.path == GwnEndpoints.networkList.path);
    final q = call.queryParameters;
    expect(q.keys, containsAll(<String>['access_token', 'appID', 'timestamp', 'signature']));
    expect(q['access_token'], 't0ken');
    expect(q['appID'], '667041');
    expect(q.containsKey('secretKey'), isFalse, reason: 'the secret signs the request but is never sent');
    expect(call.uri.toString(), isNot(contains('s3cret')));

    // The signature is sha256("&" + params + "&" + sha256(body) + "&"), with
    // the secret inside the params — reproduce it exactly.
    final body = jsonEncode(call.data);
    final bodyHash = sha256.convert(utf8.encode(body)).toString();
    final params = 'access_token=t0ken&appID=667041&secretKey=s3cret&timestamp=${q['timestamp']}';
    final expected = sha256.convert(utf8.encode('&$params&$bodyHash&')).toString();
    expect(q['signature'], expected);
  });

  test('an endpoint answering 404 is retried with the other verb', () async {
    var getSeen = 0;
    final server = _FakeServer((o) {
      if (o.path == GwnEndpoints.token) return _json('{"access_token":"t0ken"}', 200);
      if (o.method == 'GET') {
        getSeen++;
        return _json('nope', 404);
      }
      return _json('{"data":[{"id":"n1","name":"A School"}]}', 200);
    });
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    final networks = await client.listNetworks();
    expect(networks.single.id, 'n1', reason: 'the POST retry should have succeeded');
    expect(getSeen, greaterThan(0), reason: 'the documented verb is tried first');
  });

  test('a rejection carries the server\'s own words and points at the region', () async {
    final server = _FakeServer((_) => _json('{"error":"invalid_client","error_description":"app not authorised"}', 401));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await expectLater(
      client.authenticate(),
      throwsA(isA<GwnApiException>().having((e) => e.message, 'message', allOf(
        contains('rejected it'),
        contains('www.gwn.cloud'),
        // A GWN account belongs to one data centre, so name the others.
        contains('eu.gwn.cloud'),
        // …and quote what the server actually said.
        contains('app not authorised'),
      ))),
    );

    // Rejected once, the standard client_credentials spellings are tried too.
    expect(server.seen.map((o) => o.method).toSet(), containsAll(<String>['GET', 'POST']));
    expect(server.seen.length, 3);
  });

  test('an unreachable host blames the network, not a closed transport', () async {
    final server = _FakeServer((o) => throw DioException.connectionError(
          requestOptions: o,
          reason: 'failed host lookup',
        ));
    final client = GwnApiClient(credentials: creds, dio: _dioWith(server));
    addTearDown(client.close);

    await expectLater(
      client.authenticate(),
      throwsA(isA<GwnApiException>().having((e) => e.message, 'message', allOf(
        contains('Could not reach www.gwn.cloud'),
        isNot(contains('after it was closed')),
      ))),
    );
  });
}
