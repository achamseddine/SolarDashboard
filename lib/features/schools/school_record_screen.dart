import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../dashboard/widgets/dashboard_common.dart';
import '../programme/widgets/programme_common.dart';
import 'widgets/school_record_cards.dart';

/// Everything the programme knows about one school, whether or not it has a
/// monitored plant: the MEHE master record, the internet-connectivity
/// roll-out, the solar tracker, the energy audit, the live DeyeCloud plant
/// and the education dashboard.
class SchoolRecordScreen extends ConsumerWidget {
  const SchoolRecordScreen({super.key, required this.cerd});

  final int cerd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(schoolRecordProvider(cerd));
    return AsyncView<SchoolRecord?>(
      value: record,
      emptyWhen: (r) => r == null,
      emptyMessage: 'School $cerd is not in the dataset.',
      builder: (r) => _Record(record: r!),
    );
  }
}

class _Record extends ConsumerWidget {
  const _Record({required this.record});

  final SchoolRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yieldPerKwp = ref.watch(settingsProvider.select((s) => s.specificYieldKwhPerKwp));
    final s = record.school;
    final station = record.station;
    final education = s.education;
    final place = <String>['CERD ${s.cerd}', s.region ?? 'Unassigned', ?s.caza, ?s.cadaster];

    return ListView(
      padding: kPagePadding,
      children: [
        PageHeader(
          title: s.name,
          subtitle: place.join(' · '),
          actions: [
            TextButton.icon(
              onPressed: () => goTo(context, '/schools'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to schools'),
            ),
            if (station != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => goTo(context, stationRoute(station.id)),
                icon: const Icon(Icons.solar_power_outlined, size: 18),
                label: const Text('Open plant'),
              ),
            ],
            if (s.hasLocation) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => goTo(context, '/map'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Show on map'),
              ),
            ],
          ],
        ),
        _StatusChips(record: record),
        const SizedBox(height: kGap),
        SchoolRecordKpis(record: record, yieldPerKwp: yieldPerKwp),
        const SizedBox(height: kGap),
        TwoColumn(
          left: SchoolFactsCard(school: s),
          right: SchoolConnectivityCard(school: s, isMonitored: record.isMonitored),
        ),
        const SizedBox(height: kGap),
        SchoolSolarCard(school: s, station: station, yieldPerKwp: yieldPerKwp),
        const SizedBox(height: kGap),
        SchoolAuditCard(school: s, equipment: record.equipment),
        if (record.isMonitored || s.isSolarized) ...[
          const SizedBox(height: kGap),
          SchoolPlantCard(station: station, link: record.link, isSolarized: s.isSolarized),
        ],
        if (education != null) ...[
          const SizedBox(height: kGap),
          SchoolEducationCard(education: education),
        ],
        const SizedBox(height: kGap),
        MutedNote(
          'Sources: MEHE public school master list (1,211 schools), the internet-connectivity roll-out (a membership list of 534 schools — '
          'no bandwidth, provider or uptime), the UNICEF solar implementation tracker, the MEHE energy audit (annual loads and equipment '
          'inventory) and the MEHE education dashboard (attendance and risk). Expected generation = installed kWp × '
          '${Fmt.int_(yieldPerKwp)} kWh/kWp/yr (Settings). Live figures come from the linked DeyeCloud plant.',
        ),
      ],
    );
  }
}

/// Internet, solar, monitoring and shift, as one line of pills.
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.record});

  final SchoolRecord record;

  @override
  Widget build(BuildContext context) {
    final s = record.school;
    final status = s.solarStatus;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        s.connected
            ? const RecordChip(label: 'Internet connected', color: AppColors.good, icon: Icons.wifi)
            : const RecordChip(label: 'No internet connection', color: AppColors.muted, icon: Icons.wifi_off),
        if (status != null)
          RecordChip(label: status.label, color: solarStatusColor(status), icon: Icons.solar_power_outlined)
        else
          const RecordChip(label: 'Not in the solar tracker', color: AppColors.muted, icon: Icons.solar_power_outlined),
        record.isMonitored
            ? const RecordChip(label: 'Monitored plant', color: AppColors.unicefCyan, icon: Icons.podcasts)
            : const RecordChip(label: 'No monitored plant', color: AppColors.muted, icon: Icons.podcasts),
        if ((s.studentsPm ?? 0) > 0)
          RecordChip(label: 'Second shift · ${Fmt.int_(s.studentsPm)} students', color: AppColors.unicefDark, icon: Icons.schedule_outlined),
      ],
    );
  }
}
