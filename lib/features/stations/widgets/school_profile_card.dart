import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/school.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'school_link_dialog.dart';

/// MEHE school record linked to one plant: master data, solar programme
/// tracker, energy audit and education dashboard, plus the manual link
/// picker.
///
/// The profile chain (link → school → programme insights → fleet insights)
/// is the heaviest query set of the detail page and re-runs on every fleet
/// change, so the detail screen sets [paused] while it refreshes the plant:
/// the card then keeps showing the last profile instead of competing with
/// the refresh's writes and the reload that follows them.
class SchoolProfileCard extends ConsumerStatefulWidget {
  const SchoolProfileCard({super.key, required this.stationId, this.paused = false});
  final int stationId;

  /// While true the provider is not watched; the last loaded profile stays visible.
  final bool paused;

  @override
  ConsumerState<SchoolProfileCard> createState() => _SchoolProfileCardState();
}

class _SchoolProfileCardState extends ConsumerState<SchoolProfileCard> {
  AsyncValue<SchoolProfile?>? _last;

  @override
  void didUpdateWidget(covariant SchoolProfileCard old) {
    super.didUpdateWidget(old);
    if (old.stationId != widget.stationId) _last = null;
  }

  @override
  Widget build(BuildContext context) {
    final yieldPerKwp = ref.watch(settingsProvider.select((s) => s.specificYieldKwhPerKwp));
    AsyncValue<SchoolProfile?> profile;
    if (widget.paused) {
      profile = _last ?? const AsyncValue.loading();
    } else {
      profile = ref.watch(schoolProfileProvider(widget.stationId));
      if (!profile.isLoading) _last = profile;
    }
    return AsyncView<SchoolProfile?>(
      value: profile,
      builder: (p) => p == null ? _NotLinked(stationId: widget.stationId) : _Profile(stationId: widget.stationId, profile: p, yieldPerKwp: yieldPerKwp),
    );
  }
}

const _sourceNote = 'Source: MEHE public school list, UNICEF solar tracker, energy audit, MEHE education dashboard. Plant ↔ school links are automatic (name + coordinates) unless set by hand.';

