import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/school.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/school_link_dialog.dart';
import 'package:unicef_solar_monitor/features/stations/widgets/school_profile_card.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('school profile card shows the linked MEHE record and the picker sets a manual link', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    late Map<int, StationSchoolLink> links;
    await tester.runAsync(() async => links = await env.db.schools.getLinks());
    expect(links, isNotEmpty, reason: 'the demo fleet impersonates real solarised schools, so automatic links must exist');
    final id = links.keys.first;
    final link = links[id]!;
    late School school;
    await tester.runAsync(() async => school = (await env.db.schools.getSchool(link.cerd))!);

    await tester.pumpWidget(env.wrap(ListView(children: [SchoolProfileCard(stationId: id)])));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text(school.name), findsWidgets);
    expect(find.textContaining('CERD ${school.cerd}'), findsWidgets);
    expect(find.text(school.connected ? 'Connected' : 'Not in connectivity roll-out'), findsOneWidget);
    expect(find.text('Change link'), findsOneWidget);
    expect(find.text('School'), findsOneWidget);
    expect(find.textContaining('Source: MEHE public school list'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Open the picker: automatic suggestions are listed.
    await tester.tap(find.text('Change link'));
    await TestEnv.settle(tester, rounds: 3);
    expect(find.byType(SchoolLinkDialog), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.text('Re-run automatic matching'), findsOneWidget);
    final rows = find.descendant(of: find.byType(SchoolLinkDialog), matching: find.byType(ListTile));
    expect(rows, findsWidgets);
    expect(tester.takeException(), isNull);

    // Search and pick a school by hand.
    await tester.enterText(find.byType(TextField), 'Uruguay');
    await TestEnv.settle(tester, rounds: 3);
    expect(rows, findsOneWidget);
    expect(find.descendant(of: rows, matching: find.textContaining('Uruguay')), findsOneWidget);
    await tester.tap(rows.first);
    await TestEnv.settle(tester, rounds: 3);
    expect(find.byType(SchoolLinkDialog), findsNothing);

    StationSchoolLink? manual;
    await tester.runAsync(() async => manual = await env.db.schools.linkForStation(id));
    expect(manual, isNotNull);
    expect(manual!.isManual, isTrue);
    expect(manual!.cerd, 1);

    // The card follows the new link.
    await TestEnv.settle(tester, rounds: 3);
    expect(find.textContaining('Uruguay First Achrafieh'), findsWidgets);
    expect(find.textContaining('Set by hand'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('a plant without a link shows the not-linked card', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 3);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SingleChildScrollView(child: SchoolProfileCard(stationId: 99999))));
    await TestEnv.settle(tester, rounds: 3);
    expect(find.text('School record'), findsOneWidget);
    expect(find.text('This plant is not linked to a MEHE school record.'), findsOneWidget);
    expect(find.text('Link to a school'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });
}
