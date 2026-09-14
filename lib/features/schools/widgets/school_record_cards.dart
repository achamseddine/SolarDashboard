import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/models/fleet_insights.dart';
import '../../../core/models/school.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import '../../programme/widgets/programme_common.dart';

/// Cards of the single-school record page. Each one is independent: it shows
/// what its source holds for this school and says so when the source is
/// silent, so a thin record never looks like a broken screen.

String _dash(String? v) => v == null || v.trim().isEmpty ? '–' : v.trim();
String _yesNo(bool? v) => v == null ? '–' : (v ? 'Yes' : 'No');
String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Colour of an education risk level (same scale as the programme page).
Color riskColor(RiskLevel r) => switch (r) {
      RiskLevel.low => AppColors.good,
      RiskLevel.medium => AppColors.warning,
      RiskLevel.high => AppColors.critical,
    };

/// Small coloured pill used for the status line under the page title.
class RecordChip extends StatelessWidget {
  const RecordChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 14, color: color)
          else
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The six key figures of the school, in the order a field visit asks for them.
class SchoolRecordKpis extends StatelessWidget {
  const SchoolRecordKpis({super.key, required this.record, required this.yieldPerKwp});

  final SchoolRecord record;
  final double yieldPerKwp;

  @override
  Widget build(BuildContext context) {
    final s = record.school;
    final i = record.insight;
    final loads = s.loads;
    final kwp = s.solar?.kwp;
    final cloudKwp = record.station?.kwp;
    final expected = i?.expectedAnnualGenKwh ?? (kwp == null ? null : kwp * yieldPerKwp);
    final load = s.annualLoadKwh;
    final sizing = i?.sizingRatio ?? (expected != null && load != null && load > 0 ? expected / load : null);
    final education = s.education;

    final shifts = <String>[
      if (s.studentsAm != null) 'AM ${Fmt.int_(s.studentsAm)}',
      if (s.studentsPm != null) 'PM ${Fmt.int_(s.studentsPm)}',
    ];
    String? split;
    if (loads != null && !loads.isEmpty) {
      split = [for (final c in loads.categories) '${c.$1} ${Fmt.ratio(c.$2 / loads.totalKwh)}'].join(' · ');
    }

    return TileGrid(
      minTileWidth: 200,
      tileHeight: 110,
      children: [
        KpiTile(
          label: 'Students',
          value: Fmt.int_(s.students),
          hint: shifts.isEmpty ? 'no shift breakdown' : shifts.join(' · '),
          icon: Icons.groups_outlined,
          color: AppColors.unicefCyan,
        ),
        KpiTile(
          label: 'Capacity',
          value: s.capacity == null ? '–' : Fmt.int_(s.capacity),
          hint: s.capacity == null ? 'not recorded' : 'places in the MEHE master list',
          icon: Icons.meeting_room_outlined,
          color: AppColors.unicefDark,
        ),
        KpiTile(
          label: 'Installed kWp',
          value: Fmt.capacity(kwp),
          hint: cloudKwp == null ? (kwp == null ? 'not in the solar tracker' : 'solar tracker') : 'cloud ${Fmt.capacity(cloudKwp)}',
          icon: Icons.solar_power_outlined,
          color: AppColors.pv,
        ),
        KpiTile(
          label: 'Audited load',
          value: load == null ? '–' : '${Fmt.energy(load)}/yr',
          hint: split ?? 'no energy audit',
          icon: Icons.bolt_outlined,
          color: AppColors.load,
        ),
        KpiTile(
          label: 'Expected generation',
          value: expected == null ? '–' : '${Fmt.energy(expected)}/yr',
          hint: sizing == null ? '${Fmt.int_(yieldPerKwp)} kWh/kWp/yr' : 'coverage ${Fmt.ratio(sizing)} of the audit',
          icon: Icons.wb_sunny_outlined,
          color: AppColors.good,
        ),
        KpiTile(
          label: 'Attendance AM',
          value: Fmt.ratio(education?.amAttendance),
          hint: education?.pmAttendance == null ? 'MEHE education dashboard' : 'PM ${Fmt.ratio(education?.pmAttendance)}',
          icon: Icons.menu_book_outlined,
          color: AppColors.battery,
        ),
      ],
    );
  }
}

