import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../common/widgets.dart';
import 'nav.dart';
import 'widgets/detail_kpis.dart';
import 'widgets/device_cards.dart';
import 'widgets/power_flow_panel.dart';
import 'widgets/station_alerts.dart';
import 'widgets/station_charts.dart';
import 'widgets/station_header.dart';

/// One school: live flow, KPIs, charts, devices, alarms, status history.
class StationDetailScreen extends ConsumerStatefulWidget {
  const StationDetailScreen({super.key, required this.stationId});
  final int stationId;

  @override
  ConsumerState<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends ConsumerState<StationDetailScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant StationDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.stationId != widget.stationId) _refresh(force: true);
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted || _refreshing) return;
    if (!ref.read(canSyncProvider)) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(syncEngineProvider).refreshStation(widget.stationId, force: force);
    } catch (_) {
      // Errors are recorded on the station row and shown in the header.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(stationDetailProvider(widget.stationId));
    final staleMinutes = ref.watch(settingsProvider.select((s) => s.staleAfterMinutes));
    return AsyncView<StationDetail?>(
      value: detail,
      emptyWhen: (d) => d == null,
      emptyMessage: 'Plant ${widget.stationId} is not in the local database.',
      builder: (d) {
        final det = d!;
        return ListView(
          padding: kPagePadding,
          children: [
            StationHeader(station: det.station, status: det.station.status, onRefresh: () => _refresh(force: true), refreshing: _refreshing, lastError: det.latest?.lastErrorMsg),
            TwoColumn(
              leftFlex: 2,
              rightFlex: 3,
              left: PowerFlowPanel(latest: det.latest, staleAfterMinutes: staleMinutes),
              right: DetailKpis(latest: det.latest, insight: det.insight),
            ),
            const SizedBox(height: kGap),
            TodayPowerCard(detail: det),
            const SizedBox(height: kGap),
            TwoColumn(left: StationEnergy30dCard(detail: det), right: StationEnergy12mCard(detail: det)),
            const SizedBox(height: kGap),
            BatteryHistoryCard(detail: det),
            const SizedBox(height: kGap),
            Text('Devices · ${det.devices.length}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DeviceCards(devices: det.devices, latest: det.deviceLatest),
            const SizedBox(height: kGap),
            TwoColumn(
              leftFlex: 3,
              rightFlex: 2,
              left: StationAlertsCard(stationId: det.station.id, alerts: det.alerts),
              right: StatusHistoryCard(events: det.statusEvents),
            ),
            const SizedBox(height: kGap),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => goBack(context), icon: const Icon(Icons.arrow_back), label: const Text('Back to schools')),
            ),
          ],
        );
      },
    );
  }
}