class _NotLinked extends StatelessWidget {
  const _NotLinked({required this.stationId});
  final int stationId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'School record',
      subtitle: 'MEHE master data, solar tracker, energy audit and education dashboard',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This plant is not linked to a MEHE school record.', style: t.bodyMedium),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => SchoolLinkDialog.show(context, stationId: stationId),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Link to a school'),
          ),
          const MutedNote(_sourceNote),
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.stationId, required this.profile, required this.yieldPerKwp});
  final int stationId;
  final SchoolProfile profile;
  final double yieldPerKwp;

  @override
  Widget build(BuildContext context) {
    final s = profile.school;
    final link = profile.link;
    final place = [s.region ?? 'Unassigned', ?s.caza].join(' · ');
    final groups = <Widget>[
      _SchoolGroup(school: s),
      if (s.solar != null) _SolarGroup(solar: s.solar!, insight: profile.insight),
      if (s.loads != null || profile.insight != null) _EnergyGroup(school: s, insight: profile.insight, equipment: profile.equipment, yieldPerKwp: yieldPerKwp),
      if (s.education != null) _EducationGroup(education: s.education!),
    ];
    return SectionCard(
      title: s.name,
      subtitle: 'CERD ${s.cerd} · $place · linked by ${link.method.label} (${Fmt.ratio(link.confidence)})',
      trailing: OutlinedButton.icon(
        onPressed: () => SchoolLinkDialog.show(context, stationId: stationId, current: link),
        icon: const Icon(Icons.link, size: 18),
        label: const Text('Change link'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groups.length; i += 2) ...[
            if (i > 0) const SizedBox(height: kGap),
            TwoColumn(left: groups[i], right: i + 1 < groups.length ? groups[i + 1] : const SizedBox.shrink()),
          ],
          const MutedNote(_sourceNote),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ groups

/// Titled block of [InfoRow]s.
class _FactGroup extends StatelessWidget {
  const _FactGroup({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
        const Divider(height: 12),
        ...children,
      ],
    );
  }
}

/// Label on the left, an arbitrary widget (chip, meter) on the right.
class _WidgetRow extends StatelessWidget {
  const _WidgetRow(this.label, {required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}

/// Coloured dot + label pill (same look as the status chips).
class _Tag extends StatelessWidget {
  const _Tag({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

Color solarStatusColor(SolarStatus s) {
  switch (s) {
    case SolarStatus.completed:
      return AppColors.good;
    case SolarStatus.planned:
      return AppColors.load;
    case SolarStatus.onHold:
      return AppColors.warning;
    case SolarStatus.unfunded:
      return AppColors.serious;
    case SolarStatus.notSolarized:
      return AppColors.muted;
  }
}

Color _riskColor(RiskLevel r) {
  switch (r) {
    case RiskLevel.low:
      return AppColors.good;
    case RiskLevel.medium:
      return AppColors.warning;
    case RiskLevel.high:
      return AppColors.critical;
  }
}

String _dash(String? v) => v == null || v.trim().isEmpty ? '–' : v;
String _usd(double? v) => v == null ? '–' : 'USD ${Fmt.int_(v)}';
String _yesNo(bool? v) => v == null ? '–' : (v ? 'Yes' : 'No');

class _SchoolGroup extends StatelessWidget {
  const _SchoolGroup({required this.school});
  final School school;

  @override
  Widget build(BuildContext context) {
    final s = school;
    final students = <String>[
      if (s.studentsAm != null) 'AM ${Fmt.int_(s.studentsAm)}',
      if (s.studentsPm != null) 'PM ${Fmt.int_(s.studentsPm)}',
      if (s.enrollment != null) 'enrolment ${Fmt.int_(s.enrollment)}',
    ];
    return _FactGroup(
      title: 'School',
      icon: Icons.school_outlined,
      children: [
        InfoRow('Arabic name', _dash(s.nameAr)),
        InfoRow('Ownership', _dash(s.ownership)),
        InfoRow('Capacity', s.capacity == null ? '–' : '${Fmt.int_(s.capacity)} students'),
        InfoRow('Students', students.isEmpty ? '–' : students.join(' · ')),
        InfoRow('Second-shift school', s.pmCerd == null ? '–' : 'CERD ${s.pmCerd}'),
        InfoRow('Address', _dash(s.address)),
        InfoRow('School phone', _dash(s.phone)),
        _WidgetRow(
          'Internet connectivity',
          child: s.connected ? const _Tag(color: AppColors.good, label: 'Connected') : const _Tag(color: AppColors.muted, label: 'Not in connectivity roll-out'),
        ),
      ],
    );
  }
}

class _SolarGroup extends StatelessWidget {
  const _SolarGroup({required this.solar, required this.insight});
  final SchoolSolar solar;
  final SchoolInsight? insight;

  @override
  Widget build(BuildContext context) {
    final so = solar;
    final plant = insight?.station;
    final cloudKwp = plant?.kwp;
    final cloudBattery = plant?.station.batteryCapacityKwh;
    final donor = so.donor == null && so.donorGroup == null
        ? '–'
        : so.donorGroup == null || so.donorGroup == so.donor
            ? _dash(so.donor)
            : '${_dash(so.donor)} (${so.donorGroup})';
    return _FactGroup(
      title: 'Solar programme',
      icon: Icons.solar_power_outlined,
      children: [
        _WidgetRow('Status', child: _Tag(color: solarStatusColor(so.status), label: so.status.label)),
        InfoRow('Donor / grant', donor),
        InfoRow('Project', _dash(so.project)),
        InfoRow('Contractor', _dash(so.contractor)),
        InfoRow('Consultant', _dash(so.consultant)),
        InfoRow('System cost', _usd(so.costUsd)),
        InfoRow('LED retrofit cost', _usd(so.ledCostUsd)),
        InfoRow('QA cost', _usd(so.qaCostUsd)),
        InfoRow('PV capacity', 'tracker ${Fmt.capacity(so.kwp)} · cloud ${Fmt.capacity(cloudKwp)}'),
        InfoRow('Inverter', so.inverterKw == null ? '–' : '${Fmt.one(so.inverterKw)} kW'),
        InfoRow('Battery', 'tracker ${Fmt.energy(so.batteryKwh)} · cloud ${Fmt.energy(cloudBattery)}'),
        InfoRow('Shift', _dash(so.shift)),
        InfoRow('Language of instruction', _dash(so.language)),
      ],
    );
  }
}

class _EnergyGroup extends StatelessWidget {
  const _EnergyGroup({required this.school, required this.insight, required this.equipment, required this.yieldPerKwp});
  final School school;
  final SchoolInsight? insight;
  final List<SchoolEquipment> equipment;
  final double yieldPerKwp;

  @override
  Widget build(BuildContext context) {
    final loads = school.loads;
    final i = insight;
    final kwp = i?.kwp ?? school.solar?.kwp;
    final expected = i?.expectedAnnualGenKwh ?? (kwp == null ? null : kwp * yieldPerKwp);
    final sizing = i?.sizingRatio ?? (expected != null && loads != null && !loads.isEmpty ? expected / loads.totalKwh : null);
    final sorted = [...equipment]..sort((a, b) => b.annualKwh.compareTo(a.annualKwh));
    final hasMeasured = i != null && (i.measuredGenKwh30d != null || i.measuredConsKwh30d != null);
    return _FactGroup(
      title: 'Energy',
      icon: Icons.bolt_outlined,
      children: [
        if (loads != null && !loads.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('Audited annual load by category', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          HorizontalBars(
            items: [
              ('Lighting', loads.lightingKwh, AppColors.pv),
              ('HVAC', loads.hvacKwh, AppColors.gridImport),
              ('IT', loads.itKwh, AppColors.load),
              ('Miscellaneous', loads.miscKwh, AppColors.muted),
            ],
            formatter: Fmt.energy,
            barHeight: 12,
          ),
          InfoRow('Audited annual load', '${Fmt.energy(loads.totalKwh)}/yr'),
        ] else
          const InfoRow('Audited annual load', 'not audited'),
        InfoRow('Expected generation', expected == null ? '–' : '${Fmt.energy(expected)}/yr'),
        if (sizing != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RatioMeter(
              value: sizing,
              label: 'Sizing ratio ${Fmt.ratio(sizing)} — expected generation ÷ audited load',
              color: sizing < 0.6 ? AppColors.serious : (sizing < 0.9 ? AppColors.warning : AppColors.good),
            ),
          ),
        if (hasMeasured) ...[
          InfoRow('Generation last 30 d', Fmt.energy(i.measuredGenKwh30d)),
          InfoRow('Consumption last 30 d', Fmt.energy(i.measuredConsKwh30d)),
          InfoRow('Measured coverage', i.measuredCoverage == null ? '–' : '${Fmt.ratio(i.measuredCoverage)} of audited load'),
          InfoRow('Audit accuracy', i.auditAccuracy == null ? '–' : '${Fmt.ratio(i.auditAccuracy)} of audit (measured ÷ audited)'),
          MutedNote('Measured over ${i.measuredDays30d} day${i.measuredDays30d == 1 ? '' : 's'} with data; expected generation = kWp × ${Fmt.int_(yieldPerKwp)} kWh/kWp/yr (Settings).'),
        ] else
          MutedNote('Expected generation = kWp × ${Fmt.int_(yieldPerKwp)} kWh/kWp/yr (Settings).'),
        if (sorted.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('Equipment inventory · ${sorted.length} lines', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('${Fmt.energy(sorted.fold<double>(0, (a, e) => a + e.annualKwh))}/yr · ${Fmt.one(sorted.fold<double>(0, (a, e) => a + e.connectedKw))} kW connected', style: Theme.of(context).textTheme.bodySmall),
            children: [
              ChartTable(
                columns: const ['Type', 'Category', 'Watts', 'Count', 'h/day', 'kWh/yr'],
                rows: [for (final e in sorted) [e.type, e.category, Fmt.int_(e.watts), Fmt.int_(e.count), Fmt.one(e.hoursPerDay), Fmt.int_(e.annualKwh)]],
              ),
            ],
          ),
      ],
    );
  }
}

class _EducationGroup extends StatelessWidget {
  const _EducationGroup({required this.education});
  final SchoolEducation education;

  @override
  Widget build(BuildContext context) {
    final e = education;
    final risks = <(String, RiskLevel?)>[('Students AM', e.amRisk), ('Students PM', e.pmRisk), ('PM teachers', e.pmTeacherRisk)];
    return _FactGroup(
      title: 'Education',
      icon: Icons.menu_book_outlined,
      children: [
        if (e.amAttendance != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RatioMeter(value: e.amAttendance!, label: 'Morning shift attendance ${Fmt.ratio(e.amAttendance)}', color: AppColors.load),
          ),
        if (e.pmAttendance != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RatioMeter(value: e.pmAttendance!, label: 'Afternoon shift attendance ${Fmt.ratio(e.pmAttendance)}', color: AppColors.gridExport),
          ),
        if (e.amAttendance == null && e.pmAttendance == null) const InfoRow('Attendance', 'not reported'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final r in risks) _Tag(color: r.$2 == null ? AppColors.muted : _riskColor(r.$2!), label: '${r.$1}: ${r.$2?.label ?? 'not assessed'}'),
            ],
          ),
        ),
        InfoRow('PM teachers', e.pmTeachers == null ? '–' : Fmt.int_(e.pmTeachers)),
        InfoRow('Student / teacher ratio', e.studentTeacherRatio == null ? '–' : Fmt.one(e.studentTeacherRatio)),
        InfoRow('Teaching days', e.teachingDays == null ? '–' : Fmt.int_(e.teachingDays)),
        InfoRow('Visited by third party', _yesNo(e.visitedThirdParty)),
      ],
    );
  }
}
