import 'package:flutter/material.dart';

import '../../../core/models/station.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../nav.dart';

/// Back button, name, status, master data line and actions.
class StationHeader extends StatelessWidget {
  const StationHeader({
    super.key,
    required this.station,
    required this.status,
    required this.onRefresh,
    this.refreshing = false,
    this.lastError,
    this.invertersOnline,
    this.invertersTotal,
    this.lastUpdateTs,
  });

  final Station station;
  final StationStatus status;
  final VoidCallback onRefresh;
  final bool refreshing;
  final String? lastError;

  /// Inverters reporting, of the inverters known for this plant.
  final int? invertersOnline;
  final int? invertersTotal;

  /// Newest data timestamp, shown the way the cloud console does.
  final int? lastUpdateTs;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final place = [station.region ?? 'Unassigned', ?station.caza, ?station.address].join(' · ');
    final facts = <String>[
      'kWp ${Fmt.capacity(station.installedCapacityKw)}',
      if (invertersTotal != null && invertersTotal! > 0) 'Inverters online ${invertersOnline ?? 0} of $invertersTotal',
      'Last update ${Fmt.dateTime(lastUpdateTs ?? station.lastUpdateTs)}',
      'Battery ${station.batteryCapacityKwh == null ? '–' : Fmt.energy(station.batteryCapacityKwh)}',
      'Commissioned ${Fmt.date(station.startOperatingTs ?? station.createdTs)}',
      'Grid ${Fmt.label(station.gridType)}',
      'Plant id ${station.id}',
      if (station.hasLocation) '${station.lat!.toStringAsFixed(4)}, ${station.lng!.toStringAsFixed(4)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(tooltip: 'Back to schools', icon: const Icon(Icons.arrow_back), onPressed: () => goBack(context)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(station.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      StatusChip(status),
                      if (station.archived) const Chip(label: Text('Archived'), visualDensity: VisualDensity.compact),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(place, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 16,
                    runSpacing: 2,
                    children: [for (final f in facts) Text(f, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]))],
                  ),
                  if (lastError != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: scheme.error),
                        const SizedBox(width: 4),
                        Flexible(child: Text('Last API error: $lastError', style: t.bodySmall?.copyWith(color: scheme.error), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 18),
                  label: Text(refreshing ? 'Refreshing…' : 'Refresh'),
                ),
                OutlinedButton.icon(
                  onPressed: () => goTo(context, '/alarms?station=${station.id}'),
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: const Text('Alarms'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => goTo(context, '/map'),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in map'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
