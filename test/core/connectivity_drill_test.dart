import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/connectivity_insights_builder.dart';
import 'package:unicef_solar_monitor/core/insights/fleet_insights_builder.dart';
import 'package:unicef_solar_monitor/core/insights/school_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/connectivity_insights.dart';
import 'package:unicef_solar_monitor/core/models/school_insights.dart';
import 'package:unicef_solar_monitor/core/models/school_query.dart';

import '../helpers/test_env.dart';

void main() {
  test('every roll-out tile opens a list of exactly the schools it counted', () async {
    final env = await TestEnv.create(schools: 30);
    addTearDown(env.dispose);
    final fleet = await FleetInsightsBuilder(env.db).build(env.settings);
    final programme = await SchoolInsightsBuilder(env.db).build(env.settings, fleet);
    final conn = await ConnectivityInsightsBuilder(env.db).build(programme);

    // The page counts the MEHE master list; the directory will happily show
    // the connectivity records that are not in it. Those orphans exist — the
    // page says so — so the route has to exclude them or the list behind a
    // tile is larger than the tile.
    expect(conn.connectivityOnlyRecords, greaterThan(0), reason: 'this test is meaningless without orphan records');

    int list({String? connected, String? solar, String? monitored, String? region, String? caza}) => SchoolQuery.fromRoute(
          connected: connected,
          solar: solar,
          monitored: monitored,
          region: region,
          caza: caza,
          master: '1',
        ).apply(programme.schools).length;

    expect(list(connected: '1'), conn.connected, reason: 'Connected schools');
    expect(list(connected: '0'), conn.notConnected, reason: 'Schools without internet');
    expect(list(solar: '1', connected: '1'), conn.quadrant(ConnectivityQuadrant.both), reason: 'Solar + internet');
    expect(list(solar: '1', connected: '0'), conn.quadrant(ConnectivityQuadrant.solarOnly), reason: 'Solarised without internet');
    expect(list(solar: '0', connected: '1'), conn.quadrant(ConnectivityQuadrant.internetOnly));
    expect(list(solar: '0', connected: '0'), conn.quadrant(ConnectivityQuadrant.neither));
    expect(list(monitored: '1'), conn.monitored, reason: 'Monitored plants');

    // …and so do the governorate bars and the district rankings.
    final region = conn.byRegion.first;
    expect(list(region: region.name, connected: '0'), region.notConnected, reason: region.name);
    final gap = conn.topGaps.first;
    expect(list(caza: gap.name, connected: '0'), gap.notConnected, reason: gap.name);
    final best = conn.bestServed.first;
    // The best-served ranking is about the share connected, so its rows open
    // the connected schools. Sending them to the without-internet list —
    // which is what they used to do — shows the opposite of the figure, and
    // at the top of the ranking often shows nothing at all.
    expect(list(caza: best.name, connected: '1'), best.connected, reason: best.name);
    expect(best.share, greaterThanOrEqualTo(conn.topGaps.first.share));

    // Without the flag the orphans come back, which is what the flag is for.
    final loose = SchoolQuery.fromRoute(connected: '1').apply(programme.schools).length;
    expect(loose, conn.connected + conn.connectivityOnlyRecords);

    // The directory still shows an orphan when someone goes looking for it.
    final orphan = programme.schools.firstWhere((s) => !s.school.inMaster && s.school.connected);
    expect(SchoolQuery(search: '${orphan.cerd}').apply(programme.schools).map((s) => s.cerd), contains(orphan.cerd));
  });

  test('a school insight carries the master-list flag the routes filter on', () async {
    final env = await TestEnv.create(schools: 5);
    addTearDown(env.dispose);
    final fleet = await FleetInsightsBuilder(env.db).build(env.settings);
    final programme = await SchoolInsightsBuilder(env.db).build(env.settings, fleet);

    final master = programme.schools.where((s) => s.school.inMaster).length;
    expect(const SchoolQuery(inMasterOnly: true).apply(programme.schools).length, master);
    expect(
      const SchoolQuery(inMasterOnly: true).apply(programme.schools).every((SchoolInsight s) => s.school.inMaster),
      isTrue,
    );
  });
}
