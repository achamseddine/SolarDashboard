import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/school.dart';

import 'package:unicef_solar_monitor/core/demo/demo_gwn_api.dart';
import 'helpers/test_env.dart';

void main() {
  test('probe', () async {
    final env = await TestEnv.create(schools: 10, networks: 180);
    addTearDown(env.dispose);
    final nets = await env.db.networks.getNetworks();
    print('networks=${nets.length} linked=${nets.where((n) => n.cerd != null).length}');
    print('names: ${nets.take(5).map((n) => n.name).toList()}');
    final seeds = TestEnv.dataset.demoSeeds;
    print('seeds=${seeds.length}');
    final api = DemoGwnApi(seeds: seeds, networks: 180);
    final list = await api.listNetworks();
    final names = list.map((n) => n.name).toList();
    print('unique demo names=${names.toSet().length} of ${names.length}');
    print(School);
  });
}
