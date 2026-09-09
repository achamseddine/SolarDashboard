import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/sync.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';

/// Thin strip showing sync progress, last success, back-off and errors.
class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final canSync = ref.watch(canSyncProvider);
    final demo = ref.watch(settingsProvider.select((s) => s.demoMode));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelMedium;

    Color bg = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    IconData icon = Icons.cloud_done_outlined;
    String message;
    if (!canSync) {
      bg = AppColors.stale.withValues(alpha: 0.15);
      icon = Icons.key_off_outlined;
      message = 'No DeyeCloud credentials – open Settings to sign in or enable demo mode';
    } else if (status.pausedUntil != null) {
      bg = AppColors.stale.withValues(alpha: 0.15);
      icon = Icons.pause_circle_outline;
      message = 'API back-off until ${Fmt.time(status.pausedUntil!.millisecondsSinceEpoch ~/ 1000)} – ${status.message ?? ''}';
    } else if (status.running) {
      icon = Icons.sync;
      final progress = status.total > 0 ? ' ${status.current}/${status.total}' : '';
      message = '${status.phase.label}$progress';
    } else if (status.lastError != null) {
      bg = AppColors.alarm.withValues(alpha: 0.12);
      icon = Icons.error_outline;
      message = 'Last sync problem: ${status.lastError}';
    } else {
      message = status.lastSuccessAt == null ? 'Waiting for first sync' : 'Synced ${Fmt.ago(status.lastSuccessAt!.millisecondsSinceEpoch ~/ 1000)}';
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: canSync && !status.running ? () => ref.read(syncEngineProvider).syncNow() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              if (status.running)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, value: status.progress),
                )
              else
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: text, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (demo) ...[
                const Icon(Icons.science_outlined, size: 14),
                const SizedBox(width: 4),
                Text('DEMO DATA', style: text?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(width: 12),
              ],
              if (status.alertsUnsupportedReason != null) ...[
                Tooltip(message: status.alertsUnsupportedReason!, child: Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.stale)),
                const SizedBox(width: 12),
              ],
              Text('${Fmt.int_(status.requestCount)} req', style: text?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Icon(Icons.refresh, size: 16, color: canSync && !status.running ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
