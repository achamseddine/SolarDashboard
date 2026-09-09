import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/overview/overview_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('overview landing page shows generation, consumption and carbon headline cards', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 20);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const OverviewScreen()));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('Power generation'), findsOneWidget);
    expect(find.text('Power consumption'), findsOneWidget);
    expect(find.text('Carbon footprint avoided'), findsOneWidget);
    expect(find.textContaining('UNICEF school solar fleet'), findsOneWidget);
    expect(find.text('Since commissioning'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      for (final label in ['Generation vs consumption today', 'Energy balance', 'Carbon footprint avoided by month', 'Fleet health', 'Generation today by governorate']) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(['Generation vs consumption today', 'Energy balance', 'Carbon footprint avoided by month', 'Fleet health', 'Generation today by governorate']));
    await TestEnv.drain(tester);
  });
}
