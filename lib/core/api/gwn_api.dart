import '../models/gwn.dart';

/// Abstract GWN Cloud gateway used by the network sync. Implemented by
/// [GwnApiClient] (real HTTP) and `DemoGwnApi` (synthetic data), exactly as
/// the DeyeCloud side is.
///
/// Keeping the app behind this port means the wire format lives in one place:
/// when the Open API's exact paths and field names are confirmed, only
/// `GwnEndpoints` and `GwnApiClient` change.
abstract class GwnApi {
  /// Ensures a valid access token exists (no-op when cached).
  Future<void> authenticate();

  /// Every network (school LAN) visible to the account.
  Future<List<GwnNetwork>> listNetworks();

  /// Managed devices of one network — APs, switches and the gateway.
  Future<List<GwnDevice>> listDevices(String networkId);

  /// Daily counters of one network between two `yyyy-MM-dd` days, inclusive.
  Future<List<GwnNetworkDay>> networkDaily(String networkId, String fromDay, String toDay);

  /// Daily traffic split by SSID for one network.
  Future<List<GwnSsidDay>> ssidDaily(String networkId, String fromDay, String toDay);

  /// Alarms raised for the account, newest first.
  Future<List<GwnAlarm>> listAlarms({String? networkId, int? sinceTs});

  /// Frees any transport resources.
  void close() {}
}
