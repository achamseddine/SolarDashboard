import 'package:flutter/material.dart';

import '../../../core/models/network_filter.dart';
import '../../../core/models/network_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'network_detail_sheet.dart';

/// Every school with a monitored network, with the indicators a manager acts
/// on and a filter for each quadrant of the matrix.
class NetworkSchoolsTable extends StatefulWidget {
  const NetworkSchoolsTable({
    super.key,
    required this.insights,
    this.initialQuadrant,
    this.initialFilter,
    this.revision = 0,
    this.onSelectionChanged,
  });

  final NetworkInsights insights;
  final AdoptionQuadrant? initialQuadrant;

  /// A headline slice sent here from a tapped tile, shown as a chip that can
  /// be cleared.
  final NetworkSchoolFilter? initialFilter;

  /// Rises on every jump from a tile. Without it, clearing the chip and
  /// tapping the same tile again would arrive with an unchanged filter and
  /// leave the table showing everything.
  final int revision;

  /// Tells the screen what the chips now say, so a filter cleared here does
  /// not come back the next time this tab is built.
  final void Function(AdoptionQuadrant? quadrant, NetworkSchoolFilter? filter)? onSelectionChanged;

  @override
  State<NetworkSchoolsTable> createState() => _NetworkSchoolsTableState();
}

class _NetworkSchoolsTableState extends State<NetworkSchoolsTable> {
  late AdoptionQuadrant? _quadrant = widget.initialQuadrant;
  late NetworkSchoolFilter? _filter = widget.initialFilter;
  String _query = '';
  int _sort = 0;
  bool _asc = true;

  @override
  void didUpdateWidget(covariant NetworkSchoolsTable old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision ||
        old.initialQuadrant != widget.initialQuadrant ||
        old.initialFilter != widget.initialFilter) {
      _quadrant = widget.initialQuadrant;
      _filter = widget.initialFilter;
    }
  }

  List<SchoolNetwork> get _rows {
    final q = _query.trim().toLowerCase();
    final rows = widget.insights.schools.where((s) {
      if (_quadrant != null && s.quadrant != _quadrant) return false;
      if (_filter != null && !_filter!.matches(s, widget.insights.thresholds)) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          (s.region ?? '').toLowerCase().contains(q) ||
          (s.caza ?? '').toLowerCase().contains(q) ||
          '${s.cerd ?? ''}'.contains(q);
    }).toList();
    int cmp(SchoolNetwork a, SchoolNetwork b) {
      final r = switch (_sort) {
        1 => (a.uptimeShare ?? -1).compareTo(b.uptimeShare ?? -1),
        2 => (a.avgDailyClients ?? -1).compareTo(b.avgDailyClients ?? -1),
        3 => (a.activityShare ?? -1).compareTo(b.activityShare ?? -1),
        4 => (a.index ?? -1).compareTo(b.index ?? -1),
        _ => a.name.compareTo(b.name),
      };
      return _asc ? r : -r;
    }

    rows.sort(cmp);
    return rows;
  }

  /// Applies a chip and tells the screen, so the two cannot drift apart.
  void _select({AdoptionQuadrant? quadrant, NetworkSchoolFilter? filter}) {
    setState(() {
      _quadrant = quadrant;
      _filter = filter;
    });
    widget.onSelectionChanged?.call(quadrant, filter);
  }

  void _sortBy(int column, bool ascending) => setState(() {
        _sort = column;
        _asc = ascending;
      });

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SectionCard(
      title: 'Schools',
      subtitle: '${Fmt.int_(rows.length)} of ${Fmt.int_(widget.insights.schools.length)} monitored schools · tap a row for the full record',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_filter != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text(_filter!.label),
                onDeleted: () => _select(quadrant: _quadrant),
              ),
            ),
            const SizedBox(height: 4),
            Text(_filter!.what, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _quadrant == null,
                onSelected: (_) => _select(filter: _filter),
              ),
              for (final q in AdoptionQuadrant.values)
                if ((widget.insights.quadrants[q] ?? 0) > 0)
                  ChoiceChip(
                    label: Text('${q.label} ${widget.insights.quadrants[q]}'),
                    selected: _quadrant == q,
                    onSelected: (_) => _select(quadrant: _quadrant == q ? null : q, filter: _filter),
                  ),
            ],
          ),
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
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const EmptyState(message: 'No school matches this filter.', icon: Icons.search_off)
          else
            SizedBox(
              height: 420,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    // A tappable row otherwise grows a checkbox column and a
                    // select-all box that would open every school at once.
                    showCheckboxColumn: false,
                    sortColumnIndex: _sort,
                    sortAscending: _asc,
                    columns: [
                      DataColumn(label: const Text('School'), onSort: _sortBy),
                      DataColumn(label: const Text('Uptime'), numeric: true, onSort: _sortBy),
                      DataColumn(label: const Text('Devices / day'), numeric: true, onSort: _sortBy),
                      DataColumn(label: const Text('Active days'), numeric: true, onSort: _sortBy),
                      DataColumn(label: const Text('Index'), numeric: true, onSort: _sortBy),
                      const DataColumn(label: Text('APs')),
                      const DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final s in rows)
                        DataRow(onSelectChanged: (_) => showSchoolNetworkDetail(context, s), cells: [
                          DataCell(_School(school: s)),
                          DataCell(Text(Fmt.ratio(s.uptimeShare, decimals: 1))),
                          DataCell(Text(s.avgDailyClients == null ? '–' : Fmt.int_(s.avgDailyClients!.round()))),
                          DataCell(Text(s.schoolDays == 0 ? '–' : '${s.daysWithActivity} / ${s.schoolDays}')),
                          DataCell(Text(s.index == null ? '–' : s.index!.toStringAsFixed(0))),
                          DataCell(Text(s.apsTotal == 0 ? '–' : '${s.apsOnline} / ${s.apsTotal}')),
                          DataCell(_QuadrantChip(quadrant: s.quadrant)),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const MutedNote(
            'Uptime is connected minutes over expected minutes within school hours. Active days count days that carried '
            'both the agreed client count and the agreed traffic.',
          ),
        ],
      ),
    );
  }
}

class _School extends StatelessWidget {
  const _School({required this.school});
  final SchoolNetwork school;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(school.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(
            [
              if (school.cerd != null) 'CERD ${school.cerd}',
              if (school.region != null) school.region!,
              if (school.caza != null) school.caza!,
              if (school.cerd == null) 'not matched to a school',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

class _QuadrantChip extends StatelessWidget {
  const _QuadrantChip({required this.quadrant});
  final AdoptionQuadrant quadrant;

  @override
  Widget build(BuildContext context) {
    final color = switch (quadrant) {
      AdoptionQuadrant.active => AppColors.good,
      AdoptionQuadrant.adoptionSupport => AppColors.warning,
      AdoptionQuadrant.constrained => AppColors.serious,
      AdoptionQuadrant.technical => AppColors.critical,
      AdoptionQuadrant.unknown => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(quadrant.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
