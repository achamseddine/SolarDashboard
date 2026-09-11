import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/fleet_insights.dart';
import '../../core/models/school.dart';
import '../../core/models/school_insights.dart';
import '../../core/models/station.dart';
import '../../core/providers.dart';
import '../../core/sync/station_region.dart';
import '../../core/theme.dart';
import '../../core/utils/format.dart';
import '../common/widgets.dart';
import '../stations/nav.dart';

/// Lebanon map with governorate outlines, status-coloured plant markers and
/// an optional layer of every public school in the MEHE master list.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.showTiles = true});

  /// Set false in tests (no network for OpenStreetMap tiles).
  final bool showTiles;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _controller = MapController();
  StationStatus? _status;
  String? _region;
  bool _onlyAlarms = false;

  /// "Public schools" layer (MEHE master list), off by default.
  bool _showSchools = false;

  /// Within the school layer: only schools on the connectivity roll-out.
  bool _connectedOnly = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(fleetInsightsProvider);
    final boundaries = ref.watch(boundariesProvider);
    // School dataset (MEHE master list + programme tracker), joined to the fleet.
    final schoolInsights = _showSchools ? ref.watch(schoolInsightsProvider).value : null;
    return AsyncView<FleetInsights>(
      value: insights,
      builder: (d) {
        final all = d.stations.where((s) => s.station.hasLocation).toList();
        final shown = all.where((s) {
          if (_status != null && s.status != _status) return false;
          if (_region != null && s.region != _region) return false;
          if (_onlyAlarms && s.activeAlerts == 0) return false;
          return true;
        }).toList();
        final noLocation = d.stations.length - all.length;
        // Schools with coordinates that have no monitored plant (those are
        // already on the map as plant markers). Region filter applies too.
        final schools = <SchoolInsight>[
          if (schoolInsights != null)
            for (final s in schoolInsights.schools)
              if (s.school.hasLocation && !s.isMonitored && (!_connectedOnly || s.isConnected) && (_region == null || s.region == _region)) s,
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${shown.length} of ${all.length} plants on the map${noLocation > 0 ? ' · $noLocation without coordinates' : ''}', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  for (final s in StationStatus.values)
                    FilterChip(
                      avatar: Icon(AppColors.stationStatusIcon(s), size: 16, color: AppColors.stationStatus(s)),
                      label: Text('${s.label} ${d.count(s)}'),
                      selected: _status == s,
                      onSelected: (on) => setState(() => _status = on ? s : null),
                    ),
                  FilterChip(avatar: const Icon(Icons.notifications_active_outlined, size: 16), label: const Text('With alarms'), selected: _onlyAlarms, onSelected: (on) => setState(() => _onlyAlarms = on)),
                  FilterChip(
                    avatar: const Icon(Icons.school_outlined, size: 16),
                    label: const Text('Public schools'),
                    tooltip: 'Show every public school of the MEHE master list (coloured by solar status)',
                    selected: _showSchools,
                    onSelected: (on) => setState(() => _showSchools = on),
                  ),
                  if (_showSchools)
                    FilterChip(
                      avatar: Icon(Icons.wifi, size: 16, color: _connectedOnly ? AppColors.good : null),
                      label: const Text('Connected only'),
                      tooltip: 'Only schools on the internet-connectivity roll-out list',
                      selected: _connectedOnly,
                      onSelected: (on) => setState(() => _connectedOnly = on),
                    ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _region,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, labelText: 'Governorate', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All')),
                        for (final r in [...LebanonRegions.all, LebanonRegions.unassigned]) DropdownMenuItem<String?>(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _region = v),
                    ),
                  ),
                  IconButton(tooltip: 'Reset view', icon: const Icon(Icons.center_focus_strong_outlined), onPressed: () => _controller.move(const LatLng(33.85, 35.85), 8)),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: const MapOptions(initialCenter: LatLng(33.85, 35.85), initialZoom: 8, minZoom: 6, maxZoom: 17),
                    children: [
                      if (widget.showTiles)
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'org.unicef.unicef_solar_monitor',
                          errorTileCallback: (_, _, _) {},
                        ),
                      if (boundaries != null && boundaries.isLoaded)
                        PolygonLayer(
                          polygons: [
                            for (final g in boundaries.governorates)
                              for (final ring in g.outlines)
                                Polygon(
                                  points: [for (final p in ring) LatLng(p.$1, p.$2)],
                                  color: AppColors.unicefCyan.withValues(alpha: 0.05),
                                  borderColor: AppColors.unicefDark.withValues(alpha: 0.6),
                                  borderStrokeWidth: 1.2,
                                ),
                          ],
                        ),
                      // Schools sit underneath the plant markers; ~1,250 cheap
                      // dots, no tooltips, so panning stays smooth.
                      if (_showSchools)
                        MarkerLayer(
                          markers: [
                            for (final s in schools)
                              Marker(
                                point: LatLng(s.school.lat!, s.school.lng!),
                                width: _SchoolDot.hitSize,
                                height: _SchoolDot.hitSize,
                                child: _SchoolDot(insight: s, onTap: () => _openSchool(context, s)),
                              ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          for (final s in shown)
                            Marker(
                              point: LatLng(s.station.lat!, s.station.lng!),
                              width: _size(s.kwp),
                              height: _size(s.kwp),
                              child: _StationMarker(insight: s, onTap: () => _open(context, s)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(right: 12, bottom: 12, child: _Legend(shown: shown, schools: _showSchools ? schools : null, schoolsLoading: _showSchools && schoolInsights == null)),
                  if (!widget.showTiles)
                    Positioned(left: 12, bottom: 12, child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('Base map tiles disabled', style: Theme.of(context).textTheme.labelSmall)))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static double _size(double? kwp) => (14 + ((kwp ?? 10) / 30) * 14).clamp(14, 28).toDouble();

  void _open(BuildContext context, StationInsight s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _StationSheet(insight: s, onOpen: () {
        Navigator.pop(ctx);
        goTo(context, '/stations/${s.id}');
      }),
    );
  }

  void _openSchool(BuildContext context, SchoolInsight s) {
    final station = s.station;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SchoolSheet(
        insight: s,
        onOpen: station == null
            ? null
            : () {
                Navigator.pop(ctx);
                goTo(context, '/stations/${station.id}');
              },
      ),
    );
  }
}

/// Colour of a school dot: solarised without a monitored plant, in the
/// pipeline, or not solarised (also used by the legend).
Color schoolMarkerColor(School school) {
  final status = school.solarStatus;
  if (status == SolarStatus.completed) return AppColors.warning;
  if (status != null && status.isPipeline) return AppColors.unicefCyan;
  return _SchoolDot.notSolarized;
}

/// 8 px school dot (white ring = internet-connected) with a slightly larger
/// tap target. Decorations are shared so 1,250 markers stay cheap.
class _SchoolDot extends StatelessWidget {
  const _SchoolDot({required this.insight, required this.onTap});
  final SchoolInsight insight;
  final VoidCallback onTap;

  static const double dotSize = 8;
  static const double hitSize = 14;
  static final Color notSolarized = AppColors.muted.withValues(alpha: 0.7);

  static final Map<(Color, bool), BoxDecoration> _decorations = {};

  static BoxDecoration _decoration(Color color, bool ring) => _decorations.putIfAbsent(
        (color, ring),
        () => BoxDecoration(color: color, shape: BoxShape.circle, border: ring ? Border.all(color: Colors.white, width: 1.5) : null),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: SizedBox(
          width: dotSize,
          height: dotSize,
          child: DecoratedBox(decoration: _decoration(schoolMarkerColor(insight.school), insight.isConnected)),
        ),
      ),
    );
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({required this.insight, required this.onTap});
  final StationInsight insight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.stationStatus(insight.status);
    final surface = ChartPalette.of(context).surface;
    return Tooltip(
      message: '${insight.name}\n${insight.status.label} · ${Fmt.capacity(insight.kwp)} · PV ${Fmt.power(insight.snapshot?.generationW)} · SOC ${Fmt.percent(insight.socNow)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: surface, width: 2), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)]),
          child: insight.activeAlerts > 0 ? const Icon(Icons.priority_high, size: 12, color: Colors.white) : null,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.shown, this.schools, this.schoolsLoading = false});
  final List<StationInsight> shown;

  /// Schools drawn by the school layer (null when the layer is off).
  final List<SchoolInsight>? schools;
  final bool schoolsLoading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final gen = shown.fold(0.0, (a, s) => a + (s.snapshot?.generationW ?? 0));
    final kwp = shown.fold(0.0, (a, s) => a + (s.kwp ?? 0));
    final schools = this.schools;
    final muted = t.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Plant status', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final s in StationStatus.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(AppColors.stationStatusIcon(s), size: 14, color: AppColors.stationStatus(s)),
                  const SizedBox(width: 6),
                  Text(s.label, style: t.labelMedium),
                ]),
              ),
            const SizedBox(height: 4),
            Text('Marker size = installed kWp · ! = active alarms', style: t.labelSmall),
            const Divider(height: 12),
            Text('${Fmt.power(gen)} now · ${Fmt.capacity(kwp)} shown', style: t.labelSmall),
            if (schools != null) ...[
              const Divider(height: 12),
              Text('Public schools', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _LegendDot(color: AppColors.warning, label: 'Solarised, no monitored plant'),
              _LegendDot(color: AppColors.unicefCyan, label: 'Solar pipeline (planned, on hold, unfunded)'),
              _LegendDot(color: _SchoolDot.notSolarized, label: 'Not solarised'),
              _LegendDot(color: _SchoolDot.notSolarized, ring: true, label: 'White ring = internet-connected'),
              const SizedBox(height: 4),
              Text(schoolsLoading ? 'Loading schools…' : '${Fmt.int_(schools.length)} schools shown · ${Fmt.int_(schools.where((s) => s.isConnected).length)} connected', style: t.labelSmall),
              Text('MEHE master list · UNICEF solar tracker · connectivity roll-out', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.ring = false});
  final Color color;
  final String label;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14,
          height: 14,
          child: Center(
            child: SizedBox(
              width: 9,
              height: 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: ring ? Border.all(color: Colors.white, width: 1.5) : null,
                  boxShadow: ring ? const [BoxShadow(color: Color(0x55000000), blurRadius: 1)] : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: t.labelMedium),
      ]),
    );
  }
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({required this.insight, required this.onOpen});
  final StationInsight insight;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = insight;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(s.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            StatusChip(s.status),
          ]),
          Text([s.region, ?s.station.caza, ?s.station.address].join(' · '), style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _Fact('Installed', Fmt.capacity(s.kwp)),
              _Fact('PV now', Fmt.power(s.snapshot?.generationW)),
              _Fact('Load now', Fmt.power(s.snapshot?.consumptionW)),
              _Fact('Battery', Fmt.percent(s.socNow)),
              _Fact('Today', Fmt.energy(s.todayGenKwh)),
              _Fact('Yield 7 d', s.yield7d == null ? '–' : '${Fmt.two(s.yield7d)} kWh/kWp'),
              _Fact('Availability 7 d', Fmt.ratio(s.availability7d)),
              _Fact('Alarms', Fmt.int_(s.activeAlerts)),
              _Fact('Last data', Fmt.ago(s.latest?.dataTs ?? s.station.lastUpdateTs)),
            ],
          ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open school'))),
        ],
      ),
    );
  }
}

