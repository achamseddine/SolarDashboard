import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/api/json_utils.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';

void main() {
  group('findInt', () {
    test('matches a key by meaning, whatever it is called', () {
      // The same count under the several names this API family uses.
      for (final key in ['clientCount', 'client_num', 'staCount', 'onlineClientNum', 'userTotal']) {
        expect(findInt({key: 7}, ['client', 'sta', 'user']), 7, reason: key);
      }
    });

    test('sees a counter nested one level down', () {
      expect(findInt({'stat': {'clientNum': 12}}, ['client']), 12);
      expect(flattenOnce({'stat': {'a': 1}}).containsKey('stat.a'), isTrue);
    });

    test('honours exclusions, so a cap is not read as a count', () {
      final m = {'maxClient': 200, 'clientNum': 9};
      expect(findInt(m, ['client'], not: ['max']), 9);
    });

    test('returns null rather than guessing when nothing matches', () {
      expect(findInt({'name': 'A School', 'id': 'n1'}, ['client']), isNull);
      // A non-numeric value under a matching key is not a count.
      expect(findInt({'clientList': 'none'}, ['client']), isNull);
    });
  });

  test('a device row carries its client count under an unfamiliar name', () {
    final d = GwnDevice.fromJson(const {
      'mac': 'AA:BB',
      'name': 'AP 1',
      'type': 'AP',
      'status': 'online',
      // Not one of the names the exact-match list knows.
      'terminalTotal': 5,
    }, networkId: 'n1');

    expect(d.clientCount, 5);
    expect(d.kind, GwnDeviceKind.accessPoint);
    expect(d.isOnline, isTrue);
  });
}
