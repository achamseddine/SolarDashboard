import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/credentials.dart';
import 'package:unicef_solar_monitor/features/settings/settings_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('settings shows every section and persists a toggle', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 5);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SettingsScreen()));
    await TestEnv.settle(tester, rounds: 2);
    expect(find.text('DeyeCloud account'), findsOneWidget);
    expect(find.text('Demo mode'), findsOneWidget);
    // Both accounts — DeyeCloud for the plants, GWN Cloud for the networks.
    expect(find.text('GWN Cloud account (school networks)'), findsOneWidget);
    expect(find.text('Test connection'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Cards below the fold are built lazily: scroll until each one appears.
    final list = find.byType(ListView).first;
    Future<void> scrollTo(Finder f) async {
      for (var i = 0; i < 12 && f.evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(f, findsOneWidget);
    }

    await scrollTo(find.text('Synchronisation'));
    final dark = find.widgetWithText(SwitchListTile, 'Dark mode');
    await scrollTo(dark);
    // Scrolling stops the moment the row exists, which can leave it half off
    // the viewport; the tap has to land on it, not near it.
    await tester.ensureVisible(dark);
    await tester.pump();
    await tester.tap(dark);
    await TestEnv.settle(tester, rounds: 1);
    expect(env.prefs.getBool('settings.darkMode'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings shows the school dataset card and re-links plants', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 5);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const SettingsScreen()));
    await TestEnv.settle(tester, rounds: 3);
    expect(find.text('School dataset'), findsOneWidget);
    expect(find.text('Solarised'), findsOneWidget);
    expect(find.textContaining('1,2'), findsWidgets); // 1,246 schools in the bundled dataset
    expect(find.textContaining('by hand'), findsOneWidget);
    final relink = find.widgetWithText(OutlinedButton, 'Re-link plants');
    expect(relink, findsOneWidget);
    await tester.ensureVisible(relink);
    await tester.pump();
    await tester.tap(relink);
    await TestEnv.settle(tester, rounds: 4);
    expect(find.textContaining('plants linked to school records'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await TestEnv.drain(tester);
  });

  test('password normalisation accepts plain text and hex digests', () {
    expect(DeyeCredentials.normalisePassword('123456'), '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92');
    const hash = '37492F579FA30EF0D3AFD14F54FA3644F98AFD7BF79B85C4D4A99CF03D66705F';
    expect(DeyeCredentials.normalisePassword(hash), hash.toLowerCase());
  });
}
