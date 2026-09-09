import 'package:flutter/material.dart';

import '../../../core/models/fleet_insights.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import 'dashboard_common.dart';

/// Governorate roll-up table; row tap → schools list filtered by region.
class RegionTable extends StatelessWidget {
  const RegionTable({super.key, required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final regions = [...insights.regions]..sort((a, b) => b.stations.compareTo(a.stations));
    final num = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    String pct(double? v) => v == null ? 'n/a' : Fmt.ratio(v);
    return SectionCard(
      title: 'Governorates',
      subtitle: 'Tap a row to open the schools of that governorate',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: regions.isEmpty
          ? const EmptyState(message: 'No governorate data yet', icon: Icons.map_outlined)
          : LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 18,
                    columns: const [
                      DataColumn(label: Text('Governorate')),
                      DataColumn(label: Text('Schools'), numeric: true),
                      DataColumn(label: Text('Online'), numeric: true),
                      DataColumn(label: Text('Availability 7 d'), numeric: true),
                      DataColumn(label: Text('kWp'), numeric: true),
                      DataColumn(label: Text('Generation now'), numeric: true),
                      DataColumn(label: Text('Today'), numeric: true),
                      DataColumn(label: Text('Median yield 7 d'), numeric: true),
                      DataColumn(label: Text('Self-suff. 7 d'), numeric: true),
                      DataColumn(label: Text('Alarms'), numeric: true),
                    ],
                    rows: [
                      for (final r in regions)
                        DataRow(
                          onSelectChanged: (_) => goTo(context, stationsRoute(region: r.name)),
                          cells: [
                            DataCell(Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(Fmt.int_(r.stations), style: num)),
                            DataCell(Text('${Fmt.ratio(r.onlineShare)} (${r.online + r.alarm})', style: num)),
                            DataCell(Text(pct(r.availability7d), style: num)),
                            DataCell(Text(Fmt.capacity(r.kwp), style: num)),
                            DataCell(Text(Fmt.power(r.generationNowW), style: num)),
                            DataCell(Text(Fmt.energy(r.todayGenKwh), style: num)),
                            DataCell(Text(r.medianYield7d == null ? 'n/a' : '${Fmt.two(r.medianYield7d)} kWh/kWp', style: num)),
                            DataCell(Text(pct(r.selfSufficiency7d), style: num)),
                            DataCell(Text(Fmt.int_(r.activeAlerts), style: num?.copyWith(fontWeight: r.activeAlerts > 0 ? FontWeight.w700 : null))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
