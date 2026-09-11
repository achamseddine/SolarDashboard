import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Colour of a programme status (same scale everywhere on the page).
Color solarStatusColor(SolarStatus s) => switch (s) {
      SolarStatus.completed => AppColors.good,
      SolarStatus.planned => AppColors.unicefCyan,
      SolarStatus.onHold => AppColors.warning,
      SolarStatus.unfunded => AppColors.serious,
      SolarStatus.notSolarized => AppColors.muted,
    };

/// `USD 1,234,567` — full figure with thousands separators.
String usd(double? v) => v == null ? '–' : 'USD ${Fmt.int_(v)}';

/// `USD 1.2 M`, `USD 340 k` — compact figure for trailing texts.
String usdCompact(double? v) {
  if (v == null) return '–';
  final a = v.abs();
  if (a >= 1e6) return 'USD ${Fmt.one(v / 1e6)} M';
  if (a >= 1e3) return 'USD ${Fmt.int_(v / 1e3)} k';
  return 'USD ${Fmt.int_(v)}';
}

/// `12.3 GWh`, `4.5 MWh`, `812 kWh` — one decimal, fits a donut centre.
String energyCompact(double? kwh) {
  if (kwh == null) return '–';
  final a = kwh.abs();
  if (a >= 1e6) return '${Fmt.one(kwh / 1e6)} GWh';
  if (a >= 1e3) return '${Fmt.one(kwh / 1e3)} MWh';
  return '${Fmt.int_(kwh)} kWh';
}

/// Small label / value fact used inside programme cards (not a nested card).
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.label, required this.value, this.hint, this.color, this.width = 170});

  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (hint != null) Text(hint!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Wrapping row of [FactTile]s.
class FactWrap extends StatelessWidget {
  const FactWrap({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 20, runSpacing: 12, children: children);
}

/// Card holding a counted list: `title · count`, "Showing n of m", an empty
/// line when there is nothing to show and an optional muted note.
class ProgrammeListCard extends StatelessWidget {
  const ProgrammeListCard({
    super.key,
    required this.title,
    required this.count,
    required this.emptyText,
    required this.rows,
    this.subtitle,
    this.trailing,
    this.note,
    this.emptyIcon = Icons.check_circle_outline,
    this.emptyColor = AppColors.good,
  });

  final String title;
  final int count;
  final String? subtitle;
  final Widget? trailing;
  final String emptyText;
  final List<Widget> rows;
  final String? note;
  final IconData emptyIcon;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '$title · $count',
      subtitle: count > rows.length ? 'Showing ${rows.length} of $count${subtitle == null ? '' : ' · $subtitle'}' : subtitle,
      trailing: trailing,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(emptyIcon, size: 18, color: emptyColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(emptyText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ),
            )
          else
            ...rows,
          if (note != null) MutedNote(note!),
        ],
      ),
    );
  }
}
