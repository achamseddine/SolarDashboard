import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/alert.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../nav.dart';

/// Alarms of one plant with acknowledge buttons.
class StationAlertsCard extends ConsumerWidget {
  const StationAlertsCard({super.key, required this.stationId, required this.alerts});
  final int stationId;
  final List<SolarAlert> alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = alerts.where((a) => a.isActive).length;
    return SectionCard(
      title: 'Alarms',
      subtitle: '$active active · ${alerts.length - active} recovered (last ${alerts.length})',
      trailing: TextButton.icon(
        onPressed: () => goTo(context, '/alarms?station=$stationId'),
        icon: const Text('Alarm centre'),
        label: const Icon(Icons.arrow_forward, size: 16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: alerts.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No alarms recorded for this plant'))
          : Column(
              children: [
                for (final a in alerts.take(25)) AlertRow(alert: a, onAcknowledge: a.isActive && !a.acknowledged ? () => _ack(ref, a) : null),
                if (alerts.length > 25) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Showing 25 of ${alerts.length}', style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
    );
  }

  Future<void> _ack(WidgetRef ref, SolarAlert a) async {
    final db = ref.read(databaseProvider);
    await db.alerts.acknowledge(a.id);
    db.notifyChanged(DataKind.alerts);
  }
}

/// One alarm line shared by the station detail and the alarm centre.
class AlertRow extends StatelessWidget {
  const AlertRow({super.key, required this.alert, this.onAcknowledge, this.onOpenStation, this.showStation = false, this.now});
  final SolarAlert alert;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onOpenStation;
  final bool showStation;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final n = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final start = a.startTs ?? a.firstSeenAt;
    final duration = Duration(seconds: ((a.endTs ?? n) - start).clamp(0, 1 << 31));
    final meta = <String>[
      if (showStation && a.stationName != null) a.stationName!,
      if (a.deviceSn != null) '${a.deviceType ?? 'Device'} ${a.deviceSn}',
      if (a.code != null && a.code != a.name) a.code!,
      a.source == AlertSource.cloud ? 'DeyeCloud' : (a.source == AlertSource.derived ? 'derived locally' : 'demo'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: LevelChip(a.level)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, decoration: a.isActive ? null : TextDecoration.lineThrough))),
                    if (a.acknowledged) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.done_all, size: 16, color: scheme.onSurfaceVariant, semanticLabel: 'acknowledged')),
                  ],
                ),
                if (showStation && a.stationName != null && onOpenStation != null)
                  InkWell(onTap: onOpenStation, child: Text(a.stationName!, style: t.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)))
                else
                  Text(meta.join(' · '), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (showStation && onOpenStation != null) Text(meta.skip(1).join(' · '), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (a.description != null) Text(a.description!, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(a.isActive ? 'Active' : 'Recovered', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: a.isActive ? scheme.error : scheme.onSurfaceVariant)),
              Text('${Fmt.dateTime(start)} · ${Fmt.ago(start)}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(a.isActive ? 'open ${Fmt.duration(duration)}' : 'lasted ${Fmt.duration(duration)}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          if (onAcknowledge != null) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: 'Acknowledge', icon: const Icon(Icons.check_circle_outline), onPressed: onAcknowledge),
          ] else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
