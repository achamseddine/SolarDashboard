import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/features/common/widgets.dart';
import 'package:unicef_solar_monitor/features/dashboard/widgets/dashboard_common.dart';
import 'package:unicef_solar_monitor/features/connectivity/connectivity_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  Future<void> openOverview(WidgetTester tester, TestEnv env) async {
    await tester.pumpWidget(env.wrap(const ConnectivityScreen()));
    await TestEnv.settle(tester, rounds: 8);
    await tester.tap(find.widgetWithText(Tab, 'Network overview'));
    await TestEnv.settle(tester, rounds: 8);
  }

  testWidgets('every headline tile opens what its number is made of', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);
    await openOverview(tester, env);

    // The whole headline grid, tile by tile: each one must open a panel and
    // close again cleanly. A tile that is not a target fails here.
    const labels = [
      'Schools connected',
      'LAN operational',
      'Meaningfully connected',
      'Actively using technology',
      'High digital adoption',
      'Low / no adoption',
      'Technical intervention',
      'Adoption support',
      'Average network uptime',
      'Active client devices',
      'Open critical incidents',
      'Networks in the account',
    ];
    for (final label in labels) {
      final tile = find.widgetWithText(KpiTile, label);
      expect(tile, findsOneWidget, reason: '$label should be on the headline grid');
      expect(tester.widget<KpiTile>(tile).onTap, isNotNull, reason: '$label should be tappable');

      await tester.tap(tile);
      await tester.pumpAndSettle();
      // The panel repeats the label as its title and says what it counts.
      expect(find.text(label), findsWidgets, reason: 'the panel for $label should name it');
      expect(find.byType(BottomSheet), findsOneWidget, reason: '$label opened nothing');

      await tester.tapAt(const Offset(640, 12));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a headline panel lists the schools behind the figure and carries them to the table', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);
    await openOverview(tester, env);

    await tester.tap(find.widgetWithText(KpiTile, 'Schools connected'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tap one for its full record'), findsOneWidget);

    // One school from the list opens its own record.
    final row = find.byType(CompactRow).first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    // The record opens on its status block; the rest is below the fold.
    expect(find.text('Where it sits'), findsOneWidget);
    expect(find.text('Seen online'), findsOneWidget);
    await tester.tapAt(const Offset(640, 12));
    await tester.pumpAndSettle();

    // …and the slice itself can be carried to the Schools tab.
    await tester.tap(find.widgetWithText(FilledButton, 'Open in the Schools tab'));
    await tester.pumpAndSettle();
    await TestEnv.settle(tester, rounds: 4);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Schools connected'), findsOneWidget);
  });

  testWidgets('a tappable table row is a row, not a selection', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);
    await tester.pumpWidget(env.wrap(const ConnectivityScreen()));
    await TestEnv.settle(tester, rounds: 8);
    await tester.tap(find.widgetWithText(Tab, 'Schools'));
    await TestEnv.settle(tester, rounds: 6);

    // Giving a DataRow an onSelectChanged makes Flutter add a checkbox column
    // and a select-all box in the header — which would open one sheet per
    // school at a single tap.
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.widget<DataTable>(find.byType(DataTable)).showCheckboxColumn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a filter cleared on the Schools tab stays cleared', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);
    await openOverview(tester, env);

    await tester.tap(find.widgetWithText(KpiTile, 'Schools connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open in the Schools tab'));
    await tester.pumpAndSettle();
    await TestEnv.settle(tester, rounds: 4);
    final chip = find.widgetWithText(InputChip, 'Schools connected');
    expect(chip, findsOneWidget);

    // Clearing the chip has to reach the screen, or leaving the tab and
    // coming back brings the filter with it.
    tester.widget<InputChip>(chip).onDeleted!();
    await TestEnv.settle(tester, rounds: 4);
    expect(find.widgetWithText(InputChip, 'Schools connected'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Roll-out'));
    await TestEnv.settle(tester, rounds: 6);
    await tester.tap(find.widgetWithText(Tab, 'Schools'));
    await TestEnv.settle(tester, rounds: 6);
    expect(find.widgetWithText(InputChip, 'Schools connected'), findsNothing);

    // …and the same tile can send it here again.
    await tester.tap(find.widgetWithText(Tab, 'Network overview'));
    await TestEnv.settle(tester, rounds: 6);
    await tester.tap(find.widgetWithText(KpiTile, 'Schools connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open in the Schools tab'));
    await tester.pumpAndSettle();
    await TestEnv.settle(tester, rounds: 4);
    expect(find.widgetWithText(InputChip, 'Schools connected'), findsOneWidget);
  });

  testWidgets('infrastructure figures open the schools behind them', (tester) async {
    final env = await TestEnv.createFor(tester, schools: 10, networks: 30);
    addTearDown(env.dispose);
    await tester.pumpWidget(env.wrap(const ConnectivityScreen()));
    await TestEnv.settle(tester, rounds: 8);
    await tester.tap(find.widgetWithText(Tab, 'Infrastructure'));
    await TestEnv.settle(tester, rounds: 8);

    await tester.tap(find.text('Access point'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.textContaining('schools that have at least one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
