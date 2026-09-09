import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// CO₂ and diesel avoided (today · 30 d · lifetime) with the formula tooltip.
class EnvironmentCard extends StatelessWidget {
  const EnvironmentCard({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final formula = 'Avoided emissions are computed from self-consumed generation only '
        '(generation − grid export):\n'
        'CO₂ avoided = self-consumed kWh × ${Fmt.two(i.co2FactorKgPerKwh)} kg CO₂/kWh\n'
        'Diesel avoided = self-consumed kWh × ${Fmt.two(i.dieselLitresPerKwh)} L/kWh\n'
        'Both factors can be changed in Settings → Display.';
    final rows = [
      ('Today', i.today.selfConsumedKwh, i.co2AvoidedTodayKg, i.today.selfConsumedKwh * i.dieselLitresPerKwh),
      ('Last 30 days', i.last30d.selfConsumedKwh, i.co2Avoided30dKg, i.dieselAvoided30dL),
      ('Lifetime', i.lifetime.selfConsumedKwh, i.co2AvoidedLifetimeKg, i.dieselAvoidedLifetimeL),
    ];
    return SectionCard(
      title: 'Environmental impact',
      subtitle: 'Self-consumed generation × factor',
      trailing: Tooltip(
        message: formula,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 8),
        child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.info_outline, size: 20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox(),
                  for (final h in ['Self-consumed', 'CO₂ avoided', 'Diesel avoided']) Text(h, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.right),
                ],
              ),
              for (final r in rows)
                TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r.$1, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    _Num(Fmt.energy(r.$2)),
                    _Num(Fmt.co2(r.$3), color: AppColors.good),
                    _Num(Fmt.litres(r.$4)),
                  ],
                ),
            ],
          ),
          MutedNote('Factors: ${Fmt.two(i.co2FactorKgPerKwh)} kg CO₂/kWh · ${Fmt.two(i.dieselLitresPerKwh)} L diesel/kWh · self-consumption 30 d ${i.selfConsumption30d == null ? 'n/a' : Fmt.ratio(i.selfConsumption30d)}'),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, textAlign: TextAlign.right, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
      );
}
