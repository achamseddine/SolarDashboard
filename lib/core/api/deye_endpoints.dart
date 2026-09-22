/// DeyeCloud Open API v1 endpoint catalogue.
///
/// All paths are relative to a region base URL and are called with `POST`.
/// See `docs/API_REFERENCE.md` for request/response shapes.
class DeyeEndpoints {
  DeyeEndpoints._();

  static const String euBaseUrl = 'https://eu1-developer.deyecloud.com/v1.0';
  static const String usBaseUrl = 'https://us1-developer.deyecloud.com/v1.0';

  // Account
  static const String token = '/account/token'; // + ?appId=
  static const String accountInfo = '/account/info';

  // Station (plant) operations
  static const String stationList = '/station/list';
  static const String stationListWithDevice = '/station/listWithDevice';
  static const String stationDevice = '/station/device';
  static const String stationLatest = '/station/latest';
  static const String stationHistory = '/station/history';

  // Device operations
  static const String deviceList = '/device/list';
  static const String deviceLatest = '/device/latest';
  static const String deviceHistory = '/device/history';
  static const String deviceMeasurePoints = '/device/measurePoints';

  /// Alert endpoints were launched on 18 Dec 2024 (see ChangeLog). Their exact
  /// paths are not reproduced in public samples, so the client probes these
  /// candidates in order and remembers the first that answers with a DeyeCloud
  /// envelope. Edit these if your developer-portal documentation differs.
  static const List<String> stationAlertCandidates = [
    '/station/alertList',
    '/station/alert/list',
    '/station/alert',
  ];
  static const List<String> deviceAlertCandidates = [
    '/device/alertList',
    '/device/alert/list',
    '/device/alert',
  ];

  /// Maximum serial numbers accepted by [deviceLatest] per call.
  static const int deviceLatestBatchSize = 10;

  /// Page size used for list endpoints.
  static const int pageSize = 200;

  /// Page/size parameter namings tried by the paginator, in order.
  ///
  /// DeyeCloud deployments are not consistent about how a list request asks
  /// for the next page: some honour `page`/`size`, others only react to
  /// `pageNo`/`pageSize` (or one of the other spellings below) and silently
  /// keep answering with the first page otherwise. The client walks this list
  /// until one of them actually advances and then remembers the winner.
  static const List<PagingSpelling> pagingSpellings = [
    PagingSpelling('page', 'size'),
    PagingSpelling('pageNo', 'pageSize'),
    PagingSpelling('pageIndex', 'pageSize'),
    PagingSpelling('current', 'size'),
    PagingSpelling('pageNum', 'pageSize'),
    PagingSpelling('offset', 'limit', offsetBased: true),
  ];

  /// Maximum station ids sent to [stationDevice] per call.
  static const int stationDeviceIdBatch = 20;
}

/// One way of naming the paging parameters of a list endpoint.
///
/// [pageKey] carries a 1-based page number unless [offsetBased] is true, in
/// which case it carries the number of rows to skip.
class PagingSpelling {
  const PagingSpelling(this.pageKey, this.sizeKey, {this.offsetBased = false});

  final String pageKey;
  final String sizeKey;
  final bool offsetBased;

  /// Body fragment requesting the [page]-th (1-based) page of [size] rows.
  Map<String, Object?> params(int page, int size) => {
        pageKey: offsetBased ? (page - 1) * size : page,
        sizeKey: size,
      };

  /// Short label used in logs, e.g. `pageNo/pageSize` or `offset/limit`.
  String get label => offsetBased ? '$pageKey/$sizeKey (offset)' : '$pageKey/$sizeKey';

  @override
  String toString() => label;
}
