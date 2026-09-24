import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/network_filter.dart';
import '../../../core/models/network_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// One label/value line inside a detail panel.
///
/// [opens] makes the line a target in its own right, so a number inside the
/// panel drills down exactly like the tile that opened it.
class DrillFact {
  const DrillFact(this.label, this.value, {this.opens});

  final String label;
  final String value;
  final NetworkDrill Function()? opens;
}

/// What one number on the network dashboards is made of: the figure, what it
/// means, and the schools behind it.
///
/// Built once per tapped tile so the panel that opens is the same statement
/// the tile made — the rows are selected by the predicate that produced the
/// count, not by a similar-looking one.
class NetworkDrill {
  const NetworkDrill({
    required this.title,
    required this.value,
    required this.what,
    required this.rows,
    this.metric,
    this.note,
    this.filter,
    this.facts = const [],
    this.emptyMessage,
  });

  final String title;

  /// The headline figure exactly as the tile printed it.
  final String value;

  /// What the figure counts, in the operator's terms.
  final String what;

  final List<SchoolNetwork> rows;

  /// The figure to show beside each school — the one being counted.
  final ({String value, String hint}) Function(SchoolNetwork school)? metric;

  /// Caveat worth carrying into the detail view.
  final String? note;

  /// Set when the list can be reopened as a filter on the Schools tab.
  final NetworkSchoolFilter? filter;

  /// Label/value lines shown above the list, for figures that are not a
  /// simple count of schools.
  final List<DrillFact> facts;

  /// Why there is no list, when a figure has no per-school breakdown.
  final String? emptyMessage;
}

/// Every detail sheet carries this name, so leaving for the Schools tab can
/// close the whole stack rather than one panel of it.
const String _sheetRoute = 'network-detail';

/// Opens [drill] as a sheet. [onOpenList] carries the slice to the Schools
/// tab, where it can be sorted and searched in full.
Future<void> showNetworkDrill(
  BuildContext context,
  NetworkDrill drill, {
  void Function(NetworkSchoolFilter filter)? onOpenList,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 900),
      routeSettings: const RouteSettings(name: _sheetRoute),
      builder: (_) => _DrillSheet(drill: drill, onOpenList: onOpenList),
    );

/// Builds the panel behind one headline slice.
NetworkDrill drillFor(
  NetworkInsights insights,
  NetworkSchoolFilter filter, {
  String? title,
  String? value,
  String? note,
  List<DrillFact> facts = const [],
}) {
  final rows = filter.select(insights);
  return NetworkDrill(
    title: title ?? filter.label,
    value: value ?? Fmt.int_(rows.length),
    what: filter.what,
    rows: rows,
    metric: filter.metric,
    note: note,
    filter: filter,
    facts: facts,
  );
}

class _DrillSheet extends StatefulWidget {
  const _DrillSheet({required this.drill, this.onOpenList});

  final NetworkDrill drill;
  final void Function(NetworkSchoolFilter filter)? onOpenList;

  @override
  State<_DrillSheet> createState() => _DrillSheetState();
}

class _DrillSheetState extends State<_DrillSheet> {
  String _query = '';

