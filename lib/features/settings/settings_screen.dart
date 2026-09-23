import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import 'widgets/credentials_card.dart';
import 'widgets/gwn_credentials_card.dart';
import 'widgets/dataset_card.dart';
import 'widgets/diagnostics_card.dart';

const appVersion = '1.0.0';

/// Credentials, demo mode, sync cadence, display, advanced, diagnostics.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final canSync = ref.watch(canSyncProvider);
    final notifier = ref.read(settingsProvider.notifier);
    Future<void> set(AppSettings Function(AppSettings) f) => notifier.update(f);
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: kPagePadding,
      children: [
        PageHeader(title: 'Settings', subtitle: 'UNICEF School Solar Monitor $appVersion'),
        if (!canSync)
          Card(
            color: AppColors.stale.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.stale),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Welcome. Enter the DeyeCloud credentials below to start monitoring the school plants, or switch on demo mode to explore the app with synthetic data.', style: t.bodyMedium)),
                ],
              ),
            ),
          ),
        const SizedBox(height: kGap),
        const CredentialsCard(),
        const SizedBox(height: kGap),
        const GwnCredentialsCard(),
        const SizedBox(height: kGap),
        SectionCard(
          title: 'Demo mode',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.demoMode,
            onChanged: (v) => set((x) => x.copyWith(demoMode: v)),
            title: const Text('Use a synthetic fleet of ~60 Lebanese schools'),
            subtitle: const Text('No network needed. Switch off to use the DeyeCloud account. Data from both sources share the same local database — use "Clear all data" when switching.'),
          ),
        ),
        const SizedBox(height: kGap),
        const DatasetCard(),
        const SizedBox(height: kGap),
        SectionCard(
          title: 'Synchronisation',
          child: Column(
            children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, value: s.autoSync, onChanged: (v) => set((x) => x.copyWith(autoSync: v)), title: const Text('Automatic synchronisation'), subtitle: const Text('Poll DeyeCloud on a schedule while the app is open')),
              _SliderTile(label: 'Poll interval', value: s.pollIntervalMinutes.toDouble(), min: 2, max: 60, divisions: 29, unit: 'min', onChanged: (v) => set((x) => x.copyWith(pollIntervalMinutes: v.round())), hint: 'Device readings, plant status and derived alarms'),
              _SliderTile(label: 'Plant live data interval', value: s.stationLatestIntervalMinutes.toDouble(), min: 5, max: 120, divisions: 23, unit: 'min', onChanged: (v) => set((x) => x.copyWith(stationLatestIntervalMinutes: v.round())), hint: '/station/latest for every plant (one request per plant)'),
              _SliderTile(label: 'Alarm interval (alarming plants)', value: s.alertIntervalMinutes.toDouble(), min: 5, max: 120, divisions: 23, unit: 'min', onChanged: (v) => set((x) => x.copyWith(alertIntervalMinutes: v.round()))),
              _SliderTile(label: 'Alarm interval (all plants)', value: s.alertFleetIntervalMinutes.toDouble(), min: 15, max: 720, divisions: 47, unit: 'min', onChanged: (v) => set((x) => x.copyWith(alertFleetIntervalMinutes: v.round()))),
              _SliderTile(label: 'Concurrent requests', value: s.maxConcurrentRequests.toDouble(), min: 1, max: 8, divisions: 7, unit: '', onChanged: (v) => set((x) => x.copyWith(maxConcurrentRequests: v.round())), hint: 'Lower if DeyeCloud answers with rate-limit errors'),
              _SliderTile(label: 'Stale threshold', value: s.staleAfterMinutes.toDouble(), min: 15, max: 720, divisions: 47, unit: 'min', onChanged: (v) => set((x) => x.copyWith(staleAfterMinutes: v.round())), hint: 'A plant whose newest data is older than this is shown as stale'),
              _SliderTile(label: 'Raw time-series retention', value: s.retentionDays.toDouble(), min: 3, max: 30, divisions: 27, unit: 'days', onChanged: (v) => set((x) => x.copyWith(retentionDays: v.round())), hint: 'Per-plant power snapshots and device samples; daily/monthly energy and status history are kept forever'),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: s.backfillFrames, onChanged: (v) => set((x) => x.copyWith(backfillFrames: v)), title: const Text('Nightly intraday backfill'), subtitle: const Text("Fetch yesterday's 5–10 min frames for every plant once a night (one request per plant)")),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: s.collectDeviceReadings, onChanged: (v) => set((x) => x.copyWith(collectDeviceReadings: v)), title: const Text('Collect inverter and battery readings'), subtitle: const Text('Batched /device/latest polling (10 devices per request); needed for derived alarms and battery statistics')),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(onPressed: canSync ? () => ref.read(syncEngineProvider).syncNow() : null, icon: const Icon(Icons.sync, size: 18), label: const Text('Sync now')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear all local data?'),
                          content: const Text('Every synced plant, reading, energy row, alarm and status history will be deleted. Credentials and settings are kept. The next synchronisation rebuilds the database (history is re-fetched).'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete everything')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref.read(databaseProvider).clearAllData();
                        if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Local data cleared')));
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear all data'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        SectionCard(
          title: 'Display and factors',
          child: Column(
            children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, value: s.darkMode, onChanged: (v) => set((x) => x.copyWith(darkMode: v)), title: const Text('Dark mode')),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: s.keepScreenOn, onChanged: (v) => set((x) => x.copyWith(keepScreenOn: v)), title: const Text('Keep screen on'), subtitle: const Text('For wall-mounted / kiosk tablets')),
              _SliderTile(label: 'CO₂ factor', value: s.co2FactorKgPerKwh, min: 0.2, max: 1.2, divisions: 100, unit: 'kg/kWh', decimals: 2, onChanged: (v) => set((x) => x.copyWith(co2FactorKgPerKwh: v)), hint: 'Emissions avoided per self-consumed kWh (grid + diesel generators)'),
              _SliderTile(label: 'Diesel factor', value: s.dieselLitresPerKwh, min: 0.1, max: 0.5, divisions: 40, unit: 'L/kWh', decimals: 2, onChanged: (v) => set((x) => x.copyWith(dieselLitresPerKwh: v)), hint: 'Generator fuel per kWh'),
              _SliderTile(label: 'Expected PV yield', value: s.specificYieldKwhPerKwp, min: 1000, max: 2000, divisions: 20, unit: 'kWh/kWp·yr', onChanged: (v) => set((x) => x.copyWith(specificYieldKwhPerKwp: v)), hint: 'Used to compare installed capacity with the audited school loads'),
              _SliderTile(label: 'School day starts', value: s.schoolDayStartHour.toDouble(), min: 6, max: 10, divisions: 4, unit: 'h', onChanged: (v) => set((x) => x.copyWith(schoolDayStartHour: v.round()))),
              _SliderTile(label: 'School day ends', value: s.schoolDayEndHour.toDouble(), min: 12, max: 18, divisions: 6, unit: 'h', onChanged: (v) => set((x) => x.copyWith(schoolDayEndHour: v.round()))),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        _AdvancedCard(settings: s),
        const SizedBox(height: kGap),
        const DiagnosticsCard(),
        const SizedBox(height: kGap),
        Text('Map data © OpenStreetMap contributors · Boundaries © geoBoundaries (CC BY 4.0)', style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({required this.label, required this.value, required this.min, required this.max, required this.divisions, required this.unit, required this.onChanged, this.hint, this.decimals = 0});
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;
  final String? hint;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.bodyMedium),
                if (hint != null) Text(hint!, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: '${value.toStringAsFixed(decimals)} $unit', onChanged: onChanged),
          ),
          SizedBox(width: 90, child: Text('${value.toStringAsFixed(decimals)} $unit', textAlign: TextAlign.right, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]))),
        ],
      ),
    );
  }
}

