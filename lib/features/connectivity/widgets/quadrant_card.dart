import 'package:flutter/material.dart';

import '../../../core/models/connectivity_insights.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'connectivity_common.dart';

/// The solar × internet matrix: four tiles and the same four counts as a
/// donut, each tapping through to the matching directory filter.
class SolarInternetCard extends StatelessWidget {
  const SolarInternetCard({super.key, required this.insights});
  final ConnectivityInsights insights;

  static const _order = ConnectivityQuadrant.values;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    return SectionCard(
      title: 'Solar and internet',
      subtitle: 'Every public school in one of four combinations of a solar system and an internet connection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TwoColumn(
            // Below this width the donut and its legend stack under the
            // matrix instead of being squeezed next to it.
            breakpoint: 1150,
            left: Column(
              children: [
                Row(children: [
                  Expanded(child: _QuadrantTile(quadrant: _order[0], insights: d)),
                  const SizedBox(width: kGap),
                  Expanded(child: _QuadrantTile(quadrant: _order[1], insights: d)),
                ]),
                const SizedBox(height: kGap),
                Row(children: [
                  Expanded(child: _QuadrantTile(quadrant: _order[2], insights: d)),
                  const SizedBox(width: kGap),
                  Expanded(child: _QuadrantTile(quadrant: _order[3], insights: d)),
                ]),
              ],
            ),
            right: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DonutChart(
                size: 150,
                centerLabel: 'schools',
                centerValue: Fmt.int_(d.schools),
                slices: [for (final q in _order) (q.label, d.quadrant(q).toDouble(), quadrantColor(q))],
                onTap: (i) => goTo(context, quadrantRoute(_order[i])),
              ),
            ),
          ),
          const MutedNote(
            'The combination decides what the programme can see and what it should do next: a solarised school without internet cannot report to the cloud, '
            'so its plant is invisible until someone visits it, while a connected school without solar is a ready candidate for the next phase — the data path is already there.',
          ),
        ],
      ),
    );
  }
}

/// One combination: count, students, and what it means.
class _QuadrantTile extends StatelessWidget {
  const _QuadrantTile({required this.quadrant, required this.insights});
  final ConnectivityQuadrant quadrant;
  final ConnectivityInsights insights;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = quadrantColor(quadrant);
    return SizedBox(
      height: 150,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => goTo(context, quadrantRoute(quadrant)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(quadrantIcon(quadrant), size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(quadrant.label, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(Fmt.int_(insights.quadrant(quadrant)), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                ),
                Text('${Fmt.int_(insights.quadrantStudentCount(quadrant))} students', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Flexible(child: Text(quadrant.description, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
