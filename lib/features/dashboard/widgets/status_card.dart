import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Status donut (tap a slice → filtered school list) + data-age histogram.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final statuses = StationStatus.values.where((s) => insights.count(s) > 0).toList();
    final slices = [for (final s in statuses) (s.label, insights.count(s).toDouble(), AppColors.stationStatus(s))];
    final age = insights.dataAgeHistogram.entries.toList();
    return SectionCard(
      title: 'Plant status',
      subtitle: '${insights.reportingStations} of ${insights.totalStations} reporting within the stale threshold',
      trailing: SeeAllButton(location: stationsRoute(), label: 'All schools'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slices.isEmpty)
            const SizedBox(height: 160, child: EmptyState(message: 'No schools yet', icon: Icons.donut_large_outlined))
          else
            DonutChart(
              slices: slices,
              centerValue: Fmt.int_(insights.totalStations),
              centerLabel: 'schools',
              onTap: (i) => goTo(context, stationsRoute(status: statuses[i].name)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in statuses)
                InkWell(
                  onTap: () => goTo(context, stationsRoute(status: s.name)),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(AppColors.stationStatusIcon(s), size: 14, color: AppColors.stationStatus(s)), const SizedBox(width: 4), StatusChip(s, compact: true)],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Age of newest data', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          HorizontalBars(
            items: [for (final e in age) (e.key, e.value.toDouble(), null)],
            formatter: (v) => Fmt.int_(v),
            barHeight: 12,
          ),
          if (insights.stationsWithErrors > 0) MutedNote('${insights.stationsWithErrors} plants returned API errors on the last sweep'),
        ],
      ),
    );
  }
}
