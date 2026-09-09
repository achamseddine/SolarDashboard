import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../api/deye_endpoints.dart';

/// DeyeCloud data centre.
enum DeyeRegion {
  eu('EU (eu1-developer.deyecloud.com)', DeyeEndpoints.euBaseUrl),
  us('US (us1-developer.deyecloud.com)', DeyeEndpoints.usBaseUrl);

  const DeyeRegion(this.label, this.baseUrl);
  final String label;
  final String baseUrl;

  static DeyeRegion fromName(String? name) =>
      DeyeRegion.values.firstWhere((r) => r.name == name, orElse: () => DeyeRegion.eu);
}

/// Everything needed to obtain a DeyeCloud access token.
class DeyeCredentials {
  const DeyeCredentials({
    required this.appId,
    required this.appSecret,
    required this.email,
    required this.passwordSha256,
    this.companyId,
    this.region = DeyeRegion.eu,
  });

  final String appId;
  final String appSecret;
  final String email;

  /// Lower-case hex SHA-256 of the DeyeCloud password.
  final String passwordSha256;

  /// Optional organisation id; when set the token acts as a business member.
  final String? companyId;
  final DeyeRegion region;

  bool get isComplete =>
      appId.trim().isNotEmpty && appSecret.trim().isNotEmpty && email.trim().isNotEmpty && passwordSha256.trim().isNotEmpty;

  String get baseUrl => region.baseUrl;

  DeyeCredentials copyWith({
    String? appId,
    String? appSecret,
    String? email,
    String? passwordSha256,
    String? companyId,
    bool clearCompanyId = false,
    DeyeRegion? region,
  }) =>
      DeyeCredentials(
        appId: appId ?? this.appId,
        appSecret: appSecret ?? this.appSecret,
        email: email ?? this.email,
        passwordSha256: passwordSha256 ?? this.passwordSha256,
        companyId: clearCompanyId ? null : (companyId ?? this.companyId),
        region: region ?? this.region,
      );

  /// Accepts either a plain password (hashed here) or an already hashed
  /// 64-character hex digest (returned unchanged, lower-cased).
  static String normalisePassword(String input) {
    final t = input.trim();
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) return t.toLowerCase();
    return sha256.convert(utf8.encode(t)).toString();
  }

  Map<String, Object?> toTokenBody() => {
        'appSecret': appSecret.trim(),
        'email': email.trim(),
        'password': passwordSha256,
        if (companyId != null && companyId!.trim().isNotEmpty) 'companyId': companyId!.trim(),
      };

  @override
  String toString() => 'DeyeCredentials(appId=$appId, email=$email, companyId=$companyId, region=${region.name})';
}
