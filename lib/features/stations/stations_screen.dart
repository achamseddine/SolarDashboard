import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fleet_insights.dart';
import '../../core/providers.dart';
import '../common/widgets.dart';
import 'nav.dart';
import 'station_filters.dart';
import 'widgets/station_csv.dart';
import 'widgets/station_filter_bar.dart';
import 'widgets/station_table.dart';

/// Schools list: search, filters, sort, wide table, CSV export.
class StationsScreen extends ConsumerStatefulWidget {
  const StationsScreen({super.key, this.initialQuery, this.initialRegion, this.initialStatus, this.initialFilter});
  final String? initialQuery;
  final String? initialRegion;
  final String? initialStatus;

  /// Quick filter from the dashboard: `alarms`, `underperforming`, `lowsoc`.
  final String? initialFilter;

  @override
  ConsumerState<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends ConsumerState<StationsScreen> {
  late StationFilter _filter;
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _filter = StationFilter.fromRoute(query: widget.initialQuery, region: widget.initialRegion, status: widget.initialStatus, filter: widget.initialFilter);
    _search = TextEditingController(text: _filter.query);
  }

  @override
  void didUpdateWidget(covariant StationsScreen old) {
    super.didUpdateWidget(old);
    // A new deep link (e.g. dashboard → "/stations?status=offline") while
    // already on this screen replaces the filter.
    if (old.initialQuery != widget.initialQuery || old.initialRegion != widget.initialRegion || old.initialStatus != widget.initialStatus || old.initialFilter != widget.initialFilter) {
      final next = StationFilter.fromRoute(query: widget.initialQuery, region: widget.initialRegion, status: widget.initialStatus, filter: widget.initialFilter);
      _filter = next.copyWith(sort: _filter.sort, ascending: _filter.ascending);
      _search.text = _filter.query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(StationFilter f) => setState(() => _filter = f);

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(fleetInsightsProvider);
    return Padding(
      padding: kPagePadding,
      child: AsyncView<FleetInsights>(
        value: insights,
        emptyWhen: (d) => d.stations.isEmpty,
        emptyMessage: 'No schools yet – data appears after the first sync.',
        builder: (data) {
          final rows = _filter.apply(data.stations);
          final regionCounts = <String, int>{};
          for (final s in data.stations) {
            regionCounts[s.region] = (regionCounts[s.region] ?? 0) + 1;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Schools',
                subtitle: _countsLine(rows.length, data.stations.length),
                actions: [
                  Builder(
                    builder: (ctx) => FilledButton.tonalIcon(
                      onPressed: rows.isEmpty ? null : () => exportStationsCsv(ctx, rows),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export CSV'),
                    ),
                  ),
                ],
              ),
              StationFilterBar(filter: _filter, onChanged: _update, searchController: _search, regionCounts: regionCounts),
              const SizedBox(height: kGap),
              Expanded(
                child: rows.isEmpty
                    ? EmptyState(
                        message: 'No schools match the current filters.',
                        icon: Icons.filter_alt_off_outlined,
                        action: TextButton(
                          onPressed: () {
                            _search.clear();
                            _update(StationFilter(sort: _filter.sort, ascending: _filter.ascending));
                          },
                          child: const Text('Clear filters'),
                        ),
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 260),
                              child: StationTable(
                                rows: rows,
                                filter: _filter,
                                onSort: (sort, asc) => _update(_filter.copyWith(sort: sort, ascending: asc)),
                                onTap: (s) => goTo(context, '/stations/${s.id}'),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _countsLine(int shown, int total) {
    final base = shown == total ? '$total schools' : '$shown of $total schools';
    final bits = <String>[
      if (_filter.region != null) _filter.region!,
      if (_filter.status != null) _filter.status!.label.toLowerCase(),
      if (_filter.withAlarms) 'with alarms',
      if (_filter.underPerforming) 'under-performing',
      if (_filter.lowSoc) 'low SOC',
      if (_filter.query.isNotEmpty) '"${_filter.query}"',
    ];
    return bits.isEmpty ? base : '$base · ${bits.join(' · ')}';
  }
}
