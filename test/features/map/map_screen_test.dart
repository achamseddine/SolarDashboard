import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/map/map_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('map renders markers for every located plant without tiles', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const MapScreen(showTiles: false)));
    await TestEnv.settle(tester);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.textContaining('20 of 20 plants on the map'), findsOneWidget);
    expect(find.text('Plant status'), findsOneWidget);
    expect(find.byType(MarkerLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public schools layer adds school markers and legend entries', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    int markerCount() => tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).fold(0, (n, l) => n + l.markers.length);

    await tester.pumpWidget(env.wrap(const MapScreen(showTiles: false)));
    await TestEnv.settle(tester);
    expect(markerCount(), 20);
    expect(find.text('Public schools'), findsOneWidget);
    expect(find.text('Connected only'), findsNothing);
    expect(find.textContaining('schools shown'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Public schools'));
    await TestEnv.settle(tester, rounds: 4);
    expect(find.byType(MarkerLayer), findsNWidgets(2));
    final withSchools = markerCount();
    expect(withSchools, greaterThan(20 + 500), reason: 'every located, unmonitored public school gets a dot');
    expect(find.textContaining('schools shown'), findsOneWidget);
    expect(find.text('Solarised, no monitored plant'), findsOneWidget);
    expect(find.text('Connected only'), findsOneWidget);
    // Plant markers are still all there: the plant count line is unchanged.
    expect(find.textContaining('20 of 20 plants on the map'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Connected only'));
    await tester.pump(const Duration(milliseconds: 300));
    final connectedOnly = markerCount();
    expect(connectedOnly, lessThan(withSchools));
    expect(connectedOnly, greaterThan(20));
    expect(tester.takeException(), isNull);

    // Tapping a school dot opens the school sheet. Hundreds of dots overlap at
    // this zoom, so trigger the first dot's tap callback directly.
    final dot = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SchoolDot');
    expect(dot, findsWidgets);
    (tester.widget(dot.first) as dynamic).onTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('CERD '), findsOneWidget);
    expect(find.text('Audited load'), findsOneWidget);
    expect(find.text('Internet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Turning the layer off removes the dots again.
    await tester.tapAt(const Offset(700, 40)); // dismiss the sheet
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilterChip, 'Public schools'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(markerCount(), 20);
    expect(find.textContaining('schools shown'), findsNothing);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  testWidgets('connectivity mode recolours the school layer and the legend', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    int markerCount() => tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)).fold(0, (n, l) => n + l.markers.length);

    await tester.pumpWidget(env.wrap(const MapScreen(showTiles: false)));
    await TestEnv.settle(tester);
    final plantsOnly = markerCount();
    expect(plantsOnly, 20);
    // The chip only appears once the school layer is on.
    expect(find.widgetWithText(FilterChip, 'Connectivity'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Public schools'));
    await TestEnv.settle(tester, rounds: 4);
    final solarColouring = markerCount();
    expect(find.widgetWithText(FilterChip, 'Connectivity'), findsOneWidget);
    expect(find.text('Solarised, no monitored plant'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Connectivity'));
    await tester.pump(const Duration(milliseconds: 300));
    final connectivity = markerCount();
    expect(connectivity, greaterThanOrEqualTo(plantsOnly));
    // Monitored schools join the layer in connectivity mode.
    expect(connectivity, greaterThan(solarColouring));
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('No internet'), findsOneWidget);
    expect(find.textContaining('connected of'), findsOneWidget);
    // The solar-status legend gives way to the connectivity one.
    expect(find.text('Solarised, no monitored plant'), findsNothing);
    // Plant markers and their filters are untouched.
    expect(find.textContaining('20 of 20 plants on the map'), findsOneWidget);
    expect(find.text('Plant status'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Turning it off restores the solar-status colouring and drops the
    // monitored schools from the layer again.
    await tester.tap(find.widgetWithText(FilterChip, 'Connectivity'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(markerCount(), solarColouring);
    expect(find.text('Solarised, no monitored plant'), findsOneWidget);
    expect(find.text('No internet'), findsNothing);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });
}
