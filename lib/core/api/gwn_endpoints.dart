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

  /// Endpoints confirmed against published examples of this API, with the
  /// verb and the body keys each takes.
  static const ({String path, String method}) networkList = (path: '$apiPrefix/network/list', method: 'GET');
  static const ({String path, String method}) networkDetail = (path: '$apiPrefix/network/detail', method: 'POST');
  static const ({String path, String method}) apList = (path: '$apiPrefix/ap/list', method: 'POST');
  static const ({String path, String method}) ssidList = (path: '$apiPrefix/ssid/list', method: 'POST');

  /// Switches and gateways are not in the published examples; these are
  /// probed, and an account that exposes neither simply reports no switches.
  static const List<({String path, String method})> switchListCandidates = [
    (path: '$apiPrefix/switch/list', method: 'POST'),
    (path: '$apiPrefix/device/list', method: 'POST'),
  ];

  static const List<({String path, String method})> alarmCandidates = [
    (path: '$apiPrefix/alarm/list', method: 'POST'),
    (path: '$apiPrefix/event/list', method: 'POST'),
    (path: '$apiPrefix/alert/list', method: 'POST'),
  ];

  /// This API version exposes no time-series statistics: there is no
  /// `statistics/*` or `report/*` family, only the list and detail endpoints
  /// above. Daily counters are therefore accrued by the app from repeated
  /// observations rather than fetched — see `NetworkSync`.
  static const bool exposesHistory = false;

  /// The body a list endpoint expects, alongside its paging parameters.
  static Map<String, Object?> listBody({String? networkId}) => {
        'search': '',
        'order': '',
        'networkId': ?networkId,
      };

  /// Page size used for list endpoints.
  static const int pageSize = 100;

  /// Paging, as the published examples spell it.
  static const ({String page, String size}) paging = (page: 'pageNum', size: 'pageSize');

  /// Keys a list payload may hide its rows under.
  static const List<String> listKeys = ['data', 'result', 'list', 'records', 'items', 'rows', 'content'];

  /// Keys carrying the total row count.
  static const List<String> totalKeys = ['total', 'totalCount', 'totalNum', 'count', 'totalElements'];
}
