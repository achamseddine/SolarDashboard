import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/school_insights.dart';
import '../../core/models/school_query.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import 'widgets/school_csv.dart';
import 'widgets/school_filter_bar.dart';
import 'widgets/school_table.dart';

/// Every school in the dataset — the MEHE master list joined with the
/// connectivity roll-out, the solar tracker, the energy audit, the education
/// dashboard and (where one exists) the monitored plant.
class SchoolsDirectoryScreen extends ConsumerStatefulWidget {
  const SchoolsDirectoryScreen({
    super.key,
    this.initialQuery,
    this.initialRegion,
    this.initialCaza,
    this.initialConnected,
    this.initialSolar,
    this.initialMonitored,
    this.initialFilter,
    this.initialMaster,
  });

  final String? initialQuery;
  final String? initialRegion;
  final String? initialCaza;

  /// `1`/`0`: only schools (not) on the internet-connectivity roll-out.
  final String? initialConnected;

  /// `1`/`0`: only (un)solarised schools.
  final String? initialSolar;

  /// `1`/`0`: only schools with (without) a monitored plant.
  final String? initialMonitored;

  /// Named quick filter from another screen: `connected`, `notconnected`,
  /// `solaronly`, `nosolar`, `unmonitored`.
  final String? initialFilter;

  /// `1` when the caller counts master-list schools only.
  final String? initialMaster;

  SchoolQuery get _routeQuery => SchoolQuery.fromRoute(
        query: initialQuery,
        region: initialRegion,
        caza: initialCaza,
        connected: initialConnected,
        solar: initialSolar,
        monitored: initialMonitored,
        filter: initialFilter,
        master: initialMaster,
      );

  @override
  ConsumerState<SchoolsDirectoryScreen> createState() => _SchoolsDirectoryScreenState();
}

class _SchoolsDirectoryScreenState extends ConsumerState<SchoolsDirectoryScreen> {
  late SchoolQuery _query;
  late final TextEditingController _search;

  /// Rows of the unfiltered directory, cached per insights build.
  SchoolInsights? _allSource;
  List<SchoolInsight> _all = const [];

  /// Last loaded rows, kept while the next query resolves so that typing in
  /// the search field does not flash an empty table.
  List<SchoolInsight> _rows = const [];

  @override
  void initState() {
    super.initState();
    _query = widget._routeQuery;
    _search = TextEditingController(text: _query.search);
  }

  @override
  void didUpdateWidget(covariant SchoolsDirectoryScreen old) {
    super.didUpdateWidget(old);
    // A new deep link (e.g. connectivity → "/schools?connected=0") while the
    // screen is already mounted replaces the filters but keeps the sort.
    final changed = old.initialQuery != widget.initialQuery ||
        old.initialRegion != widget.initialRegion ||
        old.initialCaza != widget.initialCaza ||
        old.initialConnected != widget.initialConnected ||
        old.initialSolar != widget.initialSolar ||
        old.initialMonitored != widget.initialMonitored ||
        old.initialFilter != widget.initialFilter ||
        old.initialMaster != widget.initialMaster;
    if (changed) {
      _query = widget._routeQuery.copyWith(sort: _query.sort, ascending: _query.ascending);
      _search.text = _query.search;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(SchoolQuery q) => setState(() => _query = q);

  void _clear() {
    _search.clear();
    _update(SchoolQuery(sort: _query.sort, ascending: _query.ascending));
  }

  /// The directory without any filter (an empty query still drops the 30
  /// records that exist in no source but a secondary workbook).
  List<SchoolInsight> _unfiltered(SchoolInsights? programme) {
    if (programme == null) return const [];
    if (!identical(_allSource, programme)) {
      _allSource = programme;
      _all = const SchoolQuery().apply(programme.schools);
    }
    return _all;
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(schoolDirectoryProvider(_query));
    final programme = ref.watch(schoolInsightsProvider).value;
    final all = _unfiltered(programme);
    if (directory.value != null) _rows = directory.value!;
    final rows = _rows;

    final regionCounts = <String, int>{};
    for (final s in all) {
      regionCounts[s.region] = (regionCounts[s.region] ?? 0) + 1;
    }
    var connected = 0, solarized = 0, monitored = 0;
    for (final s in rows) {
      if (s.isConnected) connected++;
      if (s.isSolarized) solarized++;
      if (s.isMonitored) monitored++;
    }

    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Schools',
            subtitle: _subtitle(rows.length, all.isEmpty ? rows.length : all.length, connected, solarized, monitored),
            actions: [
              Builder(
                builder: (ctx) => FilledButton.tonalIcon(
                  onPressed: rows.isEmpty ? null : () => exportSchoolsCsv(ctx, rows),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              ),
            ],
          ),
          SchoolFilterBar(query: _query, onChanged: _update, searchController: _search, regionCounts: regionCounts, onClear: _clear),
          const SizedBox(height: kGap),
          Expanded(child: _body(directory, rows)),
          MutedNote(_sources(programme, rows.length)),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<List<SchoolInsight>> directory, List<SchoolInsight> rows) {
    if (rows.isEmpty) {
      if (directory.hasError) return ErrorState(message: directory.error.toString());
      if (directory.isLoading) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
      return EmptyState(
        message: 'No school matches the current filters.',
        icon: Icons.filter_alt_off_outlined,
        action: TextButton(onPressed: _clear, child: const Text('Clear filters')),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 260),
            child: SchoolTable(
              rows: rows,
              query: _query,
              onSort: (sort, asc) => _update(_query.copyWith(sort: sort, ascending: asc)),
              onTap: (s) => goTo(context, '/schools/${s.cerd}'),
              onOpenPlant: (s) => goTo(context, '/stations/${s.station!.id}'),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(int shown, int total, int connected, int solarized, int monitored) {
    final base = _query.hasActiveFilter ? '${Fmt.int_(shown)} of ${Fmt.int_(total)} schools' : '${Fmt.int_(total)} schools';
    return '$base · ${Fmt.int_(connected)} with internet · ${Fmt.int_(solarized)} solarised · ${Fmt.int_(monitored)} with a monitored plant';
  }

  String _sources(SchoolInsights? programme, int shown) {
    final capped = shown > SchoolTable.defaultMaxRows ? 'Showing the first ${Fmt.int_(SchoolTable.defaultMaxRows)} of ${Fmt.int_(shown)} matching schools — narrow the filters, or export the CSV for the full list. ' : '';
    final master = programme == null ? '' : ' (${Fmt.int_(programme.publicSchools)} schools)';
    final roll = programme == null ? '' : ' of ${Fmt.int_(programme.connected)} schools';
    return '${capped}School records from the MEHE public school master list$master; the internet column is membership of the connectivity roll-out$roll — a school is on the list or not, with no bandwidth, provider or uptime; '
        'solar data from the UNICEF solar implementation tracker; audited loads from the MEHE energy audit; attendance from the MEHE education dashboard.';
  }
}
