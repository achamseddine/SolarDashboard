/// GWN Cloud Open API endpoint catalogue.
///
/// The token path and the request signing were established from published
/// community examples of the GWN Manager API, not from the developer portal
/// (`doc.grandstream.dev` is unreachable from the build environment). The
/// shapes below match those examples; where an account disagrees, the client
/// falls back through the candidates and `lastProbe` reports what answered.
class GwnEndpoints {
  GwnEndpoints._();

  /// Regional hosts an account can live on.
  static const Map<String, String> hosts = {
    'Global (www.gwn.cloud)': 'https://www.gwn.cloud',
    'Europe (eu.gwn.cloud)': 'https://eu.gwn.cloud',
    'Americas (us.gwn.cloud)': 'https://us.gwn.cloud',
  };

  /// Prefix the data endpoints sit behind.
  static const String apiPrefix = '/oapi/v1.0.0';

  /// Token exchange. Sits at the host root, **not** under [apiPrefix] — the
  /// first build assumed otherwise and every path answered 404.
  ///
  /// `GET /oauth/token?grant_type=client_credentials&client_id=APP_ID`
  /// `&client_secret=SECRET_KEY`
  static const String token = '/oauth/token';

  /// One endpoint of the signed API: its path and the verb it expects.
  /// The client retries with the other verb if the first answers 404 or 405.
  static const ({String path, String method}) networkList = (path: '$apiPrefix/network/list', method: 'GET');
  static const ({String path, String method}) networkDetail = (path: '$apiPrefix/network/detail', method: 'POST');
  static const ({String path, String method}) apList = (path: '$apiPrefix/ap/list', method: 'POST');
  static const ({String path, String method}) deviceInfo = (path: '$apiPrefix/device/info', method: 'POST');

  /// Not seen in the reference examples; probed in order.
  static const List<({String path, String method})> switchListCandidates = [
    (path: '$apiPrefix/switch/list', method: 'POST'),
    (path: '$apiPrefix/device/list', method: 'POST'),
  ];
  static const List<({String path, String method})> clientStatsCandidates = [
    (path: '$apiPrefix/statistics/network', method: 'POST'),
    (path: '$apiPrefix/network/statistics', method: 'POST'),
    (path: '$apiPrefix/report/network', method: 'POST'),
  ];
  static const List<({String path, String method})> ssidStatsCandidates = [
    (path: '$apiPrefix/statistics/ssid', method: 'POST'),
    (path: '$apiPrefix/ssid/statistics', method: 'POST'),
  ];
  static const List<({String path, String method})> alarmCandidates = [
    (path: '$apiPrefix/alarm/list', method: 'POST'),
    (path: '$apiPrefix/event/list', method: 'POST'),
    (path: '$apiPrefix/alert/list', method: 'POST'),
  ];

  /// Page size used for list endpoints.
  static const int pageSize = 100;

  /// Page/size parameter namings tried by the paginator, in order.
  static const List<({String page, String size})> pagingSpellings = [
    (page: 'pageNum', size: 'pageSize'),
    (page: 'page', size: 'pageSize'),
    (page: 'pageNo', size: 'pageSize'),
    (page: 'offset', size: 'limit'),
  ];

  /// Keys a list payload may hide its rows under.
  static const List<String> listKeys = ['data', 'result', 'list', 'records', 'items', 'rows', 'content'];

  /// Keys carrying the total row count.
  static const List<String> totalKeys = ['total', 'totalCount', 'totalNum', 'count', 'totalElements'];
}
