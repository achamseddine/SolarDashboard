import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Landing-page strip: how far the solarisation programme has come, from the
/// MEHE/UNICEF dataset. Renders nothing while the insights are not ready.
class ProgrammeStrip extends ConsumerWidget {
  const ProgrammeStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(schoolInsightsProvider).value;
    if (d == null || d.publicSchools == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: kGap),
      child: SectionCard(
        title: 'Solarisation programme',
        subtitle: '${Fmt.int_(d.solarized)} of ${Fmt.int_(d.publicSchools)} public schools solarised · ${Fmt.int_(d.pipeline)} in the pipeline · ${Fmt.capacity(d.installedKwp)} installed',
        trailing: const SeeAllButton(location: '/programme', label: 'Programme'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TileGrid(
              minTileWidth: 180,
              tileHeight: 84,
              children: [
                KpiTile(dense: true, label: 'Public schools', value: Fmt.int_(d.publicSchools), hint: '${Fmt.int_(d.students)} students', icon: Icons.school_outlined, onTap: () => goTo(context, '/schools')),
                KpiTile(dense: true, label: 'Solarised', value: Fmt.int_(d.solarized), hint: '${Fmt.ratio(d.solarizedShare)} of public schools', icon: Icons.wb_sunny_outlined, color: AppColors.pv, onTap: () => goTo(context, '/programme')),
                KpiTile(dense: true, label: 'Connected', value: Fmt.int_(d.connected), hint: '${Fmt.ratio(d.connectedShare)} · ${Fmt.int_(d.solarizedConnected)} solar + internet', icon: Icons.wifi, color: AppColors.unicefCyan, onTap: () => goTo(context, '/connectivity')),
                KpiTile(dense: true, label: 'Monitored plants', value: Fmt.int_(d.monitored), hint: '${Fmt.int_(d.solarizedUnmonitored)} solarised, no plant', icon: Icons.link, color: AppColors.battery, onTap: () => goTo(context, '/programme')),
              ],
            ),
            const SizedBox(height: 10),
            RatioMeter(value: d.solarizedShare, color: AppColors.pv, label: 'Coverage: ${Fmt.ratio(d.solarizedShare)} of public schools solarised · ${Fmt.int_(d.studentsSolarized)} students benefiting'),
            const SizedBox(height: 6),
            Text('MEHE / UNICEF workbooks · plant ↔ school links are automatic unless set by hand', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
