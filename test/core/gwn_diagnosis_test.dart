import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/api/gwn_api_client.dart';
import 'package:unicef_solar_monitor/core/models/gwn_credentials.dart';

void main() {
  // A synthetic key of the length GWN issues. A real one must never be
  // written down here: this repository is public, and a test fixture is a
  // credential the moment it is a real credential.
  const key = 'A1b2C3d4E5f6G7h8J9k0L1m2N3p4Q5r6';
  final short = key.substring(0, key.length - 3);
  const other = 'Z9y8X7w6V5u4T3s2R1q0P9n8M7k6J5h4';

  GwnCredentials creds(String secret, {String host = 'https://www.gwn.cloud'}) =>
      GwnCredentials(appId: '667041', secretKey: secret, baseUrl: host);

  GwnLastAuth worked(String secret, {String host = 'www.gwn.cloud'}) => GwnLastAuth(
        appId: '667041',
        host: host,
        keyLength: secret.length,
        fingerprint: gwnKeyFingerprint(secret),
        ts: DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        strategy: 'POST form',
      );

  const rejected = ['/oauth/token (POST form): HTTP 401 — {"error":"invalid_client","error_description":"Bad client credentials"}'];

  test('no failure shape ever carries the key or a run of it', () {
    for (final secret in [key, short, other]) {
      for (final attempts in [
        rejected,
        ['/oauth/token: Network error'],
        ['/oauth/token: HTTP 404'],
      ]) {
        for (final last in [null, worked(key), worked(other)]) {
          final m = gwnLoginDiagnosis(creds(secret), attempts, lastSuccess: last);
          expect(m, isNot(contains(secret)), reason: 'the key must never appear in a message that gets photographed');
          expect(m, isNot(contains(secret.substring(0, 8))));
          expect(m, isNot(contains(secret.substring(secret.length - 8))));
        }
      }
    }
  });

  test('with no history, rotation leads and the region is offered', () {
    final m = gwnLoginDiagnosis(creds(key), rejected);
    expect(m, contains('667041'), reason: 'the App ID is not a secret and identifies the account');
    expect(m, contains('32 characters'));
    expect(m, contains('has not authenticated'), reason: 'say plainly there is nothing to compare against');
    expect(m, contains('re-issued'));
    expect(m, contains('Europe'), reason: 'without history the region cannot be ruled out');
  });

  test('the same key that last worked means it was changed at the portal', () {
    final m = gwnLoginDiagnosis(creds(key), rejected, lastSuccess: worked(key));
    expect(m, contains('same key that last worked'));
    expect(m, contains('changed at the portal'));
    expect(m, contains('3 days ago'));
    expect(m, isNot(contains('Europe')), reason: 'the region is proven by the last success on this host');
  });

  test('a different key from the one that last worked is named as such', () {
    final m = gwnLoginDiagnosis(creds(other), rejected, lastSuccess: worked(key));
    expect(m, contains('not the key that last worked'));
    expect(m, isNot(contains('Europe')));
  });

  test('a change of host since the last success is pointed out', () {
    final m = gwnLoginDiagnosis(creds(key, host: 'https://eu.gwn.cloud'), rejected, lastSuccess: worked(key));
    expect(m, contains('last worked on www.gwn.cloud'));
  });

  test('a short key is the finding, and its fingerprint is withheld', () {
    final m = gwnLoginDiagnosis(creds(short), rejected, lastSuccess: worked(key));
    expect(m, contains('${short.length} characters'));
    expect(m, contains('part of it is missing'));
    final tiny = gwnLoginDiagnosis(creds('abcd'), rejected);
    expect(tiny, contains('not shown for a key this short'), reason: 'six hex characters of four could be walked back');
  });

  test('a long key is not called short', () {
    final m = gwnLoginDiagnosis(creds('${key}xyz'), rejected);
    expect(m, contains('something extra'));
    expect(m, isNot(contains('missing')));
  });

  test('invalid_client rules out a disabled grant, anything else keeps it', () {
    expect(gwnLoginDiagnosis(creds(key), rejected), isNot(contains('client-credentials grant')));
    expect(gwnLoginDiagnosis(creds(key), ['/oauth/token (POST form): HTTP 403 — forbidden']), contains('client-credentials grant'));
  });

  test('the fingerprint identifies an entry without revealing it', () {
    expect(gwnKeyFingerprint(key), gwnKeyFingerprint(key));
    expect(gwnKeyFingerprint(key), isNot(gwnKeyFingerprint(other)));
    expect(gwnKeyFingerprint(key), matches(RegExp(r'^[0-9a-f]{6}$')));
  });

  test('pasted keys lose what a paste carries invisibly', () {
    expect(GwnCredentials.clean(' $key\n'), key);
    expect(GwnCredentials.clean('${key.substring(0, 10)}​${key.substring(10)}'), key);
    expect(GwnCredentials.clean('﻿$key '), key);
  });

  test('an unreachable host is not reported as a credential problem', () {
    final m = gwnLoginDiagnosis(creds(key), ['/oauth/token: Network error']);
    expect(m, contains('Could not reach'));
    expect(m, isNot(contains('fingerprint')));
  });

  test('the last success survives a round trip through preferences', () {
    final a = worked(key);
    final prefs = a.toPrefs();
    final b = GwnLastAuth.fromPrefs((k) => prefs[k] is String ? prefs[k] as String : null, (k) => prefs[k] is int ? prefs[k] as int : null)!;
    expect(b.fingerprint, a.fingerprint);
    expect(b.keyLength, a.keyLength);
    expect(b.host, a.host);
    expect(b.ts, a.ts);
    expect(prefs.values.whereType<String>(), isNot(contains(key)), reason: 'the key itself is never stored here');
  });
}
