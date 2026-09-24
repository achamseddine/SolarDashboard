import 'package:flutter/material.dart';

import '../../../core/models/gwn.dart';
import '../../../core/models/network_filter.dart';
import '../../../core/models/network_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'network_detail_sheet.dart';

/// Carries a slice to the Schools tab, where it can be sorted and searched.
typedef OpenSchoolList = void Function(NetworkSchoolFilter filter);

/// Section 1 — the executive headline indicators.
///
/// Every tile is a count over the same school list, so every tile opens it:
/// tapping one shows what the figure means and the schools behind it,
/// selected by the very predicate that produced the number.
class NetworkHeadlineKpis extends StatelessWidget {
  const NetworkHeadlineKpis({super.key, required this.insights, this.onOpenList});

  final NetworkInsights insights;
  final OpenSchoolList? onOpenList;

  /// Open critical alarms that belong to a network in the account.
  static int _attributable(NetworkInsights d) => d.schools.fold<int>(0, (a, s) => a + s.openCriticalAlarms);

  /// One headline tile and the panel it opens.
  Widget _tile(
    BuildContext context, {
    required NetworkSchoolFilter filter,
    required String label,
    required String value,
    String? hint,
    IconData? icon,
    Color? color,
    String? note,
    List<DrillFact> facts = const [],
  }) =>
      KpiTile(
        label: label,
        value: value,
        hint: hint,
        icon: icon,
        color: color,
        onTap: () => showNetworkDrill(
          context,
          drillFor(insights, filter, title: label, value: value, note: note, facts: facts),
          onOpenList: onOpenList,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final t = d.thresholds;
    return TileGrid(
      // Wide enough for the longest headline label ("Meaningfully
      // connected") without the tile clipping it.
      minTileWidth: 240,
      children: [
        _tile(
          context,
          filter: NetworkSchoolFilter.connected,
          label: 'Schools connected',
          value: Fmt.int_(d.connected),
          hint: 'seen online at least once · of ${Fmt.int_(d.publicSchools)} public schools',
          icon: Icons.wifi,
          color: AppColors.unicefCyan,
          facts: [
            DrillFact('Share of public schools', Fmt.ratio(d.connectedShare)),
            DrillFact('Public schools in the master list', Fmt.int_(d.publicSchools)),
          ],
          note: d.unlinkedNetworks == 0
              ? null
              : 'The count includes ${Fmt.int_(d.unlinkedNetworks)} networks whose name carries no CERD the app could match, '
                  'while the denominator counts public schools only — so the share reads high until they are matched.',
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.lanOperational,
          label: 'LAN operational',
          value: Fmt.int_(d.lanOperational),
          hint: 'gateway up and APs available',
          icon: Icons.lan_outlined,
          color: AppColors.good,
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.meaningfullyConnected,
          label: 'Meaningfully connected',
          value: Fmt.int_(d.meaningfullyConnected),
          hint: 'uptime ≥ ${Fmt.ratio(t.uptimeTarget)} over a day of checks · speed and quality not measured',
          icon: Icons.speed,
          facts: [
            DrillFact('Uptime target', Fmt.ratio(t.uptimeTarget)),
            DrillFact('Access points that must be up', Fmt.ratio(t.apAvailabilityTarget)),
          ],
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.activelyUsing,
          label: 'Actively using technology',
          value: Fmt.int_(d.activelyUsing),
          hint: 'activity on ≥ ${Fmt.ratio(t.activeUseShare)} of school days',
          icon: Icons.devices,
          color: AppColors.unicefDark,
          facts: [
            DrillFact('A day counts as active at', '${Fmt.int_(t.activeDayClients)} devices and ${Fmt.int_(t.activeDayMegabytes)} MB'),
            DrillFact('Share of days required', Fmt.ratio(t.activeUseShare)),
          ],
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.highAdoption,
          label: 'High digital adoption',
          value: Fmt.int_(d.highAdoption),
          hint: 'sustained use · only where use was measured',
          icon: Icons.trending_up,
          color: AppColors.good,
          facts: [DrillFact('Use score at or above', t.highAdoptionIndex.toStringAsFixed(0))],
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.lowAdoption,
          label: 'Low / no adoption',
          value: Fmt.int_(d.lowAdoption),
          hint: 'weak use despite the network · only where use was measured',
          icon: Icons.trending_down,
          color: AppColors.warning,
          facts: [DrillFact('Use score below', t.lowAdoptionIndex.toStringAsFixed(0))],
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.technicalIntervention,
          label: 'Technical intervention',
          value: Fmt.int_(d.technicalIntervention),
          hint: 'gateway or most access points down, failed ports, or open critical alarms',
          icon: Icons.build_outlined,
          color: AppColors.critical,
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.adoptionSupport,
          label: 'Adoption support',
          value: Fmt.int_(d.adoptionSupport),
          hint: 'infrastructure healthy, use still low',
          icon: Icons.school_outlined,
          color: AppColors.serious,
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.uptimeMeasured,
          label: 'Average network uptime',
          value: Fmt.ratio(d.avgUptime, decimals: 1),
          hint: d.avgUptime == null
              ? 'needs several checks in a day before a share means anything'
              : 'across the schools checked often enough to tell',
          icon: Icons.timeline,
          facts: [
            DrillFact('Mean uptime', Fmt.ratio(d.avgUptime, decimals: 1)),
            DrillFact('Schools it is averaged over', Fmt.int_(NetworkSchoolFilter.uptimeMeasured.count(d))),
          ],
          note: 'The average is over these schools only. A school checked once carries no share and is left out '
              'rather than counted as zero.',
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.clientsMeasured,
          label: 'Active client devices',
          value: Fmt.int_(d.activeUsers),
          hint: 'mean daily unique devices · not unique people',
          icon: Icons.group_outlined,
          facts: [
            DrillFact('Devices across the portfolio', Fmt.int_(d.activeUsers)),
            DrillFact('Schools reporting a client count', Fmt.int_(NetworkSchoolFilter.clientsMeasured.count(d))),
          ],
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.openIncidents,
          label: 'Open critical incidents',
          value: Fmt.int_(d.openCriticalIncidents),
          hint: 'unresolved critical alarms',
          icon: Icons.warning_amber_outlined,
          color: d.openCriticalIncidents > 0 ? AppColors.critical : AppColors.muted,
          facts: [
            DrillFact('Open critical alarms', Fmt.int_(d.openCriticalIncidents)),
            // An alarm the account raised against no network in the list
            // cannot be placed at a school, and would otherwise be a figure
            // with nothing behind it.
            if (d.openCriticalIncidents > _attributable(d))
              DrillFact('Not attributable to a network', Fmt.int_(d.openCriticalIncidents - _attributable(d))),
            DrillFact('Schools carrying them', Fmt.int_(NetworkSchoolFilter.openIncidents.count(d)),
                opens: NetworkSchoolFilter.openIncidents.count(d) == 0 ? null : () => drillFor(d, NetworkSchoolFilter.openIncidents)),
          ],
          note: 'The headline counts alarms; the list counts schools, so a school with three alarms appears once.',
        ),
        _tile(
          context,
          filter: NetworkSchoolFilter.all,
          label: 'Networks in the account',
          value: Fmt.int_(d.networks),
          hint: d.unlinkedNetworks == 0 ? 'all matched to a school' : '${Fmt.int_(d.unlinkedNetworks)} not matched to a school',
          icon: Icons.router_outlined,
          facts: [
            DrillFact('Matched to a school', Fmt.int_(d.networks - d.unlinkedNetworks)),
            // The actionable half: a data-quality worklist for the CERD join.
            DrillFact(
              'Not matched',
              Fmt.int_(d.unlinkedNetworks),
              opens: d.unlinkedNetworks == 0 ? null : () => drillFor(d, NetworkSchoolFilter.unmatched),
            ),
          ],
          note: 'An unmatched network has no CERD number in its name that the app could read, so its governorate '
              'and enrolment are unknown. It still reports its own devices.',
        ),
      ],
    );
  }
}

/// Section 10 — the infrastructure × adoption matrix.
class AdoptionMatrixCard extends StatelessWidget {
  const AdoptionMatrixCard({super.key, required this.insights, this.onTap});