class _AdvancedCard extends ConsumerStatefulWidget {
  const _AdvancedCard({required this.settings});
  final AppSettings settings;

  @override
  ConsumerState<_AdvancedCard> createState() => _AdvancedCardState();
}

class _AdvancedCardState extends ConsumerState<_AdvancedCard> {
  late final TextEditingController _station = TextEditingController(text: widget.settings.alertStationPath ?? '');
  late final TextEditingController _device = TextEditingController(text: widget.settings.alertDevicePath ?? '');

  @override
  void dispose() {
    _station.dispose();
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Advanced — alarm endpoints',
      subtitle: 'DeyeCloud launched the alert list endpoints in Dec 2024 without public samples; the app probes /station/alertList, /station/alert/list, … and remembers the first that answers. Override here if the developer portal documents different paths.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 300, child: TextField(controller: _station, decoration: const InputDecoration(labelText: 'Station alert path', hintText: '/station/alertList', border: OutlineInputBorder(), isDense: true))),
              SizedBox(width: 300, child: TextField(controller: _device, decoration: const InputDecoration(labelText: 'Device alert path', hintText: '/device/alertList', border: OutlineInputBorder(), isDense: true))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(
                        alertStationPath: _station.text.trim().isEmpty ? null : _station.text.trim(),
                        alertDevicePath: _device.text.trim().isEmpty ? null : _device.text.trim(),
                        clearAlertPaths: _station.text.trim().isEmpty && _device.text.trim().isEmpty,
                      ));
                  if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Alarm endpoint paths applied – used on the next sync')));
                },
                child: const Text('Apply'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _station.clear();
                  _device.clear();
                  ref.read(settingsProvider.notifier).update((s) => s.copyWith(clearAlertPaths: true));
                },
                child: const Text('Reset to auto-probe'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Request bodies: station {stationId, startTimestamp, endTimestamp, page, size}; device {deviceSn, startTimestamp, endTimestamp}. Timestamps are 10-digit Unix seconds.', style: t.labelSmall),
        ],
      ),
    );
  }
}
