import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unicef_solar_monitor/core/insights/education_insights_builder.dart';
import 'package:unicef_solar_monitor/core/models/school.dart';
import 'package:unicef_solar_monitor/features/education/education_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  test('education insights aggregate the MEHE extract', () async {
    final env = await TestEnv.create(sync: false);
    final d = await EducationInsightsBuilder(env.db).build();

    expect(d.schools, 1211);
    expect(d.secondShiftSchools, 312);
    expect(d.amSchools, 1211);
    expect(d.amAttendance, closeTo(0.924, 0.005));
    expect(d.amAttendanceWeighted, isNotNull);
    expect(d.pmSchools, 313);
    expect(d.pmAttendance, closeTo(0.634, 0.005));
    expect(d.teacherSchools, 312);
    expect(d.teachers, 7809);
    expect(d.femaleTeachers, 6635);
    expect(d.maleTeachers, 1174);
    expect(d.femaleShare, closeTo(0.85, 0.02));
    expect(d.studentTeacherRatio, closeTo(12.26, 0.05));
    expect(d.teachingDays, closeTo(137.1, 0.5));
    expect(d.visitedThirdParty, 221);
    expect(d.teacherTerms.length, 4);
    expect(d.teacherTerms.every((t) => t > 7000), isTrue);
    expect(d.termReportingShare, closeTo(0.996, 0.01));
    expect(d.teacherRisk[RiskLevel.low], 172);
    expect(d.highRiskTeachers, 36);
    expect(d.studentRiskPm[RiskLevel.high], 22);
    expect(d.hasAbsenceRates, isFalse, reason: 'the bundled extract leaves the 10+ absence columns empty');
    expect(d.byRegion.fold(0, (a, r) => a + r.schools), d.schools);
    expect(d.byRegion.first.name, isNotEmpty);
    await env.dispose();
  });

  testWidgets('education screen shows student and teacher indicators', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await TestEnv.createFor(tester, schools: 10);
    addTearDown(() => tester.runAsync(env.dispose));

    await tester.pumpWidget(env.wrap(const EducationScreen()));
    await TestEnv.settle(tester, rounds: 4);

    expect(find.text('Students and teachers'), findsOneWidget);
    expect(find.text('Morning attendance'), findsOneWidget);
    expect(find.text('Afternoon attendance'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView).first;
    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      for (final label in ['Afternoon-shift teachers', 'Students per teacher', 'Teaching days', 'By governorate', 'Teacher risk rating']) {
        if (find.textContaining(label).evaluate().isNotEmpty) seen.add(label);
      }
      await tester.drag(list, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'layout exception after scroll $i');
    }
    expect(seen, containsAll(['Afternoon-shift teachers', 'Students per teacher', 'By governorate']));
    await TestEnv.drain(tester);
  });
}
