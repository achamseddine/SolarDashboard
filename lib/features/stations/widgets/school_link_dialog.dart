import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/school.dart';
import '../../../core/providers.dart';
import '../../../core/schools/station_school_linker.dart';
import '../../../core/utils/format.dart';
import 'school_profile_card.dart' show solarStatusColor;

/// Manual plant ↔ school link picker: automatic suggestions (name +
/// coordinates) or a search by name / Arabic name / CERD number.
class SchoolLinkDialog extends ConsumerStatefulWidget {
  const SchoolLinkDialog({super.key, required this.stationId, this.current});

  final int stationId;

  /// The existing link, when the plant is already linked.
  final StationSchoolLink? current;

  static Future<void> show(BuildContext context, {required int stationId, StationSchoolLink? current}) =>
      showDialog<void>(context: context, builder: (_) => SchoolLinkDialog(stationId: stationId, current: current));

  @override
  ConsumerState<SchoolLinkDialog> createState() => _SchoolLinkDialogState();
}

class _SchoolLinkDialogState extends ConsumerState<SchoolLinkDialog> {
  final _controller = TextEditingController();
  String _query = '';
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(School school) async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await db.schools.setLink(StationSchoolLink(stationId: widget.stationId, cerd: school.cerd, method: LinkMethod.manual, confidence: 1, updatedAt: nowEpoch()));
    db.notifyChanged(DataKind.schools);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _unlink() async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    await db.schools.deleteLink(widget.stationId);
    db.notifyChanged(DataKind.schools);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _rerun() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final n = await ref.read(syncEngineProvider).linkSchools();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = 'Automatic matching re-run · $n link${n == 1 ? '' : 's'} written (links set by hand are kept).';
    });
  }

  static String _distance(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final suggestions = ref.watch(linkSuggestionsProvider((widget.stationId, _query)));
    final searching = _query.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.current == null ? 'Link plant to a school' : 'Change the linked school'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search by name, Arabic name or CERD number',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 6),
            Text(
              searching ? 'Schools matching “${_query.trim()}” (MEHE public school list)' : 'Automatic suggestions ranked by name similarity and distance to the plant',
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_message!, style: t.bodySmall?.copyWith(color: scheme.primary)),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: suggestions.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load schools: $e', style: t.bodySmall?.copyWith(color: scheme.error))),
                data: (list) => list.isEmpty
                    ? Center(
                        child: Text(
                          searching ? 'No school matches “${_query.trim()}”.' : 'No automatic suggestion — search for the school by name or CERD number.',
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _CandidateTile(
                          candidate: list[i],
                          showConfidence: !searching,
                          isCurrent: widget.current?.cerd == list[i].school.cerd,
                          enabled: !_busy,
                          onTap: () => _pick(list[i].school),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton.icon(
            onPressed: _busy ? null : _unlink,
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Unlink'),
          ),
        TextButton.icon(
          onPressed: _busy ? null : _rerun,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.autorenew, size: 18),
          label: const Text('Re-run automatic matching'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.showConfidence, required this.isCurrent, required this.enabled, required this.onTap});
  final LinkCandidate candidate;
  final bool showConfidence;
  final bool isCurrent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = candidate.school;
    final status = s.solarStatus;
    final place = [s.region ?? 'Unassigned', ?s.caza].join(' / ');
    final d = candidate.distanceM;
    final trailing = <String>[
      if (showConfidence) Fmt.ratio(candidate.confidence),
      if (d != null) _SchoolLinkDialogState._distance(d),
    ];
    return ListTile(
      dense: true,
      enabled: enabled,
      selected: isCurrent,
      onTap: onTap,
      leading: Icon(isCurrent ? Icons.link : Icons.school_outlined, color: isCurrent ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          'CERD ${s.cerd}',
          place,
          ?s.nameAr,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: solarStatusColor(status).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
              child: Text(status.label, style: t.labelMedium?.copyWith(color: solarStatusColor(status), fontWeight: FontWeight.w600)),
            ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Text(trailing.join('\n'), textAlign: TextAlign.right, style: t.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ],
      ),
    );
  }
}
