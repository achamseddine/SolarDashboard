/// GWN Cloud Open API credentials: the App ID and Secret Key issued in the
/// cloud account, plus the regional host the account lives on.
///
/// Nothing here is ever written to SQLite or to the repository — the values
/// live in the platform secure store (see `CredentialStore`) or are seeded at
/// build time with `--dart-define`.
class GwnCredentials {
  const GwnCredentials({
    required this.appId,
    required this.secretKey,
    this.baseUrl = defaultBaseUrl,
  });

  /// Default regional host. Accounts provisioned elsewhere override it in
  /// Settings.
  static const String defaultBaseUrl = 'https://www.gwn.cloud';

  /// Length of the Secret Keys GWN Cloud issues. Used only to tell an
  /// operator that what they typed looks short — never to reject a key, in
  /// case the portal ever issues another length.
  static const int usualKeyLength = 32;

  /// Strips everything that cannot be part of a key but can be carried
  /// invisibly by a paste: spaces, newlines, non-breaking spaces, the
  /// zero-width characters and a byte-order mark. Trimming the ends alone
  /// leaves an interior one in place, and nothing on screen shows it.
  static String clean(String v) => v.replaceAll(RegExp(r'[\s\u00A0\u200B-\u200F\u2028\u2029\uFEFF]'), '');

  final String appId;
  final String secretKey;
  final String baseUrl;

  /// The credentials as they should go on the wire.
  GwnCredentials get cleaned => GwnCredentials(appId: clean(appId), secretKey: clean(secretKey), baseUrl: baseUrl.trim());

  bool get isComplete => appId.trim().isNotEmpty && secretKey.trim().isNotEmpty;

  GwnCredentials copyWith({String? appId, String? secretKey, String? baseUrl}) => GwnCredentials(
        appId: appId ?? this.appId,
        secretKey: secretKey ?? this.secretKey,
        baseUrl: baseUrl ?? this.baseUrl,
      );

  /// Never put the secret in a log line or an error message.
  @override
  String toString() => 'GwnCredentials(appId: ${appId.isEmpty ? '–' : '${appId.substring(0, appId.length.clamp(0, 3))}…'}, baseUrl: $baseUrl)';
}

/// What the last successful GWN login used.
///
/// None of it is secret: the fingerprint is a one-way hash of the key and the
/// length is a count. Kept so that a later rejection can say what changed
/// rather than list everything that might have — the difference between "the
/// key stored here is the one that worked, so it was changed at the portal"
/// and "what is stored is not what worked".
class GwnLastAuth {
  const GwnLastAuth({
    required this.appId,
    required this.host,
    required this.keyLength,
    required this.fingerprint,
    required this.ts,
    this.strategy,
  });

  final String appId;
  final String host;
  final int keyLength;
  final String fingerprint;

  /// Seconds since the epoch.
  final int ts;

  /// Which token strategy the deployment accepted.
  final String? strategy;

  static const String prefix = 'gwn.lastAuth';

  Map<String, Object> toPrefs() => {
        '$prefix.appId': appId,
        '$prefix.host': host,
        '$prefix.keyLength': keyLength,
        '$prefix.fingerprint': fingerprint,
        '$prefix.ts': ts,
        '$prefix.strategy': ?strategy,
      };

  static GwnLastAuth? fromPrefs(String? Function(String) getString, int? Function(String) getInt) {
    final fp = getString('$prefix.fingerprint');
    final ts = getInt('$prefix.ts');
    if (fp == null || fp.isEmpty || ts == null) return null;
    return GwnLastAuth(
      appId: getString('$prefix.appId') ?? '',
      host: getString('$prefix.host') ?? '',
      keyLength: getInt('$prefix.keyLength') ?? 0,
      fingerprint: fp,
      ts: ts,
      strategy: getString('$prefix.strategy'),
    );
  }
}
