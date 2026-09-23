/// GWN Cloud Open API endpoint catalogue.
///
/// **These paths are not yet confirmed against the developer portal.** The
/// documentation at `doc.grandstream.dev/GWN-API` was unreachable from the
/// build environment, so each call is expressed as an ordered list of
/// candidates and the client keeps the first that answers with a GWN
/// envelope — the same probing the DeyeCloud client already does for its
/// alert endpoints. Replace a list with the single documented path once it is
/// known; nothing outside this file has to change.
class GwnEndpoints {
  GwnEndpoints._();

  /// Regional hosts an account can live on.
  static const Map<String, String> hosts = {
    'Global (www.gwn.cloud)': 'https://www.gwn.cloud',
    'Europe (eu.gwn.cloud)': 'https://eu.gwn.cloud',
    'Americas (us.gwn.cloud)': 'https://us.gwn.cloud',
  };

  /// Prefix every Open API path sits behind.
  static const String apiPrefix = '/oapi/v1.0.0';

  /// Token exchange: App ID + Secret Key in, bearer token out.
  static const List<String> tokenCandidates = [
    '$apiPrefix/oauth/token',
    '$apiPrefix/token',
    '/oapi/v1.0.0/auth/token',
  ];

  /// Field names the token request may expect for the App ID and Secret Key.
  static const List<({String id, String secret})> tokenFieldSpellings = [
    (id: 'app_id', secret: 'app_secret'),
    (id: 'appId', secret: 'secretKey'),
    (id: 'client_id', secret: 'client_secret'),
  ];

  static const List<String> networkListCandidates = [
    '$apiPrefix/network/list',
    '$apiPrefix/networks',
    '$apiPrefix/network',
  ];

  static const List<String> deviceListCandidates = [
    '$apiPrefix/device/list',
    '$apiPrefix/devices',
    '$apiPrefix/ap/list',
  ];

  /// Per-network daily statistics (clients, traffic, uptime).
  static const List<String> networkStatsCandidates = [
    '$apiPrefix/statistics/network',
    '$apiPrefix/network/statistics',
    '$apiPrefix/report/network',
  ];

  /// Per-SSID daily traffic.
  static const List<String> ssidStatsCandidates = [
    '$apiPrefix/statistics/ssid',
    '$apiPrefix/ssid/statistics',
    '$apiPrefix/report/ssid',
  ];

  static const List<String> alarmListCandidates = [
    '$apiPrefix/alarm/list',
    '$apiPrefix/alarms',
    '$apiPrefix/event/list',
  ];

  /// Page size used for list endpoints.
  static const int pageSize = 100;

  /// Page/size parameter namings tried by the paginator, in order — GWN
  /// deployments are no more consistent about this than DeyeCloud's.
  static const List<({String page, String size})> pagingSpellings = [
    (page: 'page', size: 'pageSize'),
    (page: 'pageNum', size: 'pageSize'),
    (page: 'pageNo', size: 'pageSize'),
    (page: 'offset', size: 'limit'),
  ];

  /// Keys a list payload may hide its rows under.
  static const List<String> listKeys = ['data', 'result', 'list', 'records', 'items', 'rows', 'content'];

  /// Keys carrying the total row count.
  static const List<String> totalKeys = ['total', 'totalCount', 'totalNum', 'count', 'totalElements'];
}
