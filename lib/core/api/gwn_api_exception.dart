/// A GWN Cloud call that did not return usable data.
class GwnApiException implements Exception {
  GwnApiException(this.message, {this.endpoint, this.status, this.code});

  final String message;
  final String? endpoint;
  final int? status;
  final String? code;

  bool get isNetworkError => status == null;
  bool get isServerError => status != null && status! >= 500;
  bool get isAuthError => status == 401 || status == 403 || code == 'AUTH';

  @override
  String toString() => 'GwnApiException($message${endpoint == null ? '' : ' at $endpoint'}${status == null ? '' : ' [$status]'})';
}
