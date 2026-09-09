import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/station.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Fleet-wide PV / load / import / export over the last 24 h (15-min buckets)
/// with a small signed battery chart underneath and a table twin.
class FleetPowerCard extends ConsumerWidget {
  const FleetPowerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(powerBucketsProvider(('', 24)));
    final p = ChartPalette.of(context);
    final data = buckets.value;
    if (data == null || data.isEmpty) {
      return SectionCard(
        title: 'Fleet power today',
        subtitle: 'Sum over reporting plants, 15-min buckets',
        child: SizedBox(
          height: 240,
          child: AsyncView<List<PowerBucket>>(
            value: buckets,
            emptyWhen: (b) => b.isEmpty,
            emptyMessage: 'No fleet power buckets yet – they appear after the first sync.',
            builder: (_) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    return Builder(
      builder: (context) {
        final b = data;
        final sorted = [...b]..sort((x, y) => x.bucketTs.compareTo(y.bucketTs));
        final series = [
          TimeSeries(label: 'PV', color: p.pv, area: true, points: [for (final x in sorted) (x.bucketTs, x.generationW)]),
          TimeSeries(label: 'Load', color: p.load, points: [for (final x in sorted) (x.bucketTs, x.consumptionW)]),
          TimeSeries(label: 'Grid import', color: p.gridImport, points: [for (final x in sorted) (x.bucketTs, x.gridImportW)]),
          TimeSeries(label: 'Grid export', color: p.gridExport, points: [for (final x in sorted) (x.bucketTs, x.gridExportW)]),
        ];
        final battery = TimeSeries(label: 'Battery (+ charge / − discharge)', color: p.battery, points: [for (final x in sorted) (x.bucketTs, x.chargeW - x.dischargeW)]);
        final hasBattery = sorted.any((x) => x.chargeW != 0 || x.dischargeW != 0);
        final last = sorted.last;
        return ChartOrTable(
          title: 'Fleet power today',
          subtitle: 'Sum over reporting plants, 15-min buckets · ${Fmt.time(sorted.first.bucketTs)}–${Fmt.time(last.bucketTs)} · ${last.stationsReporting} plants in last bucket',
          chart: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PowerLineChart(series: series, height: 240),
              if (hasBattery) ...[
                const SizedBox(height: 12),
                Text('Battery power', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                PowerLineChart(series: [battery], height: 90, showLegend: false),
                const MutedNote('Positive = charging, negative = discharging'),
              ],
            ],
          ),
          table: ChartTable(
            columns: const ['Time', 'PV', 'Load', 'Import', 'Export', 'Battery', 'Plants'],
            rows: [
              for (final x in sorted.reversed)
                [Fmt.time(x.bucketTs), Fmt.power(x.generationW), Fmt.power(x.consumptionW), Fmt.power(x.gridImportW), Fmt.power(x.gridExportW), Fmt.power(x.chargeW - x.dischargeW, signed: true), Fmt.int_(x.stationsReporting)],
            ],
          ),
        );
      },
    );
  }
}
