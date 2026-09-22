import 'package:flutter/material.dart';

import 'plant_filters.dart';

/// Page-size selector, previous/next and the "Showing A–B of N" line, like
/// the paging strip of the DeyeCloud console.
class PlantPager extends StatelessWidget {
  const PlantPager({super.key, required this.page, required this.pageSize, required this.onPageSize, required this.onPage});

  final PlantPage page;

  /// Rows per page; `null` is the "All" entry.
  final int? pageSize;
  final ValueChanged<int?> onPageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rows per page', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            for (final size in PlantQuery.pageSizes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('plant-page-size-${size ?? 'all'}'),
                  selected: pageSize == size,
                  onSelected: (_) => onPageSize(size),
                  showCheckmark: false,
                  label: Text(size == null ? 'All' : '$size'),
                ),
              ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(page.rangeLabel, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            IconButton(
              key: const ValueKey('plant-page-previous'),
              onPressed: page.hasPrevious ? () => onPage(page.page - 1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
            ),
            Text(page.pageLabel, style: t.bodyMedium),
            IconButton(
              key: const ValueKey('plant-page-next'),
              onPressed: page.hasNext ? () => onPage(page.page + 1) : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
            ),
          ],
        ),
      ],
    );
  }
}
