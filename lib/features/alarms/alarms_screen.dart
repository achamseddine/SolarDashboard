import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/models/alert.dart';
import '../../core/models/fleet_insights.dart';
import '../../core/models/sync.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../stations/nav.dart';
import '../stations/widgets/station_alerts.dart';

/// Alarm centre: filters, summary, list with acknowledge.
class AlarmsScreen extends ConsumerStatefulWidget {
  const AlarmsScreen({super.key, this.initialStationId});
  final int? initialStationId;

  @override
  ConsumerState<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends ConsumerState<AlarmsScreen> {
  late AlertFilter _filter;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _filter = AlertFilter(stationId: widget.initialStationId, status: widget.initialStationId == null ? AlertStatus.active : null, sinceDays: widget.initialStationId == null ? 30 : null);
  }

  @override
  void didUpdateWidget(covariant AlarmsScreen old) {
    super.didUpdateWidget(old);
    if (old.initialStationId != widget.initialStationId && widget.initialStationId != null) {
      setState(() => _filter = _filter.copyWith(stationId: widget.initialStationId, clearStatus: true, clearSince: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _set(AlertFilter f) => setState(() => _filter = f);

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _set(_filter.copyWith(search: v));
    });
  }

  Future<void> _ack(SolarAlert a) async {
    final db = ref.read(databaseProvider);
    await db.alerts.acknowledge(a.id);
    db.notifyChanged(DataKind.alerts);
  }

  Future<void> _ackAll(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acknowledge all active alarms?'),
        content: Text('$count active alarm${count == 1 ? '' : 's'}${_filter.stationId == null ? ' across the fleet' : ' of this plant'} will be marked as acknowledged. They stay listed until they recover.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Acknowledge all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = ref.read(databaseProvider);
    await db.alerts.acknowledgeAll(stationId: _filter.stationId);
    db.notifyChanged(DataKind.alerts);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertsProvider(_filter));
    final insights = ref.watch(fleetInsightsProvider).value;
    final sync = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final stationName = _filter.stationId == null ? null : insights?.stations.where((s) => s.id == _filter.stationId).firstOrNull?.name;
    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: stationName == null ? 'Alarms' : 'Alarms · $stationName',
            subtitle: 'Cloud alarms from DeyeCloud and alarms derived locally from device readings',
            actions: [
              if (_filter.stationId != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(label: Text(stationName ?? 'Plant ${_filter.stationId}'), onDeleted: () => _set(_filter.copyWith(clearStation: true, status: AlertStatus.active, sinceDays: 30)), avatar: const Icon(Icons.school_outlined, size: 16)),
                ),
              Builder(builder: (context) {
                final active = alerts.value?.where((a) => a.isActive && !a.acknowledged).length ?? 0;
                return FilledButton.tonalIcon(
                  onPressed: active == 0 ? null : () => _ackAll(active),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text('Acknowledge all ($active)'),
                );
              }),
            ],
          ),
          if (sync.alertsUnsupportedReason != null)
            Card(
              color: AppColors.stale.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_off_outlined, color: AppColors.stale),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Cloud alarms unavailable: ${sync.alertsUnsupportedReason}. Locally derived alarms (offline plants, device alarm states, low SOC, temperatures, string faults) still work. Check the endpoint paths in Settings → Advanced.', style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            ),
          if (insights != null) _Summary(insights: insights),
          const SizedBox(height: kGap),
          _FilterRow(filter: _filter, onChanged: _set, searchController: _search, onSearch: _onSearch),
          const SizedBox(height: kGap),
          Expanded(
            child: AsyncView<List<SolarAlert>>(
              value: alerts,
              emptyWhen: (l) => l.isEmpty,
              emptyMessage: 'No alarms match the current filters.',
              builder: (list) => Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = list[i];
                    return AlertRow(
                      alert: a,
                      showStation: true,
                      onOpenStation: a.stationId == null ? null : () => goTo(context, '/stations/${a.stationId}'),
                      onAcknowledge: a.isActive && !a.acknowledged ? () => _ack(a) : null,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.insights});
  final FleetInsights insights;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final mttr = i.alertMttrMedianSeconds;
    return TileGrid(
      minTileWidth: 180,
      aspect: 2.6,
      children: [
        KpiTile(label: 'High', value: Fmt.int_(i.activeAlertsByLevel[AlertLevel.high]), icon: Icons.error_outline, color: AppColors.levelHigh, dense: true, hint: 'active'),
        KpiTile(label: 'Medium', value: Fmt.int_(i.activeAlertsByLevel[AlertLevel.medium]), icon: Icons.warning_amber_rounded, color: AppColors.levelMedium, dense: true, hint: 'active'),
        KpiTile(label: 'Low', value: Fmt.int_(i.activeAlertsByLevel[AlertLevel.low]), icon: Icons.info_outline, color: AppColors.levelLow, dense: true, hint: 'active'),
        KpiTile(label: 'Open > 7 days', value: Fmt.int_(i.alertsOpenOver7d), icon: Icons.hourglass_bottom, dense: true, hint: 'need follow-up'),
        KpiTile(label: 'Median time to recovery', value: mttr == null ? '–' : Fmt.duration(Duration(seconds: mttr.round())), icon: Icons.timer_outlined, dense: true, hint: 'recovered alarms, 30 d'),
        KpiTile(label: 'Schools with alarms', value: Fmt.int_(i.stations.where((s) => s.activeAlerts > 0).length), icon: Icons.school_outlined, dense: true, hint: 'of ${i.totalStations}'),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filter, required this.onChanged, required this.searchController, required this.onSearch});
  final AlertFilter filter;
  final ValueChanged<AlertFilter> onChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search alarm, code, school, serial…', border: OutlineInputBorder()),
          ),
        ),
        SegmentedButton<AlertStatus?>(
          segments: const [
            ButtonSegment(value: null, label: Text('All')),
            ButtonSegment(value: AlertStatus.active, label: Text('Active')),
            ButtonSegment(value: AlertStatus.recovered, label: Text('Recovered')),
          ],
          selected: {filter.status},
          onSelectionChanged: (s) => onChanged(s.first == null ? filter.copyWith(clearStatus: true) : filter.copyWith(status: s.first)),
        ),
        Text('Level', style: label),
        for (final l in [AlertLevel.high, AlertLevel.medium, AlertLevel.low])
          FilterChip(
            avatar: Icon(Icons.circle, size: 12, color: AppColors.alertLevel(l)),
            label: Text(l.label),
            selected: filter.level == l,
            onSelected: (on) => onChanged(on ? filter.copyWith(level: l) : filter.copyWith(clearLevel: true)),
          ),
        Text('Source', style: label),
        FilterChip(label: const Text('DeyeCloud'), selected: filter.source == AlertSource.cloud, onSelected: (on) => onChanged(on ? filter.copyWith(source: AlertSource.cloud) : filter.copyWith(clearSource: true))),
        FilterChip(label: const Text('Derived'), selected: filter.source == AlertSource.derived, onSelected: (on) => onChanged(on ? filter.copyWith(source: AlertSource.derived) : filter.copyWith(clearSource: true))),
        Text('Period', style: label),
        DropdownButton<int?>(
          value: filter.sinceDays,
          items: const [
            DropdownMenuItem(value: 1, child: Text('Last 24 h')),
            DropdownMenuItem(value: 7, child: Text('Last 7 days')),
            DropdownMenuItem(value: 30, child: Text('Last 30 days')),
            DropdownMenuItem(value: null, child: Text('All time')),
          ],
          onChanged: (v) => onChanged(v == null ? filter.copyWith(clearSince: true) : filter.copyWith(sinceDays: v)),
        ),
        FilterChip(
          avatar: const Icon(Icons.mark_email_unread_outlined, size: 16),
          label: const Text('Unacknowledged only'),
          selected: filter.unacknowledgedOnly,
          onSelected: (on) => onChanged(filter.copyWith(unacknowledgedOnly: on)),
        ),
      ],
    );
  }
}