/// MEHE master record: identity, place, people and contact details.
class SchoolFactsCard extends StatelessWidget {
  const SchoolFactsCard({super.key, required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final s = school;
    return SectionCard(
      title: 'School record',
      subtitle: 'MEHE public school master list',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Arabic name', _dash(s.nameAr)),
          InfoRow('Ownership', _dash(s.ownership)),
          InfoRow('Cadaster', _dash(s.cadaster)),
          InfoRow('CAS code', s.casCode?.toString() ?? '–'),
          InfoRow('Address', _dash(s.address)),
          InfoRow('School phone', _dash(s.phone)),
          InfoRow('Students AM', Fmt.int_(s.studentsAm)),
          InfoRow('Students PM', Fmt.int_(s.studentsPm)),
          InfoRow('Enrolment', Fmt.int_(s.enrollment)),
          InfoRow('Capacity', s.capacity == null ? '–' : '${Fmt.int_(s.capacity)} students'),
          InfoRow('Second-shift school', s.pmCerd == null ? 'none' : 'CERD ${s.pmCerd}'),
          InfoRow(
            'Coordinates',
            s.lat == null || s.lng == null ? 'no coordinates' : '${s.lat!.toStringAsFixed(5)}, ${s.lng!.toStringAsFixed(5)}',
          ),
          MutedNote(s.inMaster
              ? 'Blank fields are blank in the master list; nothing here is inferred.'
              : 'This school is not in the MEHE master list — its record comes from a secondary workbook and is thinner.'),
        ],
      ),
    );
  }
}

ConnectivityGroup? _regionGroup(ConnectivityInsights? c, String region) {
  if (c == null) return null;
  for (final g in c.byRegion) {
    if (g.name == region) return g;
  }
  return null;
}

/// Internet connectivity: the membership answer, what it does and does not
/// say, and how the school's governorate is served.
class SchoolConnectivityCard extends ConsumerWidget {
  const SchoolConnectivityCard({super.key, required this.school, required this.isMonitored});

  final School school;
  final bool isMonitored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final region = school.region ?? 'Unassigned';
    final group = _regionGroup(ref.watch(connectivityInsightsProvider).value, region);
    final on = school.connected;
    final color = on ? AppColors.good : AppColors.muted;
    return SectionCard(
      title: 'Internet connectivity',
      subtitle: 'Internet-connectivity roll-out (534 schools)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(on ? Icons.wifi : Icons.wifi_off, size: 26, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  on ? 'On the connectivity roll-out' : 'Not on the connectivity roll-out',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The roll-out list is a membership list: a school is on it or not. It records no bandwidth, no provider and no uptime, '
            'so this page cannot say whether the line is working today.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (group != null) ...[
            const SizedBox(height: 12),
            RatioMeter(value: group.share, color: AppColors.unicefCyan, label: '$region · ${Fmt.ratio(group.share)} of schools connected'),
            const SizedBox(height: 6),
            Text('${Fmt.int_(group.connected)} of ${Fmt.int_(group.schools)} schools in $region', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (isMonitored && !on) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A plant is monitored here but the school is not on the roll-out list: the data path to DeyeCloud may be unreliable, '
                    'so gaps in the live figures can be connectivity rather than an outage.',
                    style: t.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Solar implementation tracker record, or the reason there is none.
class SchoolSolarCard extends StatelessWidget {
  const SchoolSolarCard({super.key, required this.school, required this.station, required this.yieldPerKwp});

  final School school;
  final StationInsight? station;
  final double yieldPerKwp;

  @override
  Widget build(BuildContext context) {
    final solar = school.solar;
    if (solar == null) return _NoSolar(school: school, yieldPerKwp: yieldPerKwp);
    final t = Theme.of(context).textTheme;
    final listed = solar.listedName;
    final donorGroup = solar.donorGroup;
    return SectionCard(
      title: 'Solar programme',
      subtitle: 'UNICEF solar implementation tracker',
      trailing: RecordChip(label: solar.status.label, color: solarStatusColor(solar.status)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (solar.statusRaw != null && solar.statusRaw != solar.status.label)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Tracker wording: “${solar.statusRaw}”', style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          if (listed != null && listed.trim() != school.name.trim()) InfoRow('Listed in the tracker as', listed),
          InfoRow('Donor / grant', _dash(solar.donor)),
          InfoRow('Donor group', _dash(donorGroup)),
          InfoRow('Project', _dash(solar.project)),
          InfoRow('Contractor', _dash(solar.contractor)),
          InfoRow('Consultant', _dash(solar.consultant)),
          InfoRow('System cost', usd(solar.costUsd)),
          InfoRow('LED retrofit cost', usd(solar.ledCostUsd)),
          InfoRow('Quality assurance cost', usd(solar.qaCostUsd)),
          InfoRow('PV capacity', station?.kwp == null ? Fmt.capacity(solar.kwp) : 'tracker ${Fmt.capacity(solar.kwp)} · cloud ${Fmt.capacity(station?.kwp)}'),
          InfoRow('Inverter', solar.inverterKw == null ? '–' : '${Fmt.one(solar.inverterKw)} kW'),
          InfoRow('Battery', solar.batteryKwh == null ? '–' : '${Fmt.one(solar.batteryKwh)} kWh'),
          InfoRow('Shift', _dash(solar.shift)),
          InfoRow('Language of instruction', _dash(solar.language)),
          const MutedNote('Costs are the contracted amounts recorded in the tracker, not payments made.'),
        ],
      ),
    );
  }
}

class _NoSolar extends StatelessWidget {
  const _NoSolar({required this.school, required this.yieldPerKwp});

  final School school;
  final double yieldPerKwp;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final load = school.annualLoadKwh;
    return SectionCard(
      title: 'Solar programme',
      subtitle: 'UNICEF solar implementation tracker',
      trailing: const RecordChip(label: 'No tracker record', color: AppColors.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This school is not in the solar tracker: no completed, planned, on-hold or unfunded system is recorded for CERD ${school.cerd}.', style: t.bodyMedium),
          const SizedBox(height: 8),
          InfoRow('Audited annual load', load == null ? 'not audited' : '${Fmt.energy(load)}/yr'),
          if (load != null && load > 0)
            InfoRow('Sizing reference', '≈ ${Fmt.one(load / yieldPerKwp)} kWp at ${Fmt.int_(yieldPerKwp)} kWh/kWp/yr'),
          MutedNote(load == null
              ? 'Without an energy audit there is no sizing reference for this school either.'
              : 'The audited load is the sizing reference a future system would be built against.'),
        ],
      ),
    );
  }
}

