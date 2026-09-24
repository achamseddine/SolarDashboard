import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/models/gwn.dart';
import 'package:unicef_solar_monitor/core/schools/network_school_linker.dart';

import '../helpers/test_env.dart';

void main() {
  test('a network named "<CERD>- <arabic name>" links to that school exactly', () {
    final schools = TestEnv.dataset.schools;
    final linker = NetworkSchoolLinker(schools);

    // The names the GWN account actually carries, CERD prefix and all.
    const names = {
      1000: '1000- متوسطة الصويري الرسمية',
      1001: '1001- متوسطة مشغرة الأولى الرسمية المختلطة',
      1003: '1003- ثانوية مشغرة الرسمية',
      1008: '1008- متوسطة القرعون الرسمية',
      1019: '1019- الرفيد المتوسطة الرسمية',
    };

    for (final e in names.entries) {
      final m = linker.match(GwnNetwork(id: 'n${e.key}', name: e.value));
      expect(m, isNotNull, reason: 'no match for ${e.value}');
      expect(m!.school.cerd, e.key, reason: 'wrong school for ${e.value}');
      expect(m.confidence, 1.0);
    }
  });

  test('the prefix is read only when it names a school in the dataset', () {
    final linker = NetworkSchoolLinker(TestEnv.dataset.schools);

    // A number that is not a CERD falls through to name matching rather than
    // linking to something arbitrary.
    final bogus = linker.match(const GwnNetwork(id: 'x', name: '999999- لا يوجد'));
    expect(bogus, isNull);

    expect(NetworkSchoolLinker.cerdFromName('1000- متوسطة الصويري الرسمية'), 1000);
    expect(NetworkSchoolLinker.cerdFromName('متوسطة الصويري الرسمية'), isNull);
    expect(NetworkSchoolLinker.cerdFromName('Beirut School'), isNull);
    // CERDs start at 1, so a single digit is a real prefix.
    expect(NetworkSchoolLinker.cerdFromName('7- سلمى الصايغ الرسمية المختلطة'), 7);
  });

  test('the whole account links when every network carries its CERD', () {
    final schools = TestEnv.dataset.schools;
    final linker = NetworkSchoolLinker(schools);
    // Stand in for the 560-network account: name each after its own school.
    final sample = schools.take(200).toList();
    var linked = 0;
    for (final s in sample) {
      final m = linker.match(GwnNetwork(id: 'n${s.cerd}', name: '${s.cerd}- ${s.nameAr ?? s.name}'));
      if (m != null && m.school.cerd == s.cerd) linked++;
    }
    expect(linked, sample.length, reason: 'every network with a CERD prefix should link');
  });

  test('the prefix is read however the account punctuates it', () {
    final linker = NetworkSchoolLinker(TestEnv.dataset.schools);

    // Exactly the spellings the live account uses: a separator, a building
    // letter, a letter and digit, or nothing but a space.
    const names = {
      '1000- متوسطة الصويري الرسمية': 1000,
      '388A-مدرسة النور الرسمية المختلطة': 388,
      '1080 Bجوزيف حرب المختلطة': 1080,
      '1242 B1-ثانوية دير كيفا الرسمية': 1242,
      '1242 B2 - ثانوية دير كيفا الرسمية': 1242,
      '441 مدرسة البداوي الرسمية للبنات': 441,
      '1356b-متوسطة حوشقيصر الرسمية': 1356,
    };

    for (final e in names.entries) {
      expect(NetworkSchoolLinker.cerdFromName(e.key), e.value, reason: e.key);
      final m = linker.match(GwnNetwork(id: 'x', name: e.key));
      expect(m?.school.cerd, e.value, reason: 'no link for ${e.key}');
    }

    // Two buildings of one school both link to it — that is correct, not a
    // duplicate to guard against.
    expect(
      linker.match(const GwnNetwork(id: 'a', name: '1242 B1-x'))?.school.cerd,
      linker.match(const GwnNetwork(id: 'b', name: '1242 B2-x'))?.school.cerd,
    );

    // A name with no leading number is still only matched on its words.
    expect(NetworkSchoolLinker.cerdFromName('Barqayel Mixed Public School'), isNull);
  });
}