import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import 'plant_filters.dart';

/// The DeyeCloud counter row (Total · Online · Offline · … · Alerts) as
/// filter chips. The counts always describe the whole account, so they stay
/// readable while a filter is active.
class PlantCounterBar extends StatelessWidget {
  const PlantCounterBar({super.key, required this.counts, required this.selected, required this.onSelected});

  final Map<PlantCounter, int> counts;
  final PlantCounter selected;
  final ValueChanged<PlantCounter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in PlantCounter.values)
          Tooltip(
            message: c.hint,
            child: FilterChip(
              key: ValueKey('plant-counter-${c.name}'),
              selected: selected == c,
              onSelected: (_) => onSelected(c),
              showCheckmark: false,
              avatar: Icon(c.icon, size: 16, color: c.color),
              label: Text('${c.label} ${Fmt.int_(counts[c] ?? 0)}'),
              selectedColor: c.color.withValues(alpha: 0.16),
            ),
          ),
      ],
    );
  }
}
