import 'package:flutter/material.dart';

import '../../../core/models/school.dart';
import '../../../core/models/school_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';
import 'programme_common.dart';

/// How plants were matched to schools, and the plants still unlinked.
class LinksCard extends StatelessWidget {
  const LinksCard({super.key, required this.insights});
  final SchoolInsights insights;

  static const _maxRows = 10;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final methods = d.linkMethods;
    final linked = methods.values.fold(0, (a, b) => a + b);
    final unlinked = d.unlinkedStations;
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Plant ↔ school links',
      subtitle: d.stations == 0 ? 'No plant synced yet' : '${Fmt.int_(linked)} of ${Fmt.int_(d.stations)} plants linked to a school · ${Fmt.int_(unlinked.length)} unlinked',
      trailing: SeeAllButton(location: stationsRoute(), label: 'All plants'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.stations == 0)
            const MutedNote('Links are created after the first synchronisation of the DeyeCloud account.')
          else
            FactWrap(
              children: [
                for (final m in LinkMethod.values)
                  if ((methods[m] ?? 0) > 0) FactTile(label: m.label, value: Fmt.int_(methods[m]), width: 150, color: m == LinkMethod.manual ? AppColors.unicefDark : null),
                if (linked == 0) const FactTile(label: 'Linked plants', value: '0', width: 150, hint: 'No plant matched a school'),
              ],
            ),
          const SizedBox(height: 14),
          Text('Unlinked plants · ${Fmt.int_(unlinked.length)}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          if (unlinked.isEmpty)
            MutedNote(d.stations == 0 ? 'Nothing to link yet.' : 'Every plant in the account is linked to a school.')
          else ...[
            const SizedBox(height: 4),
            for (final s in unlinked.take(_maxRows))
              CompactRow(
                leading: const Icon(Icons.link_off, size: 18, color: AppColors.muted),
                title: s.name,
                subtitle: '${s.region} · ${s.station.address ?? s.station.caza ?? 'no address'} · ${s.status.label}',
                trailing: Fmt.capacity(s.kwp),
                trailingHint: 'installed',
                onTap: () => goTo(context, stationRoute(s.id)),
              ),
            if (unlinked.length > _maxRows) MutedNote('Showing $_maxRows of ${unlinked.length} unlinked plants.'),
          ],
          const MutedNote('Links are made automatically from the plant name and coordinates (CERD number in the name, name similarity, location). A link can be set or changed by hand from the school page of a plant; manual links are kept when automatic linking runs again.'),
        ],
      ),
    );
  }
}