/// Energy audit: annual load by category and the equipment inventory.
class SchoolAuditCard extends StatelessWidget {
  const SchoolAuditCard({super.key, required this.school, required this.equipment});

  final School school;
  final List<SchoolEquipment> equipment;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final loads = school.loads;
    final lines = [...equipment]..sort((a, b) => b.annualKwh.compareTo(a.annualKwh));
    final audited = loads != null && !loads.isEmpty;
    if (!audited && lines.isEmpty) {
      return const SectionCard(
        title: 'Energy audit',
        subtitle: 'MEHE energy audit',
        child: MutedNote('No energy audit for this school'),
      );
    }
    return SectionCard(
      title: 'Energy audit',
      subtitle: 'Estimated annual consumption by category (MEHE energy audit)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loads != null && !loads.isEmpty) ...[
            HorizontalBars(
              items: [
                ('Lighting', loads.lightingKwh, AppColors.pv),
                ('HVAC', loads.hvacKwh, AppColors.gridImport),
                ('IT', loads.itKwh, AppColors.load),
                ('Miscellaneous', loads.miscKwh, AppColors.muted),
              ],
              formatter: Fmt.energy,
            ),
            const SizedBox(height: 8),
            InfoRow('Audited annual load', '${Fmt.energy(loads.totalKwh)}/yr'),
          ] else
            const MutedNote('No annual load estimate for this school'),
          if (lines.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('Equipment inventory (${lines.length} lines)', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${Fmt.energy(lines.fold<double>(0, (a, e) => a + e.annualKwh))}/yr · ${Fmt.one(lines.fold<double>(0, (a, e) => a + e.connectedKw))} kW connected',
                style: t.bodySmall,
              ),
              children: [
                ChartTable(
                  columns: const ['Equipment', 'Category', 'W', 'Items', 'h/day', 'kWh/yr'],
                  rows: [
                    for (final e in lines)
                      [_capitalise(e.type), e.category, Fmt.int_(e.watts), Fmt.int_(e.count), Fmt.one(e.hoursPerDay), Fmt.int_(e.annualKwh)],
                  ],
                ),
              ],
            ),
          const MutedNote('Audited figures are estimates from the inventory (rated power × count × hours), not metered consumption.'),
        ],
      ),
    );
  }
}

/// Live figures of the DeyeCloud plant linked to this school.
class SchoolPlantCard extends StatelessWidget {
  const SchoolPlantCard({super.key, required this.station, required this.link, required this.isSolarized});

  final StationInsight? station;
  final StationSchoolLink? link;
  final bool isSolarized;

