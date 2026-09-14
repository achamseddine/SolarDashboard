import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/connectivity_insights_builder.dart';
import 'package:unicef_solar_monitor/core/insights/fleet_insights_builder.dart';
import 'package:unicef_solar_monitor/core/insights/school_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/connectivity_insights.dart';
import 'package:unicef_solar_monitor/core/models/school_query.dart';

import '../helpers/test_env.dart';

void main() {
  test('connectivity insights and the school directory cover every school', () async {
    final env = await TestEnv.create(schools: 30);
    final fleet = await FleetInsightsBuilder(env.db).build(env.settings);
    final programme = await SchoolInsightsBuilder(env.db).build(env.settings, fleet);
    final conn = await ConnectivityInsightsBuilder(env.db).build(programme);

    expect(conn.schools, 1211);
    expect(conn.connected, greaterThan(500));
    expect(conn.byRegion.length, greaterThanOrEqualTo(8));
    expect(conn.byRegion.fold(0, (a, r) => a + r.schools), conn.schools);
    expect(conn.byCaza.fold(0, (a, r) => a + r.connected), conn.connected);
    expect(conn.quadrants.values.fold(0, (a, b) => a + b), conn.schools);
    expect(conn.quadrant(ConnectivityQuadrant.both), conn.solarizedConnected);
    expect(conn.students, greaterThan(300000));
    expect(conn.connectedStudents, lessThan(conn.students));
    expect(conn.monitored, greaterThan(0));
    expect(conn.topGaps, isNotEmpty);
    expect(conn.bestServed.first.share, greaterThanOrEqualTo(conn.bestServed.last.share));
    expect(conn.share, closeTo(conn.connected / conn.schools, 1e-9));

    // Directory filters
    const q = SchoolQuery();
    expect(q.apply(programme.schools).length, greaterThan(1200));
    expect(const SchoolQuery(connected: true).apply(programme.schools).length, 534);
    expect(const SchoolQuery(connected: false, solarized: true).apply(programme.schools).length, programme.solarized - programme.solarizedConnected);
    expect(const SchoolQuery(monitored: true).apply(programme.schools).length, programme.monitored);
    expect(const SchoolQuery(region: 'Akkar').apply(programme.schools).every((s) => s.region == 'Akkar'), isTrue);
    expect(const SchoolQuery(search: 'uruguay').apply(programme.schools).first.cerd, 1);
    expect(const SchoolQuery(search: '454').apply(programme.schools).map((s) => s.cerd), contains(454));
    final sorted = const SchoolQuery(sort: SchoolSort.students, ascending: false).apply(programme.schools);
    expect(sorted.first.students!, greaterThanOrEqualTo(sorted[5].students!));
    expect(const SchoolQuery(hasAudit: true).apply(programme.schools).every((s) => (s.annualLoadKwh ?? 0) > 0), isTrue);

    // DAO filter options
    expect((await env.db.schools.cazaCounts()).length, greaterThan(20));
    expect((await env.db.schools.ownershipCounts()).first.$1, 'MEHE');
    expect((await env.db.schools.getSchools(caza: 'Akkar')).length, greaterThan(100));
    expect((await env.db.schools.getSchools(hasAudit: true)).length, greaterThan(700));
    await env.dispose();
  });
}