  final NetworkInsights insights;
  final void Function(AdoptionQuadrant quadrant)? onTap;

  @override
  Widget build(BuildContext context) {
    final q = insights.quadrants;
    Widget cell(AdoptionQuadrant quadrant, Color color) {
      final n = q[quadrant] ?? 0;
      return Expanded(
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(quadrant),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.int_(n), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                Text(quadrant.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(quadrant.description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return SectionCard(
      title: 'Infrastructure × adoption',
      subtitle: 'Separates schools needing maintenance or ISP action from those needing training and leadership support',
      child: Column(
        children: [
          Row(children: [
            cell(AdoptionQuadrant.constrained, AppColors.serious),
            cell(AdoptionQuadrant.active, AppColors.good),
          ]),
          Row(children: [
            cell(AdoptionQuadrant.technical, AppColors.critical),
            cell(AdoptionQuadrant.adoptionSupport, AppColors.warning),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('← infrastructure unhealthy', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text('infrastructure healthy →', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if ((q[AdoptionQuadrant.unknown] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MutedNote(
                '${Fmt.int_(q[AdoptionQuadrant.unknown])} schools cannot be placed yet: the usage axis needs a client '
                'count or traffic figure, and nothing has been measured for them so far. That is why the quadrants '
                'read zero while ${Fmt.int_(insights.technicalIntervention)} schools are already flagged for technical '
                'intervention — a fault is visible on the infrastructure axis alone, but placing a school needs both.',
              ),
            ),
        ],
      ),
    );
  }
}

/// Section 9 — the Technology Adoption Index and the weight behind it.
class AdoptionIndexCard extends StatelessWidget {
  const AdoptionIndexCard({super.key, required this.insights});

  final NetworkInsights insights;

  /// One component's mean opens the schools ranked by it.
  void _showComponent(BuildContext context, IndexComponent template, double mean) {
    final rows = insights.schools.where((s) => s.scoreOf(template.label) != null).toList()
      ..sort((a, b) => b.scoreOf(template.label)!.compareTo(a.scoreOf(template.label)!));
    showNetworkDrill(
      context,
      NetworkDrill(
        title: template.label,
        value: mean.toStringAsFixed(0),
        what: 'One of the eight weighted components of the Technology Adoption Index. It carries '
            '${Fmt.ratio(template.weight)} of the framework weight, and the figure is the mean across the schools '
            'that have a score for it — highest first.',
        rows: rows,
        metric: (s) => (value: s.scoreOf(template.label)!.toStringAsFixed(0), hint: 'of 100'),
      ),
    );
  }

  /// How much of the framework each school could actually be scored on.
  void _showCoverage(BuildContext context, List<SchoolNetwork> schools, double mean) {
    final rows = [...schools]..sort((a, b) => b.availableWeight.compareTo(a.availableWeight));
    showNetworkDrill(
      context,
      NetworkDrill(
        title: 'Weight the index could be computed on',
        value: Fmt.ratio(mean),
        what: 'A school is scored only on the components it has a source for, and the remaining weights are '
            'renormalised. This is how much of the framework each school was scored on — the schools at the bottom '
            'are the ones whose index rests on the least evidence.',
        rows: rows,
        metric: (s) => (value: Fmt.ratio(s.availableWeight), hint: 'of the weight'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schools = insights.schools.where((s) => s.index != null).toList();
    if (schools.isEmpty) {
      return const SectionCard(
        title: 'Technology Adoption Index',
        child: EmptyState(message: 'No school has enough data to be scored yet.', icon: Icons.insights_outlined),
      );
    }
    final mean = schools.map((s) => s.index!).reduce((a, b) => a + b) / schools.length;
    // Every school carries the same component labels and weights; only the
    // scores differ, so the labels can be read off any of them — the
    // coverage cannot, and is averaged.
    final template = schools.first.components;
    final coverage = schools.map((s) => s.availableWeight).reduce((a, b) => a + b) / schools.length;

    // Components some schools have and others do not.
    final partial = template
        .where((c) => schools.any((s) => s.scoreOf(c.label) == null) && schools.any((s) => s.scoreOf(c.label) != null))
        .length;

    // Mean of each component across the schools that have it.
    final rows = <(String, double, Color?)>[];
    final scored = <IndexComponent>[];
    for (final c in template) {
      final vals = schools.map((s) => s.scoreOf(c.label)).whereType<double>().toList();
      if (vals.isEmpty) continue;
      rows.add((c.label, vals.reduce((a, b) => a + b) / vals.length, null));
      scored.add(c);
    }

    return SectionCard(
      title: 'Technology Adoption Index',
      subtitle: 'Mean ${mean.toStringAsFixed(0)} / 100 across ${Fmt.int_(schools.length)} scored schools · diagnostic, not a ranking',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The framework's component names are long; give them room.
          HorizontalBars(
            items: rows,
            maxValue: 100,
            labelWidth: 210,
            formatter: (v) => v.toStringAsFixed(0),
            onTap: (i) => _showComponent(context, scored[i], rows[i].$2),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('Weight the index could be computed on', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _showCoverage(context, schools, coverage),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RatioMeter(
                value: coverage,
                label: '${Fmt.ratio(coverage)} of the framework weight, on average',
                color: AppColors.unicefCyan,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Missing for every scored school — a gap in the programme's data,
          // not in one school's. Components missing for only some schools are
          // counted separately rather than presented as everyone's gap.
          for (final c in template.where((c) => schools.every((s) => s.scoreOf(c.label) == null)))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${c.label} · ${Fmt.ratio(c.weight)} of the weight · needs ${c.missingSource}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (partial > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$partial further ${partial == 1 ? 'component is' : 'components are'} missing for some schools but not others — tap the meter to see which schools are scored on how much.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          const MutedNote(
            'Components without a source are left out and the remaining weights are renormalised, so a school is never '
            'marked down for data nobody collected. The score is shown with its components so a weak result can be read. '
            'Tap a component to see the schools ranked by it.',
          ),
        ],
      ),
    );
  }
}

/// Section 2 — infrastructure health across the portfolio.
class InfrastructureCard extends StatelessWidget {
  const InfrastructureCard({super.key, required this.insights, this.onOpenList});

  final NetworkInsights insights;
  final OpenSchoolList? onOpenList;

  /// The figure counts [things] across the account; the list counts schools.
  static String _countsThings(String things) =>
      'The figure counts $things across the account; the list counts the schools carrying them, worst first.';

  /// The device kind whose offline units a row should list.
  static const _kindFilter = {
    GwnDeviceKind.router: NetworkSchoolFilter.gatewayOffline,
    GwnDeviceKind.networkSwitch: NetworkSchoolFilter.switchesOffline,
    GwnDeviceKind.accessPoint: NetworkSchoolFilter.apsOffline,
  };

  void _drill(
    BuildContext context,
    NetworkSchoolFilter filter, {
    required String title,
    required String value,
    String? note,
    List<DrillFact> facts = const [],
  }) =>
      showNetworkDrill(
        context,
        drillFor(insights, filter, title: title, value: value, note: note, facts: facts),
        onOpenList: onOpenList,
      );

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final kinds = [GwnDeviceKind.router, GwnDeviceKind.networkSwitch, GwnDeviceKind.accessPoint];
    final poeFailed = d.schools.fold<int>(0, (a, s) => a + s.poePortsFailed);
    final portErrors = d.schools.fold<int>(0, (a, s) => a + s.portsError);
    final fwTotal = d.schools.fold<int>(0, (a, s) => a + s.firmwareTotal);
    final fwOk = d.schools.fold<int>(0, (a, s) => a + s.firmwareCompliant);

    return SectionCard(
      title: 'Infrastructure health',
      subtitle: 'Gateway, switches and access points reported by the cloud · tap a figure for the schools behind it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Availability(
                label: k.label,
                online: d.devicesOnlineByKind[k] ?? 0,
                total: d.devicesByKind[k] ?? 0,
                // A row at full availability has no list to open: the
                // chevron would lead to an empty sheet.
                onTap: (d.devicesOnlineByKind[k] ?? 0) >= (d.devicesByKind[k] ?? 0)
                    ? null
                    : () => _drill(
                          context,
                          _kindFilter[k]!,
                          title: '${k.label} — schools with one down',
                          value: '${Fmt.int_(d.devicesOnlineByKind[k] ?? 0)} / ${Fmt.int_(d.devicesByKind[k] ?? 0)}',
                          facts: [
                            DrillFact('${k.label} reported', Fmt.int_(d.devicesByKind[k] ?? 0)),
                            DrillFact('Online', Fmt.int_(d.devicesOnlineByKind[k] ?? 0)),
                          ],
                          note: 'The bar counts devices across the account; the list counts the schools that have at '
                              'least one of them down.',
                        ),
              ),
            ),
          const Divider(height: 20),
          InfoRow(
            'PoE ports failed',
            Fmt.int_(poeFailed),
            onTap: poeFailed == 0
                ? null
                : () => _drill(context, NetworkSchoolFilter.poeFailed,
                    title: 'PoE ports failed',
                    value: Fmt.int_(poeFailed),
                    note: _countsThings('ports')),
          ),
          InfoRow(
            'LAN ports with errors',
            Fmt.int_(portErrors),
            onTap: portErrors == 0
                ? null
                : () => _drill(context, NetworkSchoolFilter.portErrors,
                    title: 'LAN ports with errors',
                    value: Fmt.int_(portErrors),
                    note: _countsThings('ports')),
          ),
          InfoRow(
            'Firmware compliance',
            fwTotal == 0 ? '–' : '${Fmt.ratio(fwOk / fwTotal)} · $fwOk of $fwTotal devices',
            onTap: fwTotal == 0 || fwOk == fwTotal
                ? null
                : () => _drill(
                      context,
                      NetworkSchoolFilter.firmwareOutdated,
                      title: 'Devices off the firmware baseline',
                      value: Fmt.int_(fwTotal - fwOk),
                      note: _countsThings('devices'),
                      facts: [
                        DrillFact('Devices on the baseline', '$fwOk of $fwTotal'),
                        DrillFact('Compliance', Fmt.ratio(fwOk / fwTotal)),
                      ],
                    ),
          ),
          const SizedBox(height: 8),
          const MutedNote(
            'Firmware compliance counts devices on the account\'s most common release, which stands in for an approved '
            'baseline until one is configured. Configuration compliance needs an expected VLAN / SSID / firewall '
            'baseline to compare against and is not computed.',
          ),
        ],
      ),
    );
  }
}

class _Availability extends StatelessWidget {
  const _Availability({required this.label, required this.online, required this.total, this.onTap});
  final String label;
  final int online;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? null : online / total;
    final color = share == null
        ? AppColors.muted
        : share >= 0.95
            ? AppColors.good
            : share >= 0.8
                ? AppColors.warning
                : AppColors.critical;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(
              total == 0 ? 'none' : '${Fmt.int_(online)} of ${Fmt.int_(total)} · ${Fmt.ratio(share)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ],
        ),
        const SizedBox(height: 4),
        RatioMeter(value: share ?? 0, color: color),
      ],
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: body),
    );
  }
}

/// Sections 3 and 4 — portfolio uptime, clients and traffic per day.
class NetworkTrendCard extends StatelessWidget {
  const NetworkTrendCard({super.key, required this.insights});

  final NetworkInsights insights;

  /// A day on the chart opens what that day was made of.
  void _showDay(BuildContext context, String day, {required bool hasClients}) {
    final d = insights;
    final clients = d.dailyClients.where((x) => x.day == day).firstOrNull?.clients;
    final bytes = d.dailyBytes.where((x) => x.day == day).firstOrNull?.bytes;
    final aps = d.dailyApsOnline.where((x) => x.day == day).firstOrNull?.aps;
    final uptime = d.dailyUptime.where((x) => x.day == day).firstOrNull?.uptime;
    showNetworkDrill(
      context,
      NetworkDrill(
        title: Fmt.shortDay(day),
        value: hasClients ? Fmt.int_(clients) : Fmt.int_(aps),
        what: 'What the whole portfolio reported on this day, accrued from the app\'s own observations — the cloud '
            'exposes no history of its own.',
        rows: const [],
        facts: [
          DrillFact('Client devices', clients == null ? 'not reported' : Fmt.int_(clients)),
          DrillFact('Access points online', aps == null ? 'not reported' : Fmt.int_(aps)),
          DrillFact('Traffic', bytes == null || bytes == 0 ? 'not reported' : Fmt.bytes(bytes)),
          DrillFact('Mean uptime', Fmt.ratio(uptime, decimals: 1)),
        ],
        emptyMessage: 'These are portfolio totals for the day. The per-school split is kept for the current state '
            'only, so a past day cannot be broken down by school.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = insights;
    // Client counts are the point of this card, but where the account does
    // not report them the access points do exist, and showing those beats
    // an empty panel.
    final hasClients = d.dailyClients.any((x) => x.clients > 0);
    if (d.dailyClients.isEmpty && d.dailyApsOnline.isEmpty) {
      return const SectionCard(
        title: 'Use over time',
        child: EmptyState(
          message: 'No daily counters yet. The cloud exposes no usage history, so this series is built from the '
              'app\'s own observations — it fills in from the next sync onwards, one point per day.',
          icon: Icons.show_chart,
        ),
      );
    }
    final p = ChartPalette.of(context);
    final rows = hasClients ? d.dailyClients : d.dailyApsOnline.map((x) => (day: x.day, clients: x.aps)).toList();
    final groups = [
      for (var i = 0; i < rows.length; i++)
        BarGroup(
          label: Fmt.shortDay(rows[i].day),
          fullLabel: hasClients
              ? '${Fmt.shortDay(rows[i].day)} · ${Fmt.int_(rows[i].clients)} devices · ${Fmt.bytes(d.dailyBytes[i].bytes)}'
              : '${Fmt.shortDay(rows[i].day)} · ${Fmt.int_(rows[i].clients)} access points up',
          values: [rows[i].clients.toDouble()],
        ),
    ];
    // The table lists newest first; its row index has to be mapped back.
    final tableDays = [for (var i = rows.length - 1; i >= 0; i--) rows[i].day];
    return ChartOrTable(
      title: hasClients ? 'Client devices per day' : 'Access points online per day',
      subtitle: hasClients
          ? 'Unique devices seen across every school, last ${d.days} days'
          : 'This account reports no client counts, so the access points stand in — last ${d.days} days',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnergyBarChart(
            seriesLabels: [hasClients ? 'Devices' : 'Access points'],
            seriesColors: [p.load],
            groups: groups,
            height: 220,
            maxLabels: 10,
            unitFormatter: (v) => Fmt.int_(v),
            emptyMessage: 'Nothing recorded yet',
            onBarTap: (i) => _showDay(context, rows[i].day, hasClients: hasClients),
          ),
          MutedNote(
            hasClients
                ? 'Unique device identifiers are a proxy for devices, not for students: modern phones randomise their '
                    'MAC address unless they authenticate, so a device count can move without the number of users changing.'
                : 'Access points online is an infrastructure figure, not a measure of use. It is shown because this '
                    'account reports no client counts; the adoption indicators stay unscored until it does.',
          ),
        ],
      ),
      table: ChartTable(
        columns: ['Day', hasClients ? 'Devices' : 'APs up', 'Traffic', 'Mean uptime'],
        onRowTap: (i) => _showDay(context, tableDays[i], hasClients: hasClients),
        rows: [
          for (var i = rows.length - 1; i >= 0; i--)
            [
              Fmt.shortDay(rows[i].day),
              Fmt.int_(rows[i].clients),
              Fmt.bytes(d.dailyBytes.where((b) => b.day == rows[i].day).firstOrNull?.bytes),
              Fmt.ratio(d.dailyUptime.where((u) => u.day == rows[i].day).firstOrNull?.uptime, decimals: 1),
            ],
        ],
      ),
    );
  }
}

/// Section 4 — where the traffic goes, by SSID.
class SsidSplitCard extends StatelessWidget {
  const SsidSplitCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final rows = insights.ssidTraffic;
    if (rows.isEmpty) {
      return const SectionCard(
        title: 'Traffic by SSID',
        child: EmptyState(
          message: 'This GWN API version lists SSIDs but reports no traffic against them, so the staff / student / '
              'admin split cannot be computed from it.',
          icon: Icons.wifi_tethering,
        ),
      );
    }
    final p = ChartPalette.of(context);
    final total = rows.fold<int>(0, (a, r) => a + r.bytes);
    // Only the largest few get a slice of their own; the rest are gathered
    // rather than dropped, so the centre total is the sum of what is drawn.
    const top = 5;
    final rest = rows.length > top ? rows.skip(top).fold<int>(0, (a, r) => a + r.bytes) : 0;
    return SectionCard(
      title: 'Traffic by SSID',
      subtitle: 'Separates staff, student and admin use over the last ${insights.days} days',
      child: DonutChart(
        slices: [
          for (var i = 0; i < rows.length && i < top; i++)
            (rows[i].ssid, rows[i].bytes.toDouble(), p.categorical[i % p.categorical.length]),
          if (rest > 0) ('${rows.length - top} other SSIDs', rest.toDouble(), AppColors.muted),
        ],
        centerLabel: 'Total',
        centerValue: Fmt.bytes(total),
        valueFormatter: Fmt.bytes,
        onTap: (i) => showNetworkDrill(
          context,
          NetworkDrill(
            title: i < top ? rows[i].ssid : '${rows.length - top} other SSIDs',
            value: Fmt.bytes(i < top ? rows[i].bytes : rest),
            what: i < top
                ? 'Traffic carried by this SSID across the account over the last ${insights.days} days.'
                : 'Everything outside the ${Fmt.int_(top)} largest SSIDs, gathered into one slice so the total adds up.',
            rows: const [],
            facts: [
              DrillFact('Traffic', Fmt.bytes(i < top ? rows[i].bytes : rest)),
              DrillFact('Share of all SSID traffic', total == 0 ? '–' : Fmt.ratio((i < top ? rows[i].bytes : rest) / total)),
              if (i < top) DrillFact('Peak clients', Fmt.int_(rows[i].clients)),
              if (i >= top) DrillFact('SSIDs gathered', Fmt.int_(rows.length - top)),
            ],
            emptyMessage: 'The cloud reports SSID totals for the account, not per school, so this figure has no '
                'school-by-school breakdown.',
          ),
        ),
      ),
    );
  }
}

/// Per-governorate roll-up.
class NetworkRegionCard extends StatelessWidget {
  const NetworkRegionCard({super.key, required this.insights});

  final NetworkInsights insights;

  void _showRegion(BuildContext context, RegionNetwork r) {
    final rows = insights.schools.where((s) => (s.region ?? 'Unassigned') == r.region).toList()
      ..sort((a, b) => (b.index ?? -1).compareTo(a.index ?? -1));
    showNetworkDrill(
      context,
      NetworkDrill(
        title: r.region,
        value: Fmt.int_(r.schools),
        what: 'Every school in this governorate with a monitored network, strongest adoption index first.',
        rows: rows,
        metric: (s) => (value: s.index == null ? '–' : s.index!.toStringAsFixed(0), hint: 'index'),
        facts: [
          DrillFact('Connected', Fmt.int_(r.connected)),
          DrillFact('Actively using technology', Fmt.int_(r.active)),
          DrillFact('Mean index', r.meanIndex == null ? '–' : r.meanIndex!.toStringAsFixed(0)),
          DrillFact('Mean uptime', Fmt.ratio(r.meanUptime, decimals: 1)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = insights.byRegion;
    if (rows.isEmpty) {
      return const SectionCard(
        title: 'By governorate',
        child: EmptyState(message: 'No network could be matched to a school yet.', icon: Icons.map_outlined),
      );
    }
    return SectionCard(
      title: 'By governorate',
      subtitle: 'Schools with a monitored network, and how they are doing · tap a row for its schools',
      child: ChartTable(
        columns: const ['Governorate', 'Schools', 'Connected', 'Active', 'Mean index', 'Mean uptime'],
        onRowTap: (i) => _showRegion(context, rows[i]),
        rows: [
          for (final r in rows)
            [
              r.region,
              Fmt.int_(r.schools),
              Fmt.int_(r.connected),
              Fmt.int_(r.active),
              r.meanIndex == null ? '–' : r.meanIndex!.toStringAsFixed(0),
              Fmt.ratio(r.meanUptime, decimals: 1),
            ],
        ],
      ),
    );
  }
}

/// Section 11 — what the dashboard cannot answer, and what it would take.
class MissingSourcesCard extends StatelessWidget {
  const MissingSourcesCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Indicators that need another source',
        subtitle: 'From the framework, but not answerable from the network account alone',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in insights.missingSources)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.indicator, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Needs: ${m.source}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            const MutedNote(
              'These are listed rather than shown empty so the dashboard says why a figure is absent. Connecting any of '
              'them fills in its indicators and raises the share of the index weight that can be scored.',
            ),
          ],
        ),
      );
}
