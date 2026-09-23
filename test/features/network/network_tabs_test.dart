import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/connectivity/connectivity_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  /// Cards below the fold are not built until scrolled to.
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    final list = find.byType(ListView).last;
    for (var i = 0; i < 14 && f.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(f, findsWidgets);
  }

  testWidgets('connectivity carries the roll-out and every network tab', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);

    await tester.pumpWidget(env.wrap(const ConnectivityScreen()));
    await TestEnv.settle(tester, rounds: 8);

    // Roll-out (the MEHE membership list) is the landing tab.
    expect(find.widgetWithText(Tab, 'Roll-out'), findsOneWidget);
    expect(find.text('Internet connectivity'), findsWidgets);

    // Network overview: the executive headline, the matrix and the index.
    await tester.tap(find.widgetWithText(Tab, 'Network overview'));
    await TestEnv.settle(tester, rounds: 8);
    expect(find.text('Schools connected'), findsOneWidget);
    expect(find.text('Open critical incidents'), findsOneWidget);
    await scrollTo(tester, find.text('Infrastructure × adoption'));
    await scrollTo(tester, find.text('Technology Adoption Index'));
    await scrollTo(tester, find.text('Indicators that need another source'));

    await tester.tap(find.widgetWithText(Tab, 'Infrastructure'));
    await TestEnv.settle(tester, rounds: 6);
    expect(find.text('Infrastructure health'), findsOneWidget);
    expect(find.text('Access point'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Usage'));
    await TestEnv.settle(tester, rounds: 6);
    expect(find.text('Client devices per day'), findsOneWidget);
    await scrollTo(tester, find.text('Traffic by SSID'));

    await tester.tap(find.widgetWithText(Tab, 'Schools'));
    await TestEnv.settle(tester, rounds: 6);
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the matrix opens the school list filtered to that quadrant', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);

    await tester.pumpWidget(env.wrap(const ConnectivityScreen()));
    await TestEnv.settle(tester, rounds: 8);
    await tester.tap(find.widgetWithText(Tab, 'Network overview'));
    await TestEnv.settle(tester, rounds: 8);

    await scrollTo(tester, find.text('Technical intervention needed'));
    await tester.tap(find.text('Technical intervention needed').first);
    await TestEnv.settle(tester, rounds: 6);

    // The Schools tab is now showing, with a quadrant filter active.
    expect(find.byType(DataTable), findsOneWidget);
    final all = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'));
    expect(all.selected, isFalse, reason: 'a quadrant filter should be active, not "All"');
  });
}
