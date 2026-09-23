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

  final String appId;
  final String secretKey;
  final String baseUrl;

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
