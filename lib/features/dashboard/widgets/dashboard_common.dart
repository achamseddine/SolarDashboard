import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigates with go_router when a router is present (widget tests pump the
/// screen without one, so a missing router is a no-op rather than a crash).
void goTo(BuildContext context, String location) {
  final router = GoRouter.maybeOf(context);
  if (router != null) router.go(location);
}

String stationRoute(int id) => '/stations/$id';

String stationsRoute({String? status, String? region, String? filter}) {
  final q = <String, String>{
    'status': ?status,
    'region': ?region,
    'filter': ?filter,
  };
  return Uri(path: '/stations', queryParameters: q.isEmpty ? null : q).toString();
}

/// "See all →" text button used by the attention cards.
class SeeAllButton extends StatelessWidget {
  const SeeAllButton({super.key, required this.location, this.label = 'See all'});
  final String location;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => goTo(context, location),
        icon: Text(label),
        label: const Icon(Icons.arrow_forward, size: 16),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      );
}

/// Compact tappable row (≥ 44 px) used by lists on the dashboard.
class CompactRow extends StatelessWidget {
  const CompactRow({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.trailingHint, this.onTap});

  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? trailingHint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trailing!, style: t.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    if (trailingHint != null) Text(trailingHint!, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small muted note under a chart or list ("as of", "n/a", …).
class MutedNote extends StatelessWidget {
  const MutedNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// Lays out up to four cards side by side on wide screens, 2×2 otherwise.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.children, this.breakpoint = 1000});
  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth >= breakpoint ? children.length : (children.length / 2).ceil().clamp(1, 2);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += perRow) {
        final slice = children.sublist(i, (i + perRow).clamp(0, children.length));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < slice.length; j++) ...[
              if (j > 0) const SizedBox(width: 12),
              Expanded(child: slice[j]),
            ],
            for (var j = slice.length; j < perRow; j++) ...[const SizedBox(width: 12), const Expanded(child: SizedBox())],
          ],
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 12), rows[i]],
        ],
      );
    });
  }
}
