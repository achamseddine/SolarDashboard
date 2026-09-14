import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/school_query.dart';
import '../../../core/providers.dart';
import '../../../core/sync/station_region.dart';
import '../../../core/theme.dart';

/// Search field, governorate / district / ownership dropdowns and the quick
/// filter chips of the school directory. Everything lives in a single [Wrap]
/// so the bar reflows instead of overflowing on a 900 px window.
class SchoolFilterBar extends ConsumerWidget {
  const SchoolFilterBar({super.key, required this.query, required this.onChanged, required this.searchController, this.regionCounts = const {}, this.onClear});

  final SchoolQuery query;
  final ValueChanged<SchoolQuery> onChanged;
  final TextEditingController searchController;

  /// Schools per governorate (for the dropdown labels).
  final Map<String, int> regionCounts;

  /// Resets every filter (the screen also clears the search field).
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Districts follow the selected governorate; ownership is dataset-wide.
    final cazas = ref.watch(cazaOptionsProvider(query.region)).value ?? const <(String, int)>[];
    final ownerships = ref.watch(ownershipOptionsProvider).value ?? const <(String, int)>[];
    final caza = cazas.any((c) => c.$1 == query.caza) ? query.caza : null;
    final ownership = ownerships.any((o) => o.$1 == query.ownership) ? query.ownership : null;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: searchController,
            onChanged: (v) => onChanged(query.copyWith(search: v)),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search school, CERD, district, address',
              border: const OutlineInputBorder(),
              suffixIcon: query.search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        onChanged(query.copyWith(search: ''));
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            initialValue: query.region,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Governorate', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All governorates')),
              for (final r in [...LebanonRegions.all, LebanonRegions.unassigned])
                DropdownMenuItem<String?>(value: r, child: Text(regionCounts[r] == null ? r : '$r (${regionCounts[r]})', overflow: TextOverflow.ellipsis)),
            ],
            // A new governorate invalidates the district selection.
            onChanged: (v) => onChanged(v == null ? query.copyWith(clearRegion: true, clearCaza: true) : query.copyWith(region: v, clearCaza: true)),
          ),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<String?>(
            initialValue: caza,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'District (caza)',
              border: const OutlineInputBorder(),
              enabled: cazas.isNotEmpty,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All districts')),
              for (final c in cazas) DropdownMenuItem<String?>(value: c.$1, child: Text('${c.$1} (${c.$2})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: cazas.isEmpty ? null : (v) => onChanged(v == null ? query.copyWith(clearCaza: true) : query.copyWith(caza: v)),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            initialValue: ownership,
            isExpanded: true,
            decoration: InputDecoration(isDense: true, labelText: 'Ownership', border: const OutlineInputBorder(), enabled: ownerships.isNotEmpty),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All buildings')),
              for (final o in ownerships) DropdownMenuItem<String?>(value: o.$1, child: Text('${o.$1} (${o.$2})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: ownerships.isEmpty ? null : (v) => onChanged(v == null ? query.copyWith(clearOwnership: true) : query.copyWith(ownership: v)),
          ),
        ),
        FilterChip(
          avatar: Icon(Icons.wifi, size: 16, color: query.connected == true ? AppColors.good : null),
          label: const Text('Internet'),
          tooltip: 'On the MEHE/UNICEF internet-connectivity roll-out',
          selected: query.connected == true,
          onSelected: (on) => onChanged(on ? query.copyWith(connected: true) : query.copyWith(clearConnected: true)),
        ),
        FilterChip(
          avatar: const Icon(Icons.wifi_off, size: 16),
          label: const Text('No internet'),
          tooltip: 'Not on the connectivity roll-out',
          selected: query.connected == false,
          onSelected: (on) => onChanged(on ? query.copyWith(connected: false) : query.copyWith(clearConnected: true)),
        ),
        FilterChip(
          avatar: Icon(Icons.solar_power_outlined, size: 16, color: query.solarized == true ? AppColors.pv : null),
          label: const Text('Solarised'),
          tooltip: 'Solar system completed (UNICEF solar implementation tracker)',
          selected: query.solarized == true,
          onSelected: (on) => onChanged(on ? query.copyWith(solarized: true) : query.copyWith(clearSolarized: true)),
        ),
        FilterChip(
          avatar: const Icon(Icons.power_off_outlined, size: 16),
          label: const Text('Not solarised'),
          tooltip: 'No completed solar system',
          selected: query.solarized == false,
          onSelected: (on) => onChanged(on ? query.copyWith(solarized: false) : query.copyWith(clearSolarized: true)),
        ),
        FilterChip(
          avatar: const Icon(Icons.sensors, size: 16),
          label: const Text('Monitored plant'),
          tooltip: 'Linked to a DeyeCloud plant the app monitors',
          selected: query.monitored == true,
          onSelected: (on) => onChanged(on ? query.copyWith(monitored: true) : query.copyWith(clearMonitored: true)),
        ),
        FilterChip(
          avatar: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('Energy audit'),
          tooltip: 'Has an audited annual load (MEHE energy audit)',
          selected: query.hasAudit == true,
          onSelected: (on) => onChanged(on ? query.copyWith(hasAudit: true) : query.copyWith(clearAudit: true)),
        ),
        FilterChip(
          avatar: const Icon(Icons.schedule_outlined, size: 16),
          label: const Text('Second shift'),
          tooltip: 'Hosts an afternoon shift',
          selected: query.secondShift == true,
          onSelected: (on) => onChanged(on ? query.copyWith(secondShift: true) : query.copyWith(clearSecondShift: true)),
        ),
        if (query.hasActiveFilter)
          TextButton.icon(
            onPressed: onClear ??
                () {
                  searchController.clear();
                  onChanged(SchoolQuery(sort: query.sort, ascending: query.ascending));
                },
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}
