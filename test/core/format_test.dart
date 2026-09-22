import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/utils/format.dart';

void main() {
  group('Fmt.label', () {
    test('turns cloud enum codes into words', () {
      expect(Fmt.label('BATTERY_BACKUP'), 'Battery backup');
      expect(Fmt.label('grid-tied'), 'Grid tied');
      expect(Fmt.label('SELF_CONSUMPTION'), 'Self consumption');
    });

    test('leaves prose alone and copes with nothing', () {
      expect(Fmt.label('Battery backup'), 'Battery backup');
      expect(Fmt.label(null), '–');
      expect(Fmt.label('  '), '–');
      expect(Fmt.label('___'), '–');
    });
  });
}