/// Bottom sheet of a school marker (MEHE record + programme data).
class _SchoolSheet extends StatelessWidget {
  const _SchoolSheet({required this.insight, this.onOpen});
  final SchoolInsight insight;

  /// Opens the linked plant; null when the school has no monitored plant.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = insight.school;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final solar = s.solar;
    final status = s.solarStatus;
    final statusLabel = status?.label ?? 'Not in the solar tracker';
    final statusColor = status == null ? AppColors.muted : schoolMarkerColor(s);
    final place = [?s.region, ?s.caza, ?s.address].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(s.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Chip(
              avatar: Icon(Icons.solar_power_outlined, size: 16, color: statusColor),
              label: Text(statusLabel),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          if (s.nameAr != null) Text(s.nameAr!, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          Text('CERD ${s.cerd}${place.isEmpty ? '' : ' · $place'}', style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _Fact('Students', Fmt.int_(s.students)),
              _Fact('Internet', s.connected ? 'Connected' : 'Not on roll-out list'),
              _Fact('Solar status', statusLabel),
              if (solar?.donorGroup != null || solar?.donor != null) _Fact('Donor', solar!.donorGroup ?? solar.donor!),
              if (solar?.kwp != null) _Fact('Installed', Fmt.capacity(solar!.kwp)),
              _Fact('Audited load', s.annualLoadKwh == null ? '–' : '${Fmt.energy(s.annualLoadKwh)}/yr'),
              if (insight.expectedAnnualGenKwh != null) _Fact('Expected generation', '${Fmt.energy(insight.expectedAnnualGenKwh)}/yr'),
              _Fact('Monitored plant', insight.isMonitored ? insight.station!.name : 'None'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'MEHE master list, connectivity roll-out and UNICEF solar tracker; audited load from the MEHE energy audit. Expected generation = kWp × specific yield (Settings).',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (onOpen != null) ...[
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open school'))),
          ],
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
