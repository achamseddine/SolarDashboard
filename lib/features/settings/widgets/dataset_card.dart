import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/schools/school_dataset.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';

/// Settings → school dataset: what is loaded, where it came from, re-import
/// and re-link actions.
class DatasetCard extends ConsumerStatefulWidget {
  const DatasetCard({super.key});

  @override
  ConsumerState<DatasetCard> createState() => _DatasetCardState();
}

class _DatasetCardState extends ConsumerState<DatasetCard> {
  bool _busy = false;

  static const _sources = [
    'Overview_of_Public_Schools.xlsx — MEHE public school master list',
    'Connectivity534Schools.xlsx — schools in the internet-connectivity roll-out',
    'Public_Schools_Solar_Implementation.xlsx — UNICEF solar tracker (status, donors, contractors)',
    'Energy_Breakdown.xlsx — energy audit (annual loads by category, equipment inventory)',
    'EDU_Dashboard_Data.xlsx — MEHE education dashboard (attendance, risk levels)',
  ];

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reimport() async {
    setState(() => _busy = true);
    try {
      final text = await rootBundle.loadString(SchoolDataset.assetPath);
      final ds = SchoolDataset.fromJson(text);
      final db = ref.read(databaseProvider);
      await SchoolDatasetImporter(db, log: (m) => ref.read(appLogProvider.notifier).add(m)).importIfNeeded(ds, force: true);
      final linked = await ref.read(syncEngineProvider).linkSchools();
      _toast('Dataset v${ds.version} re-imported: ${ds.schools.length} schools · $linked plants linked');
    } catch (e) {
      _toast('Re-import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _relink() async {
    setState(() => _busy = true);
    try {
      final n = await ref.read(syncEngineProvider).linkSchools();
      _toast('$n plants linked to school records');
    } catch (e) {
      _toast('Linking failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(schoolDatasetInfoProvider).value;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'School dataset',
      subtitle: 'MEHE / UNICEF workbooks bundled with the app and imported into the local database; plants are matched to school records (CERD) after every sync.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
          else if (!info.isImported)
            Text('The dataset has not been imported yet.', style: t.bodyMedium)
          else
            Wrap(
              spacing: 32,
              runSpacing: 8,
              children: [
                _Fact('Version', 'v${info.version}${info.generatedAt == null ? '' : ' · ${info.generatedAt}'}'),
                _Fact('Imported', Fmt.date(info.importedAt)),
                _Fact('Schools', Fmt.int_(info.schools)),
                _Fact('Solarised', Fmt.int_(info.solarized)),
                _Fact('Connected', Fmt.int_(info.connected)),
                _Fact('Plant links', '${Fmt.int_(info.links)} (${info.manualLinks} by hand)'),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(onPressed: _busy ? null : _reimport, icon: const Icon(Icons.upload_file_outlined, size: 18), label: const Text('Re-import bundled dataset')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _busy ? null : _relink, icon: const Icon(Icons.link, size: 18), label: const Text('Re-link plants')),
              if (_busy) ...[const SizedBox(width: 12), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))],
            ],
          ),
          const SizedBox(height: 12),
          Text('Sources', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          for (final s in _sources) Text('• $s', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text('Director names and personal phone numbers are not bundled. Rebuild the JSON with scripts/build_school_dataset.py when the workbooks change.', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