  List<SchoolNetwork> get _rows {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.drill.rows;
    return widget.drill.rows
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.region ?? '').toLowerCase().contains(q) ||
            (s.caza ?? '').toLowerCase().contains(q) ||
            '${s.cerd ?? ''}'.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drill;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows;
    // The header scrolls with the list rather than sitting above it: a
    // definition, two thresholds and a search field do not fit above a list
    // when the sheet is dragged down, and an unscrollable header there
    // overflows and takes the footer button off the bottom with it.
    return Padding(
      // The soft keyboard must not cover the list the search field filters.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(d.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                              const SizedBox(width: 12),
                              Text(d.value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.unicefCyan)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(d.what, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          for (final f in d.facts)
                            InfoRow(
                              f.label,
                              f.value,
                              onTap: f.opens == null ? null : () => showNetworkDrill(context, f.opens!(), onOpenList: widget.onOpenList),
                            ),
                          if (d.note != null) ...[
                            const SizedBox(height: 6),
                            Text(d.note!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                          if (d.rows.length > 8) ...[
                            const SizedBox(height: 10),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search a school by name, CERD, governorate or district',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ],
                          const SizedBox(height: 6),
                          if (d.rows.isNotEmpty)
                            Text(
                              '${Fmt.int_(rows.length)} of ${Fmt.int_(d.rows.length)} schools · tap one for its full record',
                              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          const SizedBox(height: 6),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyState(
                        message: d.rows.isEmpty
                            ? (d.emptyMessage ?? d.filter?.whenEmpty ?? 'No school falls under this figure.')
                            : 'No school matches.',
                        icon: d.rows.isEmpty ? Icons.info_outline : Icons.search_off,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final s = rows[i];
                          final m = d.metric?.call(s);
                          return CompactRow(
                            title: s.name,
                            subtitle: [
                              if (s.cerd != null) 'CERD ${s.cerd}' else 'not matched to a school',
                              ?s.region,
                              ?s.caza,
                            ].join(' · '),
                            trailing: m?.value,
                            trailingHint: m?.hint,
                            onTap: () => showSchoolNetworkDetail(context, s),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (d.filter != null && widget.onOpenList != null && d.rows.isNotEmpty)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          // A drill opened from inside another drill leaves
                          // two panels on the stack; both have to go or the
                          // table opens underneath them.
                          Navigator.of(context).popUntil((r) => r.settings.name != _sheetRoute);
                          widget.onOpenList!(d.filter!);
                        },
                        icon: const Icon(Icons.table_rows_outlined, size: 18),
                        label: const Text('Open in the Schools tab'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything the app knows about one school's network, in one panel.
Future<void> showSchoolNetworkDetail(BuildContext context, SchoolNetwork school) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 900),
      routeSettings: const RouteSettings(name: _sheetRoute),
      builder: (_) => _SchoolSheet(school: school),
    );

class _SchoolSheet extends StatelessWidget {
  const _SchoolSheet({required this.school});

  final SchoolNetwork school;

  @override
  Widget build(BuildContext context) {
    final s = school;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(s.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            [
              if (s.cerd != null) 'CERD ${s.cerd}' else 'not matched to a school',
              ?s.region,
              ?s.caza,
              if (s.students != null) '${Fmt.int_(s.students)} students',
            ].join(' · '),
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _Group('Status', [
            DrillFact('Where it sits', s.quadrant.label),
            DrillFact('Seen online', s.seenOnline ? 'yes' : 'not yet'),
            DrillFact('LAN operational', s.lanOperational ? 'yes' : 'no'),
            DrillFact('Adoption index', s.index == null ? 'not scored' : '${s.index!.toStringAsFixed(0)} / 100'),
            DrillFact('Use score', s.usageScore == null ? 'nothing measured yet' : '${s.usageScore!.toStringAsFixed(0)} / 100'),
          ]),
          _Group('Infrastructure', [
            DrillFact('Gateways online', s.gatewaysTotal == 0 ? 'none reported' : '${s.gatewaysOnline} of ${s.gatewaysTotal}'),
            DrillFact('Switches online', s.switchesTotal == 0 ? 'none reported' : '${s.switchesOnline} of ${s.switchesTotal}'),
            DrillFact('Access points online', s.apsTotal == 0 ? 'none reported' : '${s.apsOnline} of ${s.apsTotal} · ${Fmt.ratio(s.apAvailability)}'),
            DrillFact('PoE ports failed', Fmt.int_(s.poePortsFailed)),
            DrillFact('LAN ports with errors', Fmt.int_(s.portsError)),
            DrillFact('Firmware on baseline', s.firmwareTotal == 0 ? '–' : '${s.firmwareCompliant} of ${s.firmwareTotal}'),
            if (s.cpuMax != null) DrillFact('Peak CPU', Fmt.percent(s.cpuMax)),
            if (s.memoryMax != null) DrillFact('Peak memory', Fmt.percent(s.memoryMax)),
          ]),
          _Group('Internet', [
            DrillFact('Uptime', Fmt.ratio(s.uptimeShare, decimals: 1)),
            DrillFact('Downtime', s.downtimeHours == null ? '–' : '${Fmt.one(s.downtimeHours)} h'),
            DrillFact('Days reported', Fmt.int_(s.daysReported)),
            DrillFact('Days since last outage', s.daysSinceOutage == null ? '–' : Fmt.int_(s.daysSinceOutage)),
          ]),
          _Group('Use', [
            DrillFact('Client devices per day', s.avgDailyClients == null ? 'not reported' : Fmt.int_(s.avgDailyClients!.round())),
            DrillFact('Peak devices', s.peakClients == null ? 'not reported' : Fmt.int_(s.peakClients)),
            DrillFact('Traffic per day', s.avgDailyBytes == null ? 'not reported' : Fmt.bytes(s.avgDailyBytes)),
            DrillFact('Traffic in the window', s.totalBytes == null ? 'not reported' : Fmt.bytes(s.totalBytes)),
            DrillFact('Active access points', Fmt.ratio(s.activeApShare)),
            DrillFact('Days with activity', s.schoolDays == 0 ? '–' : '${s.daysWithActivity} of ${s.schoolDays}'),
            if (s.usageGrowth != null) DrillFact('Use trend', Fmt.percent(s.usageGrowth! * 100, decimals: 0)),
          ]),
          _Group('Support', [
            DrillFact('Open alarms', Fmt.int_(s.openAlarms)),
            DrillFact('Open critical alarms', Fmt.int_(s.openCriticalAlarms)),
          ]),
          const SizedBox(height: 8),
          Text('Adoption index components', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final c in s.components)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${c.label} · ${Fmt.ratio(c.weight)} of the weight', style: t.bodySmall)),
                      Text(c.score == null ? 'no source' : c.score!.toStringAsFixed(0),
                          style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (c.score != null) ...[
                    const SizedBox(height: 4),
                    RatioMeter(value: (c.score! / 100).clamp(0, 1), color: AppColors.unicefCyan),
                  ] else if (c.missingSource != null)
                    Text('needs ${c.missingSource}', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          MutedNote(
            'Scored on ${Fmt.ratio(s.availableWeight)} of the framework weight. Components without a source are left '
            'out and the rest renormalised, so the school is not marked down for data nobody collected.',
          ),
          if (s.cerd != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () {
                  // The router has to be read before the sheet closes: this
                  // context is gone the moment it pops.
                  final router = GoRouter.maybeOf(context);
                  Navigator.of(context).pop();
                  router?.go('/schools/${s.cerd}');
                },
                icon: const Icon(Icons.school_outlined, size: 18),
                label: const Text('Open the school record'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);

  final String title;
  final List<DrillFact> rows;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            for (final r in rows) InfoRow(r.label, r.value),
          ],
        ),
      );
}
