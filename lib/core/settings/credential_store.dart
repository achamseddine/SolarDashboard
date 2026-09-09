import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/deye_api_client.dart';
import '../models/credentials.dart';

/// Reads/writes DeyeCloud credentials in the platform secure store
/// (Android Keystore-backed EncryptedSharedPreferences, libsecret on Linux,
/// DPAPI on Windows). Nothing here is ever written to the SQLite file.
class CredentialStore implements TokenCache {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAppId = 'deye.appId';
  static const _kAppSecret = 'deye.appSecret';
  static const _kEmail = 'deye.email';
  static const _kPassword = 'deye.passwordSha256';
  static const _kCompanyId = 'deye.companyId';
  static const _kRegion = 'deye.region';
  static const _kToken = 'deye.accessToken';
  static const _kTokenExpiry = 'deye.accessTokenExpiry';
  static const _kSeeded = 'deye.seededFromDefines';

  /// Build-time seeds (`--dart-define=DEYE_APP_ID=...`). Empty when not set.
  static const seedAppId = String.fromEnvironment('DEYE_APP_ID');
  static const seedAppSecret = String.fromEnvironment('DEYE_APP_SECRET');
  static const seedEmail = String.fromEnvironment('DEYE_EMAIL');
  static const seedPassword = String.fromEnvironment('DEYE_PASSWORD_SHA256');
  static const seedCompanyId = String.fromEnvironment('DEYE_COMPANY_ID');
  static const seedRegion = String.fromEnvironment('DEYE_REGION', defaultValue: 'eu');

  static bool get hasSeed => seedAppId.isNotEmpty && seedAppSecret.isNotEmpty && seedEmail.isNotEmpty && seedPassword.isNotEmpty;

  /// Returns stored credentials, or those seeded at build time on first
  /// launch, or null.
  Future<DeyeCredentials?> load() async {
    final appId = await _read(_kAppId);
    if (appId == null || appId.isEmpty) {
      if (hasSeed && (await _read(_kSeeded)) != '1') {
        final seeded = DeyeCredentials(
          appId: seedAppId,
          appSecret: seedAppSecret,
          email: seedEmail,
          passwordSha256: DeyeCredentials.normalisePassword(seedPassword),
          companyId: seedCompanyId.isEmpty ? null : seedCompanyId,
          region: DeyeRegion.fromName(seedRegion),
        );
        await save(seeded);
        await _write(_kSeeded, '1');
        return seeded;
      }
      return null;
    }
    return DeyeCredentials(
      appId: appId,
      appSecret: await _read(_kAppSecret) ?? '',
      email: await _read(_kEmail) ?? '',
      passwordSha256: await _read(_kPassword) ?? '',
      companyId: await _read(_kCompanyId),
      region: DeyeRegion.fromName(await _read(_kRegion)),
    );
  }

  Future<void> save(DeyeCredentials c) async {
    await _write(_kAppId, c.appId.trim());
    await _write(_kAppSecret, c.appSecret.trim());
    await _write(_kEmail, c.email.trim());
    await _write(_kPassword, c.passwordSha256);
    await _write(_kCompanyId, c.companyId?.trim());
    await _write(_kRegion, c.region.name);
    await clear(); // token belongs to the previous credentials
  }

  Future<void> deleteAll() async {
    for (final k in [_kAppId, _kAppSecret, _kEmail, _kPassword, _kCompanyId, _kRegion, _kToken, _kTokenExpiry]) {
      await _storage.delete(key: k);
    }
  }

  // TokenCache -----------------------------------------------------------

  @override
  Future<String?> read() async {
    final token = await _read(_kToken);
    if (token == null || token.isEmpty) return null;
    final exp = int.tryParse(await _read(_kTokenExpiry) ?? '');
    if (exp != null && exp > 0 && exp - 300 < DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      await clear();
      return null;
    }
    return token;
  }

  @override
  Future<void> write(String token, {int? expiresAtEpoch}) async {
    await _write(_kToken, token);
    await _write(_kTokenExpiry, expiresAtEpoch?.toString());
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTokenExpiry);
  }

  Future<String?> _read(String k) async {
    try {
      return await _storage.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String k, String? v) async {
    try {
      if (v == null || v.isEmpty) {
        await _storage.delete(key: k);
      } else {
        await _storage.write(key: k, value: v);
      }
    } catch (_) {
      // Secure storage can be unavailable on some desktops (no keyring); fail soft.
    }
  }
}
