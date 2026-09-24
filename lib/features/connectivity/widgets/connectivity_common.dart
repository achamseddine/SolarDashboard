import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/theme.dart';

/// Link into the school directory with the filters already applied.
///
/// [master] restricts the list to the MEHE master list, which is the
/// population every figure on this page is counted over — without it the
/// directory shows the orphan connectivity records the page leaves out, and
/// the list disagrees with the tile it was opened from.
String schoolsRoute({String? query, String? region, String? caza, bool? connected, bool? solar, bool? monitored, String? filter, bool master = true}) {
  String? tri(bool? v) => v == null ? null : (v ? '1' : '0');
  final q = <String, String>{
    'query': ?query,
    'region': ?region,
    'caza': ?caza,
    'connected': ?tri(connected),
    'solar': ?tri(solar),
    'monitored': ?tri(monitored),
    'filter': ?filter,
    'master': ?tri(master),
  };
  return Uri(path: '/schools', queryParameters: q.isEmpty ? null : q).toString();
}

/// Colour of one solar × internet combination (same scale on the tiles, the
/// donut and the legend).
Color quadrantColor(ConnectivityQuadrant q) => switch (q) {
      ConnectivityQuadrant.both => AppColors.good,
      ConnectivityQuadrant.solarOnly => AppColors.pv,
      ConnectivityQuadrant.internetOnly => AppColors.unicefCyan,
      ConnectivityQuadrant.neither => AppColors.muted,
    };

IconData quadrantIcon(ConnectivityQuadrant q) => switch (q) {
      ConnectivityQuadrant.both => Icons.check_circle_outline,
      ConnectivityQuadrant.solarOnly => Icons.cloud_off_outlined,
      ConnectivityQuadrant.internetOnly => Icons.wifi_outlined,
      ConnectivityQuadrant.neither => Icons.remove_circle_outline,
    };

/// Directory filter matching one combination.
String quadrantRoute(ConnectivityQuadrant q) => switch (q) {
      ConnectivityQuadrant.both => schoolsRoute(solar: true, connected: true),
      ConnectivityQuadrant.solarOnly => schoolsRoute(solar: true, connected: false),
      ConnectivityQuadrant.internetOnly => schoolsRoute(solar: false, connected: true),
      ConnectivityQuadrant.neither => schoolsRoute(solar: false, connected: false),
    };
