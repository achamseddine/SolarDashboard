import 'package:flutter/material.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Month-to-date part-to-whole view of one plant — the "Solar & Utilization"
/// block of the DeyeCloud plant overview.
///
/// Left donut: where the consumption came from (battery, PV direct, grid).
/// Right donut: where the production went (battery, load, grid feed-in).
/// Both splits are derived from the daily counters, so they only add up when
/// the plant reports every counter.
class SolarUtilisationCard extends StatelessWidget {
  const SolarUtilisationCard({super.key, required this.detail});

  final StationDetail detail;

  static const _donutSize = 150.0;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final m = detail.monthToDate;
    final consumption = _atLeastZero(m.consumptionKwh);
    final production = _atLeastZero(m.generationKwh);
    final discharge = _atLeastZero(m.dischargeKwh);
    final charge = _atLeastZero(m.chargeKwh);
    final import_ = _atLeastZero(m.gridImportKwh);
    final export_ = _atLeastZero(m.gridExportKwh);

    if (consumption <= 0 && production <= 0) {
      return const SectionCard(
        title: 'Solar & utilisation',
        subtitle: 'Where this month\'s consumption came from and where its production went',
        child: EmptyState(message: 'The donuts appear once the plant reports a full day of energy counters this month.', icon: Icons.donut_large_outlined),
      );
    }

    // Large plants can run into the millions of kWh: the donut legend prints
    // whole numbers, so switch both donuts to MWh together to keep them
    // comparable (and the labels short).
    final inMwh = consumption >= 1e6 || production >= 1e6;
    final unit = inMwh ? 'MWh' : 'kWh';
    double scale(double kwh) => inMwh ? kwh / 1e3 : kwh;

    final pvDirect = _atLeastZero(consumption - discharge - import_);
    final selfUsed = _atLeastZero(production - charge - export_);

    return SectionCard(
      title: 'Solar & utilisation',
      subtitle: 'Where this month\'s consumption came from and where its production went',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TwoColumn(
            left: _Donut(
              title: 'Where the consumption came from',
              total: consumption,
              centerLabel: 'consumed',
              slices: [
                ('Discharge ($unit)', scale(discharge), p.battery),
                ('PV direct ($unit)', scale(pvDirect), p.pv),
                ('Grid ($unit)', scale(import_), p.gridImport),
              ],
            ),
            right: _Donut(
              title: 'Where the production went',
              total: production,
              centerLabel: 'produced',
              slices: [
                ('Charge ($unit)', scale(charge), p.battery),
                ('Consumption ($unit)', scale(selfUsed), p.load),
                ('Grid feed-in ($unit)', scale(export_), p.gridExport),
              ],
            ),
          ),
          const MutedNote('Month to date, from the daily energy counters. The split is derived from those counters, so it is an approximation when the plant does not report every counter — the slices then no longer add up to the measured total.'),
        ],
      ),
    );
  }

  static double _atLeastZero(double v) => v.isNaN || v < 0 ? 0 : v;
}

/// One donut with its heading; the legend (value + share per slice) is the
/// shared [DonutChart] legend.
class _Donut extends StatelessWidget {
  const _Donut({required this.title, required this.slices, required this.total, required this.centerLabel});

  final String title;
  final List<(String, double, Color)> slices;

  /// Total in kWh, shown in the centre (the slices may carry MWh).
  final double total;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final centre = Fmt.energy(total).split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DonutChart(
          size: SolarUtilisationCard._donutSize,
          slices: slices,
          centerValue: centre.first,
          centerLabel: '${centre.last} $centerLabel',
        ),
      ],
    );
  }
}
