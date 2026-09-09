import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';

/// Large headline card: one hero figure, context lines, optional meter.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
    required this.valueLabel,
    required this.rows,
    this.meter,
    this.meterLabel,
    this.footnote,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String value;
  final String valueLabel;
  final List<(String, String)> rows;
  final double? meter;
  final String? meterLabel;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.05)),
              ),
              Text(valueLabel, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (meter != null) ...[
                const SizedBox(height: 12),
                RatioMeter(value: meter!, color: color, label: meterLabel),
              ],
              const SizedBox(height: 12),
              const Divider(),
              for (final r in rows) InfoRow(r.$1, r.$2),
              if (footnote != null) ...[
                const SizedBox(height: 6),
                Text(footnote!, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The three headline cards of the landing page.
class HeroRow extends StatelessWidget {
  const HeroRow({super.key, required this.insights, this.onGeneration, this.onConsumption, this.onCarbon});
  final FleetInsights insights;
  final VoidCallback? onGeneration;
  final VoidCallback? onConsumption;
  final VoidCallback? onCarbon;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final p = ChartPalette.of(context);
    final live = i.reportingStations > 0;
    final asOf = i.dataTsMax == null ? 'no live data yet' : 'now · as of ${Fmt.time(i.dataTsMax)} · ${i.reportingStations} of ${i.totalStations} schools reporting';
    final cars = i.co2AvoidedLifetimeKg / 4600; // US EPA: 4.6 t CO₂ per passenger vehicle per year.
    final cards = [
      HeroCard(
        title: 'Power generation',
        icon: Icons.wb_sunny_outlined,
        color: p.pv,
        value: live ? Fmt.power(i.generationNowW) : '–',
        valueLabel: asOf,
        meter: i.capacityUtilisation,
        meterLabel: live ? '${Fmt.ratio(i.capacityUtilisation)} of ${Fmt.capacity(i.reportingKwp)} reporting capacity' : 'Installed ${Fmt.capacity(i.installedKwp)}',
        rows: [
          ('Today', Fmt.energy(i.today.generationKwh)),
          ('Last 7 days', Fmt.energy(i.last7d.generationKwh)),
          ('Last 30 days', Fmt.energy(i.last30d.generationKwh)),
          ('Since commissioning', Fmt.energy(i.lifetime.generationKwh)),
        ],
        footnote: 'All ${i.totalStations} schools · ${Fmt.capacity(i.installedKwp)} installed',
        onTap: onGeneration,
      ),
      HeroCard(
        title: 'Power consumption',
        icon: Icons.bolt_outlined,
        color: p.load,
        value: live ? Fmt.power(i.consumptionNowW) : '–',
        valueLabel: live ? 'now · grid import ${Fmt.power(i.importNowW)} · export ${Fmt.power(i.exportNowW)}' : asOf,
        meter: i.selfSufficiencyToday,
        meterLabel: 'Self-sufficiency today ${i.selfSufficiencyToday == null ? 'n/a' : Fmt.ratio(i.selfSufficiencyToday)} (share not bought from the grid)',
        rows: [
          ('Today', Fmt.energy(i.today.consumptionKwh)),
          ('Last 7 days', Fmt.energy(i.last7d.consumptionKwh)),
          ('Last 30 days', Fmt.energy(i.last30d.consumptionKwh)),
          ('Since commissioning', Fmt.energy(i.lifetime.consumptionKwh)),
        ],
        footnote: '30-day self-sufficiency ${i.selfSufficiency30d == null ? 'n/a' : Fmt.ratio(i.selfSufficiency30d)} · grid import ${Fmt.energy(i.last30d.gridImportKwh)}',
        onTap: onConsumption,
      ),
      HeroCard(
        title: 'Carbon footprint avoided',
        icon: Icons.eco_outlined,
        color: AppColors.good,
        value: Fmt.co2(i.co2AvoidedLifetimeKg),
        valueLabel: 'since commissioning · ${Fmt.litres(i.dieselAvoidedLifetimeL)} of diesel not burnt',
        rows: [
          ('Today', Fmt.co2(i.co2AvoidedTodayKg)),
          ('Last 30 days', Fmt.co2(i.co2Avoided30dKg)),
          ('Diesel avoided, 30 days', Fmt.litres(i.dieselAvoided30dL)),
          ('≈ cars off the road for a year', Fmt.one(cars)),
        ],
        footnote: 'Self-consumed solar × ${i.co2FactorKgPerKwh.toStringAsFixed(2)} kg CO₂/kWh and ${i.dieselLitresPerKwh.toStringAsFixed(2)} L/kWh (Settings); 4.6 t CO₂ per car-year (US EPA)',
        onTap: onCarbon,
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: kGap), child: card)]);
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < cards.length; k++) ...[
              if (k > 0) const SizedBox(width: kGap),
              Expanded(child: cards[k]),
            ],
          ],
        ),
      );
    });
  }
}
