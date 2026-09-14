import '../db/app_database.dart';
import '../models/connectivity_insights.dart';
import '../models/school_insights.dart';

/// Builds [ConnectivityInsights] from the school dataset joined with the
/// programme insights (which already carry the plant links).
class ConnectivityInsightsBuilder {
  ConnectivityInsightsBuilder(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<ConnectivityInsights> build(SchoolInsights programme) async {
    final regionRows = await db.schools.connectivityBy('region');
    final cazaRows = await db.schools.connectivityBy('caza');

    // Solar overlay per governorate / district, from the programme insights.
    final solarByRegion = <String, (int, int)>{};
    final solarByCaza = <String, (int, int)>{};
    final quadrants = <ConnectivityQuadrant, int>{};
    final quadrantStudents = <ConnectivityQuadrant, int>{};
    var schools = 0, connected = 0, students = 0, connectedStudents = 0;
    var solarized = 0, solarizedConnected = 0, monitored = 0, monitoredConnected = 0;
    var connectedWithCoordinates = 0, downWithoutInternet = 0, connectivityOnly = 0;

    for (final s in programme.schools) {
      final sc = s.school;
      if (!sc.inMaster) {
        if (sc.connected) connectivityOnly++;
        continue;
      }
      schools++;
      final enrol = sc.enrollment ?? 0;
      students += enrol;
      if (sc.connected) {
        connected++;
        connectedStudents += enrol;
        if (sc.hasLocation) connectedWithCoordinates++;
      }
      if (s.isSolarized) {
        solarized++;
        final region = s.region;
        final prevR = solarByRegion[region] ?? (0, 0);
        solarByRegion[region] = (prevR.$1 + 1, prevR.$2 + (sc.connected ? 1 : 0));
        final caza = sc.caza ?? 'Unassigned';
        final prevC = solarByCaza[caza] ?? (0, 0);
        solarByCaza[caza] = (prevC.$1 + 1, prevC.$2 + (sc.connected ? 1 : 0));
        if (sc.connected) solarizedConnected++;
      }
      if (s.isMonitored) {
        monitored++;
        if (sc.connected) monitoredConnected++;
        if (s.station!.isDown && !sc.connected) downWithoutInternet++;
      }
      final q = ConnectivityInsights.quadrantOf(sc);
      quadrants[q] = (quadrants[q] ?? 0) + 1;
      quadrantStudents[q] = (quadrantStudents[q] ?? 0) + enrol;
    }

    ConnectivityGroup group(
      (String, int, int, int, int) row,
      Map<String, (int, int)> solar,
    ) {
      final s = solar[row.$1] ?? (0, 0);
      return ConnectivityGroup(
        name: row.$1,
        schools: row.$2,
        connected: row.$3,
        students: row.$4,
        connectedStudents: row.$5,
        solarized: s.$1,
        solarizedConnected: s.$2,
      );
    }

    final byRegion = [for (final r in regionRows) group(r, solarByRegion)]..sort((a, b) => b.schools.compareTo(a.schools));
    final byCaza = [for (final r in cazaRows) group(r, solarByCaza)];

    final topGaps = [...byCaza]..sort((a, b) => b.notConnected.compareTo(a.notConnected));
    final bestServed = [for (final c in byCaza) if (c.schools >= 5) c]..sort((a, b) => b.share.compareTo(a.share));

    return ConnectivityInsights(
      generatedAt: _clock(),
      byRegion: byRegion,
      byCaza: byCaza..sort((a, b) => b.notConnected.compareTo(a.notConnected)),
      quadrants: quadrants,
      quadrantStudents: quadrantStudents,
      schools: schools,
      connected: connected,
      students: students,
      connectedStudents: connectedStudents,
      solarized: solarized,
      solarizedConnected: solarizedConnected,
      monitored: monitored,
      monitoredConnected: monitoredConnected,
      connectedWithCoordinates: connectedWithCoordinates,
      downWithoutInternet: downWithoutInternet,
      connectivityOnlyRecords: connectivityOnly,
      topGaps: topGaps.take(10).toList(),
      bestServed: bestServed.take(10).toList(),
    );
  }
}
