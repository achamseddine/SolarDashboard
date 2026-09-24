import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/alert.dart';
import '../../core/models/device.dart';
import '../../core/models/station.dart';
import '../../core/theme.dart';

/// Page padding used by every screen.
const kPagePadding = EdgeInsets.fromLTRB(20, 12, 20, 24);
const kGap = 12.0;

/// Card with an optional title row and trailing action.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
    return Card(child: onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: body));
  }
}

/// Key-figure tile: big value, label, optional delta/hint and accent colour.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.hint, this.icon, this.color, this.onTap, this.dense = false});

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 10 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: Text(label, style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              SizedBox(height: dense ? 2 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: (dense ? t.titleLarge : t.headlineSmall)?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Flexible(child: Text(hint!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured dot + label for plant status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.compact = false});
  final StationStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.stationStatus(status);
    return _Pill(color: c, label: compact ? status.label.split(' ').first : status.label);
  }
}

class DeviceStatusChip extends StatelessWidget {
  const DeviceStatusChip(this.status, {super.key});
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) => _Pill(color: AppColors.deviceStatus(status), label: status.label);
}

/// Alarm level pill.
class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key});
  final AlertLevel level;

  @override
  Widget build(BuildContext context) => _Pill(color: AppColors.alertLevel(level), label: level.label);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Small coloured square + text, for chart legends.
class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.color, required this.label, this.value});
  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        // A series name can be long (an SSID, a school); it ellipsizes rather
        // than pushing the value out of the row.
        Flexible(child: Text(label, style: t.labelMedium, softWrap: false, overflow: TextOverflow.ellipsis)),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(value!, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

/// Renders an [AsyncValue] with consistent loading / error / empty states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.emptyWhen, this.emptyMessage = 'No data yet'});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final bool Function(T data)? emptyWhen;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (d) => emptyWhen != null && emptyWhen!(d) ? EmptyState(message: emptyMessage) : builder(d),
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, st) => ErrorState(message: e.toString()),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => EmptyState(message: message, icon: Icons.error_outline);
}

/// Responsive grid of equally sized tiles with a fixed tile height.
///
/// [aspect] is kept for API compatibility but the tile height is governed by
/// [tileHeight] so multi-line hints never overflow.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 190, this.aspect = 1.9, this.gap = kGap, this.tileHeight});
  final List<Widget> children;
  final double minTileWidth;
  final double aspect;
  final double gap;
  final double? tileHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 8);
      final height = tileHeight ?? (aspect >= 2.4 ? 88.0 : 118.0);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: height, mainAxisSpacing: gap, crossAxisSpacing: gap),
        itemCount: children.length,
        itemBuilder: (_, i) => children[i],
      );
    });
  }
}

/// Two-column row that collapses to one column on narrow widths.
class TwoColumn extends StatelessWidget {
  const TwoColumn({super.key, required this.left, required this.right, this.leftFlex = 1, this.rightFlex = 1, this.breakpoint = 900});
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: kGap), right]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(flex: leftFlex, child: left), const SizedBox(width: kGap), Expanded(flex: rightFlex, child: right)],
      );
    });
  }
}

/// Label/value line used in detail panels.
///
/// With [onTap] the whole line becomes a target and grows a chevron, so a
/// figure in a card reads as something that can be opened.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor, this.onTap});
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 4, horizontal: onTap == null ? 0 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Expanded(flex: 3, child: Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: valueColor), textAlign: TextAlign.right)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: row);
  }
}

/// Page header with title, subtitle and actions.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) Text(subtitle!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