  @override
  Widget build(BuildContext context) {
    final s = station;
    if (s == null) {
      return SectionCard(
        title: 'Live plant',
        subtitle: 'DeyeCloud monitoring',
        trailing: const RecordChip(label: 'Not monitored', color: AppColors.muted),
        child: MutedNote(isSolarized
            ? 'This school has a completed solar system but no plant in the DeyeCloud account, so nothing is monitored here — only the tracker and audit figures above.'
            : 'No plant in the DeyeCloud account is linked to this school.'),
      );
    }
    final snap = s.snapshot;
    final l = link;
    return SectionCard(
      title: 'Live plant',
      subtitle: s.name,
      trailing: StatusChip(s.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('PV now', Fmt.power(snap?.generationW)),
          InfoRow('Load now', Fmt.power(snap?.consumptionW)),
          InfoRow('Battery SOC', Fmt.percent(s.socNow)),
          InfoRow('Generation today', Fmt.energy(s.todayGenKwh)),
          InfoRow('7-day yield', s.yield7d == null ? '–' : '${Fmt.two(s.yield7d)} kWh/kWp/d'),
          InfoRow('Availability (7 d)', Fmt.ratio(s.availability7d, decimals: 1)),
          InfoRow('Active alarms', Fmt.int_(s.activeAlerts), valueColor: s.activeAlerts > 0 ? AppColors.critical : null),
          InfoRow('Last data', Fmt.ago(s.latest?.dataTs)),
          InfoRow('Plant ↔ school link', l == null ? '–' : '${l.method.label} · ${Fmt.ratio(l.confidence)} confidence'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => goTo(context, stationRoute(s.id)),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open the plant page'),
            ),
          ),
          const MutedNote('Live figures come from the DeyeCloud plant linked to this school and are as fresh as the last sync.'),
        ],
      ),
    );
  }
}

/// Attendance, risk levels and teaching staff from the education dashboard.
class SchoolEducationCard extends StatelessWidget {
  const SchoolEducationCard({super.key, required this.education});

  final SchoolEducation education;

  @override
  Widget build(BuildContext context) {
    final e = education;
    final teachers = <String>[
      if (e.pmFemaleTeachers != null) '${Fmt.int_(e.pmFemaleTeachers)} female',
      if (e.pmMaleTeachers != null) '${Fmt.int_(e.pmMaleTeachers)} male',
    ];
    final risks = <(String, RiskLevel?)>[('Students AM', e.amRisk), ('Students PM', e.pmRisk), ('PM teachers', e.pmTeacherRisk)];
    return SectionCard(
      title: 'Education indicators',
      subtitle: 'MEHE education dashboard${e.shift == null ? '' : ' · ${e.shift} shift'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (e.amAttendance != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RatioMeter(value: e.amAttendance!, color: AppColors.load, label: 'Morning shift attendance ${Fmt.ratio(e.amAttendance)}'),
            ),
          if (e.pmAttendance != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RatioMeter(value: e.pmAttendance!, color: AppColors.gridExport, label: 'Afternoon shift attendance ${Fmt.ratio(e.pmAttendance)}'),
            ),
          if (e.amAttendance == null && e.pmAttendance == null) const InfoRow('Attendance', 'not reported'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final r in risks)
                RecordChip(label: '${r.$1}: ${r.$2?.label ?? 'not assessed'}', color: r.$2 == null ? AppColors.muted : riskColor(r.$2!)),
            ],
          ),
          const SizedBox(height: 4),
          InfoRow('PM teachers', e.pmTeachers == null ? '–' : '${Fmt.int_(e.pmTeachers)}${teachers.isEmpty ? '' : ' (${teachers.join(' · ')})'}'),
          InfoRow('Student / teacher ratio', Fmt.one(e.studentTeacherRatio)),
          InfoRow('Teaching days', Fmt.int_(e.teachingDays)),
          InfoRow('Visited by a third party', _yesNo(e.visitedThirdParty)),
          InfoRow('Visited by the BDO', _yesNo(e.visitedByBdo)),
          if (e.monthlyStudentRisk.isNotEmpty) _MonthlyRisks(title: 'Monthly student risk', risks: e.monthlyStudentRisk),
          if (e.monthlyTeacherRisk.isNotEmpty) _MonthlyRisks(title: 'Monthly teacher risk', risks: e.monthlyTeacherRisk),
          MutedNote('Attendance is the share of enrolled students present (AM = morning shift, PM = afternoon shift). '
              'Risk levels are the dashboard\'s own classification${e.amAbsence10Rate == null ? '' : ' · AM absence over 10 % for ${Fmt.ratio(e.amAbsence10Rate)} of students'}.'),
        ],
      ),
    );
  }
}

class _MonthlyRisks extends StatelessWidget {
  const _MonthlyRisks({required this.title, required this.risks});

  final String title;
  final Map<String, RiskLevel> risks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final entries = risks.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final m in entries) RecordChip(label: '${m.key}: ${m.value.label}', color: riskColor(m.value)),
            ],
          ),
        ],
      ),
    );
  }
}
