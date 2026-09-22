import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fleet_insights.dart';
import '../../core/models/sync.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/plant_counter_bar.dart';
import 'widgets/plant_filters.dart';
import 'widgets/plant_kpis.dart';
import 'widgets/plant_pager.dart';
import 'widgets/plant_table.dart';

/// Plants overview — the app's counterpart of the DeyeCloud "Overview" page:
/// the five account-wide figures, the status counters as filters, and a
/// paged table of **every** plant of the account.
///
/// The table is deliberately free of programme filters: a plant is listed
/// whatever its governorate, whether or not it is linked to a MEHE school
/// and whatever kind of site it sits on.
class PlantsOverviewScreen extends ConsumerStatefulWidget {
  const PlantsOverviewScreen({super.key, this.initialQuery, this.initialStatus, this.initialFilter});

  /// Deep-link search text.
  final String? initialQuery;

  /// Deep-link status counter: `online`, `offline`, `alarm`, `stale`, `unknown`.
  final String? initialStatus;

  /// Deep-link counter: `alarms`, `noalerts`, `partial`.
  final String? initialFilter;

  PlantQuery get _routeQuery => PlantQuery(
        query: initialQuery ?? '',
        counter: PlantCounter.fromRoute(status: initialStatus, filter: initialFilter),
      );

  @override
  ConsumerState<PlantsOverviewScreen> createState() => _PlantsOverviewScreenState();
}

class _PlantsOverviewScreenState extends ConsumerState<PlantsOverviewScreen> {
  late PlantQuery _query;
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _query = widget._routeQuery;
    _search = TextEditingController(text: _query.query);
  }

  @override
  void didUpdateWidget(covariant PlantsOverviewScreen old) {
    super.didUpdateWidget(old);
    final changed = old.initialQuery != widget.initialQuery || old.initialStatus != widget.initialStatus || old.initialFilter != widget.initialFilter;
    if (changed) {
      final next = widget._routeQuery;
      _query = _query.copyWith(query: next.query, counter: next.counter, page: 0);
      _search.text = next.query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Any change to search, counter or page size restarts at page 1.
  void _update(PlantQuery q) => setState(() => _query = q);

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(fleetInsightsProvider);
    final sync = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final canSync = ref.watch(canSyncProvider);
    return Padding(
      padding: kPagePadding,
      child: AsyncView<FleetInsights>(
        value: insights,
        builder: (data) => _body(context, data, sync, canSync),
      ),
    );
  }

  Widget _body(BuildContext context, FleetInsights data, SyncStatus sync, bool canSync) {
    // Every plant the database holds — no region, school or site filter.
    final all = data.stations;
    final counts = countPlants(all);
    final matched = _query.apply(all);
    final page = PlantPage.of(matched, pageSize: _query.pageSize, page: _query.page);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Plants',
          subtitle: '${Fmt.int_(all.length)} plants in the DeyeCloud account · ${Fmt.int_(data.reportingStations)} reporting now',
          actions: [
            OutlinedButton.icon(onPressed: () => goTo(context, '/map'), icon: const Icon(Icons.map_outlined, size: 18), label: const Text('Map')),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: sync.running || !canSync ? null : () => ref.read(syncEngineProvider).syncNow(),
              icon: sync.running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
              label: Text(sync.running ? sync.phase.label : 'Sync now'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (sync.isTruncated) ...[
                _TruncationWarning(message: sync.truncation!),
                const SizedBox(height: kGap),
              ],
              PlantKpiStrip(insights: data),
              const SizedBox(height: kGap),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlantCounterBar(
                      counts: counts,
                      selected: _query.counter,
                      onSelected: (c) => _update(_query.copyWith(counter: c, page: 0)),
                    ),
                    const SizedBox(height: 12),
                    _SearchField(
                      controller: _search,
                      onChanged: (v) => _update(_query.copyWith(query: v, page: 0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: kGap),
              _TableCard(
                page: page,
                query: _query,
                empty: all.isEmpty,
                onSort: (sort, asc) => _update(_query.copyWith(sort: sort, ascending: asc, page: 0)),
                onClear: () {
                  _search.clear();
                  _update(PlantQuery(sort: _query.sort, ascending: _query.ascending, pageSize: _query.pageSize));
                },
              ),
              MutedNote(
                'Every plant of the DeyeCloud account is listed here, whatever the type of location: plants are never hidden because they have no governorate, '
                'no address or no linked school — a plant without a governorate shows "Unassigned". '
                'Source: the DeyeCloud account, last synced ${sync.lastSuccessAt == null ? 'never' : Fmt.ago(sync.lastSuccessAt!.millisecondsSinceEpoch ~/ 1000)}.',
              ),
            ],
          ),
        ),
        // The pager stays pinned under the table: the table scrolls inside
        // its own card, so a pager placed after it would sit below the fold
        // on a tablet and be reachable only by scrolling past every row.
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PlantPager(
            page: page,
            pageSize: _query.pageSize,
            onPageSize: (size) => _update(_query.copyWith(pageSize: size, allRows: size == null, page: 0)),
            onPage: (p) => _update(_query.copyWith(page: p)),
          ),
        ),
      ],
    );
  }
}

/// Shown when the last sync fetched fewer plants than the cloud reported.
class _TruncationWarning extends StatelessWidget {
  const _TruncationWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(child: Text('$message — some plants may be missing from this list.', style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Search a plant by name, id, governorate, district or address',
        border: const OutlineInputBorder(),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// The table, inside horizontal + vertical scroll views, or an empty state.
class _TableCard extends StatelessWidget {
  const _TableCard({required this.page, required this.query, required this.empty, required this.onSort, required this.onClear});

  final PlantPage page;
  final PlantQuery query;

  /// True when the account holds no plant at all (as opposed to no match).
  final bool empty;
  final void Function(PlantSort sort, bool ascending) onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return const SizedBox(
        height: 220,
        child: Card(
          child: EmptyState(
            message: 'No plants yet.\nThe first synchronisation pulls every plant of the DeyeCloud account into this list.',
            icon: Icons.solar_power_outlined,
          ),
        ),
      );
    }
    if (page.rows.isEmpty) {
      return SizedBox(
        height: 220,
        child: Card(
          child: EmptyState(
            message: 'No plant matches the search or the selected counter.',
            icon: Icons.filter_alt_off_outlined,
            action: TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ),
        ),
      );
    }
    // Enough height for the page of rows, capped so the pager stays in view.
    final height = math.min(560.0, 78.0 + page.rows.length * 52.0);
    return SizedBox(
      height: height,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: math.max(320, MediaQuery.sizeOf(context).width - 260)),
              child: PlantTable(
                rows: page.rows,
                query: query,
                onSort: onSort,
                onOpen: (s) => goTo(context, stationRoute(s.id)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
