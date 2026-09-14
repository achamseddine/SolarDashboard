import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/theme.dart';

/// Link into the school directory with the filters already applied.
String schoolsRoute({String? query, String? region, String? caza, bool? connected, bool? solar, bool? monitored, String? filter}) {
  String? tri(bool? v) => v == null ? null : (v ? '1' : '0');
  final q = <String, String>{
    'query': ?query,
    'region': ?region,
    'caza': ?caza,
    'connected': ?tri(connected),
    'solar': ?tri(solar),
    'monitored': ?tri(monitored),
    'filter': ?filter,
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
