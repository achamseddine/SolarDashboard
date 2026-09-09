/// Error raised for any failed DeyeCloud call.
class DeyeApiException implements Exception {
  DeyeApiException(this.message, {this.code, this.httpStatus, this.endpoint, this.cause});

  /// DeyeCloud business code (e.g. `1000000` success, `1010001` auth failure).
  final String? code;
  final int? httpStatus;
  final String? endpoint;
  final String message;
  final Object? cause;

  bool get isAuthError {
    if (httpStatus == 401 || httpStatus == 403) return true;
    final c = code ?? '';
    final m = message.toLowerCase();
    return c.startsWith('101') ||
        m.contains('token') && (m.contains('expire') || m.contains('invalid')) ||
        m.contains('unauthor') ||
        m.contains('not login') ||
        m.contains('login');
  }

  bool get isRateLimited => httpStatus == 429 || message.toLowerCase().contains('too many') || message.toLowerCase().contains('frequen');

  bool get isServerError => (httpStatus ?? 0) >= 500;

  bool get isNetworkError => httpStatus == null && code == null;

  /// True when the endpoint itself does not exist (used to try alternative
  /// alert paths).
  bool get isNotFound => httpStatus == 404 || httpStatus == 405;

  @override
  String toString() =>
      'DeyeApiException(${endpoint ?? '-'} http=${httpStatus ?? '-'} code=${code ?? '-'}): $message';
}
