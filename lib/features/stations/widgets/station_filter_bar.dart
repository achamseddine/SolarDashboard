import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../station_filters.dart';

/// Search field, region dropdown, status chips, quick filters and sort menu.
class StationFilterBar extends StatelessWidget {
  const StationFilterBar({super.key, required this.filter, required this.onChanged, required this.searchController, this.regionCounts = const {}, this.schools = const {}});

  final StationFilter filter;
  final ValueChanged<StationFilter> onChanged;
  final TextEditingController searchController;

  /// Stations per region (for the dropdown labels).
  final Map<String, int> regionCounts;

  /// Station id → linked MEHE school (for the chip tooltips).
  final Map<int, School> schools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linkedCount = schools.length;
    final connectedCount = schools.values.where((s) => s.connected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: searchController,
                onChanged: (v) => onChanged(filter.copyWith(query: v)),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search school, CERD, address, caza…',
                  border: const OutlineInputBorder(),
                  suffixIcon: filter.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            searchController.clear();
                            onChanged(filter.copyWith(query: ''));
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: filter.region,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Governorate', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All governorates')),
                  for (final r in stationRegionOptions)
                    DropdownMenuItem<String?>(value: r, child: Text(regionCounts[r] == null ? r : '$r (${regionCounts[r]})', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => onChanged(v == null ? filter.copyWith(clearRegion: true) : filter.copyWith(region: v)),
              ),
            ),
            const SizedBox(width: 12),
            _SortMenu(filter: filter, onChanged: onChanged),
            const Spacer(),
            if (filter.hasActiveFilter)
              TextButton.icon(
                onPressed: () {
                  searchController.clear();
                  onChanged(StationFilter(sort: filter.sort, ascending: filter.ascending));
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Status', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
            for (final s in StationStatus.values)
              FilterChip(
                avatar: Icon(AppColors.stationStatusIcon(s), size: 16, color: AppColors.stationStatus(s)),
                label: Text(s.label),
                selected: filter.status == s,
                onSelected: (on) => onChanged(on ? filter.copyWith(status: s) : filter.copyWith(clearStatus: true)),
              ),
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.notifications_active_outlined, size: 16),
              label: const Text('With alarms'),
              selected: filter.withAlarms,
              onSelected: (on) => onChanged(filter.copyWith(withAlarms: on)),
            ),
            FilterChip(
              avatar: const Icon(Icons.trending_down, size: 16),
              label: const Text('Under-performing'),
              tooltip: 'Yield 7 d below half of the peer median',
              selected: filter.underPerforming,
              onSelected: (on) => onChanged(filter.copyWith(underPerforming: on)),
            ),
            FilterChip(
              avatar: const Icon(Icons.battery_alert_outlined, size: 16),
              label: const Text('Low SOC'),
              tooltip: 'Battery below 20 %',
              selected: filter.lowSoc,
              onSelected: (on) => onChanged(filter.copyWith(lowSoc: on)),
            ),
            FilterChip(
              avatar: Icon(Icons.wifi, size: 16, color: filter.connected == true ? AppColors.good : null),
              label: const Text('Connected'),
              tooltip: '$connectedCount plants at schools on the MEHE/UNICEF internet-connectivity roll-out',
              selected: filter.connected == true,
              onSelected: (on) => onChanged(on ? filter.copyWith(connected: true) : filter.copyWith(clearConnected: true)),
            ),
            FilterChip(
              avatar: const Icon(Icons.school_outlined, size: 16),
              label: const Text('Linked to school'),
              tooltip: '$linkedCount plants matched to a MEHE public-school record (by name and coordinates, or set by hand)',
              selected: filter.linked == true,
              onSelected: (on) => onChanged(on ? filter.copyWith(linked: true) : filter.copyWith(clearLinked: true)),
            ),
          ],
        ),
      ],
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.filter, required this.onChanged});
  final StationFilter filter;
  final ValueChanged<StationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<StationSort>(
          tooltip: 'Sort by',
          initialValue: filter.sort,
          onSelected: (s) => onChanged(filter.copyWith(sort: s)),
          itemBuilder: (_) => [for (final s in StationSort.values) PopupMenuItem(value: s, child: Text(s.label))],
          child: OutlinedButton.icon(
            onPressed: null,
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface, disabledForegroundColor: Theme.of(context).colorScheme.onSurface),
            icon: const Icon(Icons.sort, size: 18),
            label: Text('Sort: ${filter.sort.label}'),
          ),
        ),
        IconButton(
          tooltip: filter.ascending ? 'Ascending (tap for descending)' : 'Descending (tap for ascending)',
          icon: Icon(filter.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 20),
          onPressed: () => onChanged(filter.copyWith(ascending: !filter.ascending)),
        ),
      ],
    );
  }
}
