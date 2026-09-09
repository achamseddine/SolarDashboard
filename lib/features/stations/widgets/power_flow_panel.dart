import 'package:flutter/material.dart';

import '../../../core/models/station.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';

/// Boxed live power-flow diagram: PV → (load, battery, grid) with values,
/// direction arrows and a SOC meter. Direction is always spelled out in text.
class PowerFlowPanel extends StatelessWidget {
  const PowerFlowPanel({super.key, required this.latest, this.staleAfterMinutes = 30});

  final StationLatest? latest;
  final int staleAfterMinutes;

  @override
  Widget build(BuildContext context) {
    final snap = latest?.snapshot;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ts = latest?.dataTs;
    final ageSec = ts == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts;
    final stale = ageSec != null && ageSec > staleAfterMinutes * 60;
    return SectionCard(
      title: 'Power flow',
      subtitle: ts == null ? 'No live data yet' : 'Data ${Fmt.dateTime(ts)} · ${Fmt.ago(ts)}${latest?.source == null ? '' : ' · ${latest!.source.name}'}',
      trailing: stale
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.stale),
              const SizedBox(width: 4),
              Text('Stale', style: t.labelMedium?.copyWith(color: AppColors.stale, fontWeight: FontWeight.w600)),
            ])
          : null,
      child: snap == null || snap.isEmpty
          ? const SizedBox(height: 220, child: EmptyState(message: 'No power readings yet for this school', icon: Icons.bolt_outlined))
          : Center(child: FittedBox(fit: BoxFit.scaleDown, child: _Diagram(snap: snap, muted: scheme.onSurfaceVariant))),
    );
  }
}

class _Diagram extends StatelessWidget {
  const _Diagram({required this.snap, required this.muted});
  final StationSnapshot snap;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final p = ChartPalette.of(context);
    final pv = snap.generationW;
    final load = snap.consumptionW;
    final gridNet = snap.gridNetW; // + import, − export
    final batNet = snap.batteryNetW; // + charging, − discharging
    final soc = snap.batterySoc;

    final importing = gridNet > 5;
    final exporting = gridNet < -5;
    final charging = batNet > 5;
    final discharging = batNet < -5;

    final gridColor = importing ? p.gridImport : (exporting ? p.gridExport : muted);
    final gridLabel = importing ? 'Importing' : (exporting ? 'Exporting' : 'Idle');
    final batColor = charging || discharging ? p.battery : muted;
    final batLabel = charging ? 'Charging' : (discharging ? 'Discharging' : 'Idle');

    const boxW = 150.0;
    return Column(
      children: [
        _Node(icon: Icons.wb_sunny_outlined, title: 'PV', value: Fmt.power(pv), color: pv != null && pv > 5 ? p.pv : muted, width: boxW, hint: pv != null && pv > 5 ? 'Generating' : 'No generation'),
        _Arrow(direction: AxisDirection.down, active: pv != null && pv > 5, color: p.pv),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Node(
              icon: Icons.electrical_services_outlined,
              title: 'Grid (EDL)',
              value: Fmt.power(gridNet.abs()),
              color: gridColor,
              width: boxW,
              hint: gridLabel,
            ),
            _Arrow(direction: importing ? AxisDirection.right : AxisDirection.left, active: importing || exporting, color: gridColor),
            _Node(icon: Icons.home_outlined, title: 'Inverter', value: '', color: p.accent, width: 110, hint: 'Hybrid'),
            _Arrow(direction: AxisDirection.right, active: load != null && load > 5, color: p.load),
            _Node(icon: Icons.lightbulb_outline, title: 'Load', value: Fmt.power(load), color: load != null && load > 5 ? p.load : muted, width: boxW, hint: 'School consumption'),
          ],
        ),
        _Arrow(direction: charging ? AxisDirection.down : AxisDirection.up, active: charging || discharging, color: batColor),
        _Node(
          icon: charging ? Icons.battery_charging_full : Icons.battery_std_outlined,
          title: 'Battery',
          value: Fmt.power(batNet.abs()),
          color: batColor,
          width: 220,
          hint: batLabel,
          footer: soc == null
              ? Text('SOC –', style: Theme.of(context).textTheme.labelSmall)
              : RatioMeter(value: soc / 100, color: p.socColor(soc), label: 'SOC ${Fmt.percent(soc)}${soc < 20 ? ' · low' : ''}'),
        ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.title, required this.value, required this.color, required this.width, this.hint, this.footer});
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final double width;
  final String? hint;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(title, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis))]),
          if (value.isNotEmpty) Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          if (hint != null) Text(hint!, style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (footer != null) Padding(padding: const EdgeInsets.only(top: 6), child: footer),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.direction, required this.active, required this.color});
  final AxisDirection direction;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = active ? color : Theme.of(context).colorScheme.outlineVariant;
    final vertical = direction == AxisDirection.up || direction == AxisDirection.down;
    final icon = switch (direction) {
      AxisDirection.up => Icons.arrow_upward,
      AxisDirection.down => Icons.arrow_downward,
      AxisDirection.left => Icons.arrow_back,
      AxisDirection.right => Icons.arrow_forward,
    };
    final line = Container(width: vertical ? 2 : 18, height: vertical ? 10 : 2, color: c);
    final children = [line, Icon(active ? icon : Icons.remove, size: 18, color: c), line];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: vertical ? 0 : 4, vertical: vertical ? 2 : 0),
      child: vertical ? Column(mainAxisSize: MainAxisSize.min, children: children) : Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
