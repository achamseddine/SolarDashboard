import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/deye_api_client.dart';
import '../../../core/models/sync.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';

/// Sync status, sync log, database statistics and the app log.
class DiagnosticsCard extends ConsumerWidget {
  const DiagnosticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final logs = ref.watch(syncLogsProvider);
    final stats = ref.watch(dbStatsProvider);
    final appLog = ref.watch(appLogProvider);
    final api = ref.watch(apiProvider);
    final t = Theme.of(context).textTheme;
    final engine = ref.read(syncEngineProvider);
    return SectionCard(
      title: 'Diagnostics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Synchronisation', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          InfoRow('State', status.running ? '${status.phase.label} ${status.total > 0 ? '${status.current}/${status.total}' : ''}' : (status.pausedUntil != null ? 'Paused until ${Fmt.time(status.pausedUntil!.millisecondsSinceEpoch ~/ 1000)}' : 'Idle')),
          InfoRow('Last successful sweep', status.lastSuccessAt == null ? 'never' : '${Fmt.dateTime(status.lastSuccessAt!.millisecondsSinceEpoch ~/ 1000)} (${Fmt.ago(status.lastSuccessAt!.millisecondsSinceEpoch ~/ 1000)})'),
          InfoRow('Last error', status.lastError ?? '–'),
          InfoRow('Phase failures (last sweep)', engine.lastPhaseFailures.isEmpty ? 'none' : engine.lastPhaseFailures.join('; ')),
          InfoRow('Errors counted', Fmt.int_(status.errorCount)),
          InfoRow('API requests this session', Fmt.int_(status.requestCount)),
          InfoRow('Data source', api is DeyeApiClient ? 'DeyeCloud ${api.credentials.region.name.toUpperCase()}' : 'Demo generator'),
          if (api is DeyeApiClient) ...[
            InfoRow('Alert endpoint (station)', api.stationAlertPath ?? (api.alertsUnsupported ? 'unavailable' : 'not probed yet')),
            InfoRow('Alert endpoint (device)', api.deviceAlertPath ?? (api.alertsUnsupported ? 'unavailable' : 'not probed yet')),
            if (api.alertsUnsupportedReason != null) InfoRow('Alert probe', api.alertsUnsupportedReason!),
          ],
          const Divider(height: 24),
          Text('Database', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          AsyncView<(Map<String, int>, int)>(
            value: stats,
            builder: (s) => Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Size ${(s.$2 / 1024 / 1024).toStringAsFixed(1)} MB', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                for (final e in s.$1.entries) Text('${e.key}: ${Fmt.int_(e.value)}', style: t.bodySmall),
              ],
            ),
          ),
          const Divider(height: 24),
          Text('Sync log (newest first)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          AsyncView<List<SyncLogEntry>>(
            value: logs,
            emptyWhen: (l) => l.isEmpty,
            emptyMessage: 'No sync runs yet',
            builder: (l) => ChartTable(
              maxHeight: 260,
              columns: const ['Phase', 'Started', 'Duration', 'OK', 'Items', 'Message'],
              rows: [
                for (final e in l)
                  [e.kind, Fmt.dateTime(e.startedAt), e.duration == null ? '…' : Fmt.duration(e.duration), e.ok == null ? '…' : (e.ok! ? 'yes' : 'no'), e.items?.toString() ?? '', e.message ?? ''],
              ],
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(child: Text('App log (${appLog.length} lines)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
              TextButton.icon(
                onPressed: appLog.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: appLog.join('\n')));
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Log copied')));
                      },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              TextButton.icon(onPressed: appLog.isEmpty ? null : () => ref.read(appLogProvider.notifier).clear(), icon: const Icon(Icons.clear_all, size: 16), label: const Text('Clear')),
            ],
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              child: SelectableText(appLog.isEmpty ? 'Nothing logged yet.' : appLog.reversed.join('\n'), style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }
}
