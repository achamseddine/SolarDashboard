import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import 'nav.dart';
import 'widgets/detail_kpis.dart';
import 'widgets/device_cards.dart';
import 'widgets/plant_summary_card.dart';
import 'widgets/power_flow_panel.dart';
import 'widgets/school_profile_card.dart';
import 'widgets/solar_utilisation_card.dart';
import 'widgets/station_alerts.dart';
import 'widgets/station_charts.dart';
import 'widgets/station_header.dart';
import 'widgets/usage_history_card.dart';

/// One plant, laid out like the cloud console: a status header and four tabs
/// — Overview (live flow, totals, utilisation, curves), Devices, Alerts and
/// Plant info (identity, and the school record when one is linked).
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
        final inverters = det.devices.where((x) => x.isInverter).toList();
        final online = inverters.where((x) => (det.deviceLatest[x.deviceSn]?.status ?? x.status) == DeviceStatus.online).length;
        return DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: StationHeader(
                  station: det.station,
                  status: det.station.status,
                  onRefresh: () => _refresh(force: true),
                  refreshing: _refreshing,
                  lastError: det.latest?.lastErrorMsg,
                  invertersOnline: online,
                  invertersTotal: inverters.length,
                  lastUpdateTs: det.latest?.dataTs ?? det.station.lastUpdateTs,
                ),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Devices'),
                  Tab(text: 'Alerts'),
                  Tab(text: 'Plant info'),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    _OverviewTab(detail: det, staleMinutes: staleMinutes),
                    _DevicesTab(detail: det),
                    _AlertsTab(detail: det),
                    _PlantInfoTab(detail: det, refreshing: _refreshing),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Live flow, the figures the console puts in its summary, and the curves.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail, required this.staleMinutes});
  final StationDetail detail;
  final int staleMinutes;

  @override
  Widget build(BuildContext context) {
    final det = detail;
    return ListView(
      padding: kPagePadding,
      children: [
        TwoColumn(
          leftFlex: 2,
          rightFlex: 3,
          left: PowerFlowPanel(latest: det.latest, staleAfterMinutes: staleMinutes),
          right: DetailKpis(latest: det.latest, insight: det.insight),
        ),
        const SizedBox(height: kGap),
        PlantSummaryCard(detail: det),
        const SizedBox(height: kGap),
        SolarUtilisationCard(detail: det),
        const SizedBox(height: kGap),
        TodayPowerCard(detail: det),
        const SizedBox(height: kGap),
        UsageHistoryCard(detail: det),
        const SizedBox(height: kGap),
        TwoColumn(left: StationEnergy30dCard(detail: det), right: StationEnergy12mCard(detail: det)),
        const SizedBox(height: kGap),
        BatteryHistoryCard(detail: det),
      ],
    );
  }
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab({required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final det = detail;
    return ListView(
      padding: kPagePadding,
      children: [
        Text(
          'Devices · ${det.devices.length}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (det.devices.isEmpty)
          const EmptyState(message: 'No device has been synced for this plant yet.', icon: Icons.memory_outlined)
        else
          DeviceCards(devices: det.devices, latest: det.deviceLatest),
      ],
    );
  }
}

class _AlertsTab extends StatelessWidget {
  const _AlertsTab({required this.detail});
  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final det = detail;
    return ListView(
      padding: kPagePadding,
      children: [
        StationAlertsCard(stationId: det.station.id, alerts: det.alerts),
        const SizedBox(height: kGap),
        StatusHistoryCard(events: det.statusEvents),
      ],
    );
  }
}

class _PlantInfoTab extends StatelessWidget {
  const _PlantInfoTab({required this.detail, required this.refreshing});
  final StationDetail detail;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final det = detail;
    final s = det.station;
    return ListView(
      padding: kPagePadding,
      children: [
        SectionCard(
          title: 'Plant',
          subtitle: 'As registered in the DeyeCloud account',
          child: Column(
            children: [
              InfoRow('Plant id', '${s.id}'),
              InfoRow('Name', s.name),
              InfoRow('Governorate', s.region ?? 'Unassigned'),
              InfoRow('District', s.caza ?? '–'),
              InfoRow('Address', s.address ?? '–'),
              InfoRow('Coordinates', s.hasLocation ? '${s.lat!.toStringAsFixed(5)}, ${s.lng!.toStringAsFixed(5)}' : 'No location on record'),
              InfoRow('Installed capacity', s.installedCapacityKw == null ? '–' : '${s.installedCapacityKw} kWp'),
              InfoRow('Battery capacity', s.batteryCapacityKwh == null ? '–' : '${s.batteryCapacityKwh} kWh'),
              InfoRow('Grid type', Fmt.label(s.gridType)),
              InfoRow('Owner', s.ownerName ?? '–'),
              InfoRow('Contact', s.contactPhone ?? '–'),
              InfoRow('Time zone', s.timezone ?? '–'),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        SchoolProfileCard(stationId: s.id, paused: refreshing),
        const SizedBox(height: kGap),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => goBack(context), icon: const Icon(Icons.arrow_back), label: const Text('Back to plants')),
        ),
      ],
    );
  }
}
