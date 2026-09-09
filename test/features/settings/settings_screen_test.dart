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
    expect(find.text('Synchronisation'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(0, -800));
    await tester.pump(const Duration(milliseconds: 300));
    final dark = find.widgetWithText(SwitchListTile, 'Dark mode');
    expect(dark, findsOneWidget);
    await tester.tap(dark);
    await TestEnv.settle(tester, rounds: 1);
    expect(env.prefs.getBool('settings.darkMode'), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('password normalisation accepts plain text and hex digests', () {
    expect(DeyeCredentials.normalisePassword('123456'), '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92');
    const hash = '37492F579FA30EF0D3AFD14F54FA3644F98AFD7BF79B85C4D4A99CF03D66705F';
    expect(DeyeCredentials.normalisePassword(hash), hash.toLowerCase());
  });
}
