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
}
