import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/fleet_insights_builder.dart';
import 'package:unicef_solar_monitor/core/insights/school_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/school.dart';
import 'package:unicef_solar_monitor/core/models/station.dart';
import 'package:unicef_solar_monitor/core/schools/station_school_linker.dart';

import '../helpers/test_env.dart';

void main() {
  test('bundled dataset parses and imports', () async {
    final ds = TestEnv.dataset;
    expect(ds.version, 1);
    expect(ds.schools.length, greaterThan(1200));
    expect(ds.solarizedCount, greaterThan(200));
    expect(ds.connectedCount, 534);
    expect(ds.equipment.length, greaterThan(7000));
    expect(ds.demoSeeds.length, greaterThan(150));
    // Personal data must not be bundled.
    expect(ds.schools.every((s) => s.phone == null || !s.phone!.contains('Director')), isTrue);

    final env = await TestEnv.create(sync: false);
    final counts = await env.db.tableCounts();
    expect(counts['schools'], ds.schools.length);
    expect(counts['school_solar'], ds.schools.where((s) => s.solar != null).length);
    expect(counts['school_equipment'], ds.equipment.length);
    expect(counts['school_education'], ds.schools.where((s) => s.education != null).length);

    final one = await env.db.schools.getSchool(1);
    expect(one, isNotNull);
    expect(one!.name, contains('Uruguay'));
    expect(one.connected, isTrue);
    expect(one.solar?.status, SolarStatus.completed);
    expect(one.solar?.kwp, 84);
    expect(one.loads?.totalKwh, greaterThan(300000));
    expect(one.education?.pmRisk, RiskLevel.high);
    expect((await env.db.schools.equipmentFor(1)).length, greaterThan(5));

    // Importing again with the same version is a no-op; force re-imports.
    final again = await env.db.schools.countSchools();
    expect(again, ds.schools.length);
    await env.dispose();
  });

  test('transliteration folding unifies common spellings', () {
    String f(String s) => StationSchoolLinker.tokenize(s).join(' ');
    expect(f('Achrafieh'), f('Ashrafiyeh'));
    expect(f('Wata Mousseitbeh'), f('Wata Al Msaytbeh'));
    expect(f('Tariq Jdide First Mixed'), f('Tarik El Jdideh 1st Mixed Public School'));
    expect(f('Ibtihaj Kaddoura'), f('Ibtihaj Qaddoura'));
    expect(StationSchoolLinker.tokenize('CERD 123 Public School'), contains('123'));
  });

  test('demo plants link to the schools they were seeded from', () async {
    final env = await TestEnv.create(schools: 60);
    final links = await env.db.schools.getLinks();
    final truth = env.api.seedByStation;
    expect(truth.length, 60);
    var correct = 0, wrong = 0;
    for (final e in truth.entries) {
      final l = links[e.key];
      if (l == null) continue;
      if (l.cerd == e.value.cerd) {
        correct++;
      } else {
        wrong++;
      }
    }
    expect(wrong, 0, reason: 'no plant may be linked to the wrong school');
    expect(correct, greaterThanOrEqualTo(54), reason: 'at least 90 % of the seeded plants should be linked');
    expect(links.values.every((l) => l.confidence > 0.5), isTrue);

    // A manual link survives re-linking; deleting it lets the matcher decide again.
    final stationId = truth.keys.first;
    await env.db.schools.setLink(StationSchoolLink(stationId: stationId, cerd: 5, method: LinkMethod.manual, confidence: 1, updatedAt: 1));
    final schools = await env.db.schools.getSchools();
    await StationSchoolLinker(schools).linkAll(env.db);
    expect((await env.db.schools.linkForStation(stationId))!.cerd, 5);
    await env.db.schools.deleteLink(stationId);
    await StationSchoolLinker(schools).linkAll(env.db);
    expect((await env.db.schools.linkForStation(stationId))!.cerd, truth[stationId]!.cerd);

    // Unrelated names do not link.
    final linker = StationSchoolLinker(schools);
    expect(linker.match(const Station(id: 1, name: 'Test plant XYZ')), isNull);
    expect(linker.match(const Station(id: 2, name: 'Plant CERD 1 rooftop'))?.school.cerd, 1);
    expect(linker.suggestions(const Station(id: 3, name: 'Uruguay Achrafieh')).first.school.cerd, 1);
    await env.dispose();
  });

  test('programme insights join the dataset with the fleet', () async {
    final env = await TestEnv.create(schools: 40);
    final fleet = await FleetInsightsBuilder(env.db).build(env.settings);
    final ins = await SchoolInsightsBuilder(env.db).build(env.settings, fleet);
    expect(ins.publicSchools, 1211);
    expect(ins.solarized, greaterThan(200));
    expect(ins.connected, 534);
    expect(ins.solarizedConnected, greaterThan(100));
    expect(ins.stations, 40);
    expect(ins.monitored, greaterThanOrEqualTo(36));
    expect(ins.monitored + ins.unlinkedStations.length, lessThanOrEqualTo(40));
    expect(ins.installedKwp, greaterThan(5000));
    expect(ins.investmentUsd, greaterThan(5e6));
    expect(ins.costPerKwp, greaterThan(500));
    expect(ins.regions.map((r) => r.name), contains('Akkar'));
    expect(ins.regions.fold(0, (a, r) => a + r.schools), ins.publicSchools);
    expect(ins.byDonor.first.label, 'KfW');
    expect(ins.loadByCategory['Lighting'], greaterThan(0));
    expect(ins.topEquipment, isNotEmpty);
    expect(ins.attendance.first.countA, greaterThan(100));
    expect(ins.solarCandidates.length, greaterThan(100));
    expect(ins.fleetSizingRatio, isNotNull);
    final monitored = ins.monitoredSchools.toList();
    expect(monitored, isNotEmpty);
    expect(monitored.where((s) => s.measuredCoverage != null), isNotEmpty);
    expect(ins.forStation(monitored.first.station!.id)?.cerd, monitored.first.cerd);
    await env.dispose();
  });
}
