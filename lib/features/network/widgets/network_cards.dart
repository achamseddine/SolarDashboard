import 'package:flutter/material.dart';

import '../../../core/models/gwn.dart';
import '../../../core/models/network_insights.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format.dart';
import '../../common/charts.dart';
import '../../common/widgets.dart';
import '../../dashboard/widgets/dashboard_common.dart';

/// Section 1 — the executive headline indicators.
class NetworkHeadlineKpis extends StatelessWidget {
  const NetworkHeadlineKpis({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    return TileGrid(
      // Wide enough for the longest headline label ("Meaningfully
      // connected") without the tile clipping it.
      minTileWidth: 240,
      children: [
        KpiTile(
          label: 'Schools connected',
          value: Fmt.int_(d.connected),
          hint: 'seen online at least once · of ${Fmt.int_(d.publicSchools)} public schools',
          icon: Icons.wifi,
          color: AppColors.unicefCyan,
        ),
        KpiTile(
          label: 'LAN operational',
          value: Fmt.int_(d.lanOperational),
          hint: 'gateway up and APs available',
          icon: Icons.lan_outlined,
          color: AppColors.good,
        ),
        KpiTile(
          label: 'Meaningfully connected',
          value: Fmt.int_(d.meaningfullyConnected),
          hint: 'uptime ≥ ${Fmt.ratio(d.thresholds.uptimeTarget)} over a day of checks · speed and quality not measured',
          icon: Icons.speed,
        ),
        KpiTile(
          label: 'Actively using technology',
          value: Fmt.int_(d.activelyUsing),
          hint: 'activity on ≥ ${Fmt.ratio(d.thresholds.activeUseShare)} of school days',
          icon: Icons.devices,
          color: AppColors.unicefDark,
        ),
        KpiTile(
          label: 'High digital adoption',
          value: Fmt.int_(d.highAdoption),
          hint: 'sustained use · only where use was measured',
          icon: Icons.trending_up,
          color: AppColors.good,
        ),
        KpiTile(
          label: 'Low / no adoption',
          value: Fmt.int_(d.lowAdoption),
          hint: 'weak use despite the network · only where use was measured',
          icon: Icons.trending_down,
          color: AppColors.warning,
        ),
        KpiTile(
          label: 'Technical intervention',
          value: Fmt.int_(d.technicalIntervention),
          hint: 'gateway or most access points down, failed ports, or open critical alarms',
          icon: Icons.build_outlined,
          color: AppColors.critical,
        ),
        KpiTile(
          label: 'Adoption support',
          value: Fmt.int_(d.adoptionSupport),
          hint: 'infrastructure healthy, use still low',
          icon: Icons.school_outlined,
          color: AppColors.serious,
        ),
        KpiTile(
          label: 'Average network uptime',
          value: Fmt.ratio(d.avgUptime, decimals: 1),
          hint: d.avgUptime == null
              ? 'needs several checks in a day before a share means anything'
              : 'across the schools checked often enough to tell',
          icon: Icons.timeline,
        ),
        KpiTile(
          label: 'Active client devices',
          value: Fmt.int_(d.activeUsers),
          hint: 'mean daily unique devices · not unique people',
          icon: Icons.group_outlined,
        ),
        KpiTile(
          label: 'Open critical incidents',
          value: Fmt.int_(d.openCriticalIncidents),
          hint: 'unresolved critical alarms',
          icon: Icons.warning_amber_outlined,
          color: d.openCriticalIncidents > 0 ? AppColors.critical : AppColors.muted,
        ),
        KpiTile(
          label: 'Networks in the account',
          value: Fmt.int_(d.networks),
          hint: d.unlinkedNetworks == 0 ? 'all matched to a school' : '${Fmt.int_(d.unlinkedNetworks)} not matched to a school',
          icon: Icons.router_outlined,
        ),
      ],
    );
  }
}

/// Section 10 — the infrastructure × adoption matrix.
class AdoptionMatrixCard extends StatelessWidget {
  const AdoptionMatrixCard({super.key, required this.insights, this.onTap});

  final NetworkInsights insights;
  final void Function(AdoptionQuadrant quadrant)? onTap;

  @override
  Widget build(BuildContext context) {
    final q = insights.quadrants;
    Widget cell(AdoptionQuadrant quadrant, Color color) {
      final n = q[quadrant] ?? 0;
      return Expanded(
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(quadrant),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.int_(n), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                Text(quadrant.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(quadrant.description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return SectionCard(
      title: 'Infrastructure × adoption',
      subtitle: 'Separates schools needing maintenance or ISP action from those needing training and leadership support',
      child: Column(
        children: [
          Row(children: [
            cell(AdoptionQuadrant.constrained, AppColors.serious),
            cell(AdoptionQuadrant.active, AppColors.good),
          ]),
          Row(children: [
            cell(AdoptionQuadrant.technical, AppColors.critical),
            cell(AdoptionQuadrant.adoptionSupport, AppColors.warning),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('← infrastructure unhealthy', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text('infrastructure healthy →', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if ((q[AdoptionQuadrant.unknown] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MutedNote(
                '${Fmt.int_(q[AdoptionQuadrant.unknown])} schools cannot be placed yet: the usage axis needs a client '
                'count or traffic figure, and nothing has been measured for them so far.',
              ),
            ),
        ],
      ),
    );
  }
}

/// Section 9 — the Technology Adoption Index and the weight behind it.
class AdoptionIndexCard extends StatelessWidget {
  const AdoptionIndexCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final schools = insights.schools.where((s) => s.index != null).toList();
    if (schools.isEmpty) {
      return const SectionCard(
        title: 'Technology Adoption Index',
        child: EmptyState(message: 'No school has enough data to be scored yet.', icon: Icons.insights_outlined),
      );
    }
    final mean = schools.map((s) => s.index!).reduce((a, b) => a + b) / schools.length;
    final template = schools.first.components;
    final coverage = schools.first.availableWeight;

    // Mean of each component across the schools that have it.
    final rows = <(String, double, Color?)>[];
    for (final c in template) {
      final vals = schools.map((s) => s.scoreOf(c.label)).whereType<double>().toList();
      if (vals.isEmpty) continue;
      rows.add((c.label, vals.reduce((a, b) => a + b) / vals.length, null));
    }

    return SectionCard(
      title: 'Technology Adoption Index',
      subtitle: 'Mean ${mean.toStringAsFixed(0)} / 100 across ${Fmt.int_(schools.length)} scored schools · diagnostic, not a ranking',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The framework's component names are long; give them room.
          HorizontalBars(items: rows, maxValue: 100, labelWidth: 210, formatter: (v) => v.toStringAsFixed(0)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('Weight the index could be computed on', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          RatioMeter(value: coverage, label: '${Fmt.ratio(coverage)} of the framework weight', color: AppColors.unicefCyan),
          const SizedBox(height: 8),
          for (final c in template.where((c) => !c.isAvailable))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${c.label} · ${Fmt.ratio(c.weight)} of the weight · needs ${c.missingSource}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          const MutedNote(
            'Components without a source are left out and the remaining weights are renormalised, so a school is never '
            'marked down for data nobody collected. The score is shown with its components so a weak result can be read.',
          ),
        ],
      ),
    );
  }
}

/// Section 2 — infrastructure health across the portfolio.
class InfrastructureCard extends StatelessWidget {
  const InfrastructureCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    final kinds = [GwnDeviceKind.router, GwnDeviceKind.networkSwitch, GwnDeviceKind.accessPoint];
    final poeFailed = d.schools.fold<int>(0, (a, s) => a + s.poePortsFailed);
    final portErrors = d.schools.fold<int>(0, (a, s) => a + s.portsError);
    final fwTotal = d.schools.fold<int>(0, (a, s) => a + s.firmwareTotal);
    final fwOk = d.schools.fold<int>(0, (a, s) => a + s.firmwareCompliant);

    return SectionCard(
      title: 'Infrastructure health',
      subtitle: 'Gateway, switches and access points reported by the cloud',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Availability(
                label: k.label,
                online: d.devicesOnlineByKind[k] ?? 0,
                total: d.devicesByKind[k] ?? 0,
              ),
            ),
          const Divider(height: 20),
          InfoRow('PoE ports failed', Fmt.int_(poeFailed)),
          InfoRow('LAN ports with errors', Fmt.int_(portErrors)),
          InfoRow('Firmware compliance', fwTotal == 0 ? '–' : '${Fmt.ratio(fwOk / fwTotal)} · $fwOk of $fwTotal devices'),
          const SizedBox(height: 8),
          const MutedNote(
            'Firmware compliance counts devices on the account\'s most common release, which stands in for an approved '
            'baseline until one is configured. Configuration compliance needs an expected VLAN / SSID / firewall '
            'baseline to compare against and is not computed.',
          ),
        ],
      ),
    );
  }
}

class _Availability extends StatelessWidget {
  const _Availability({required this.label, required this.online, required this.total});
  final String label;
  final int online;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? null : online / total;
    final color = share == null
        ? AppColors.muted
        : share >= 0.95
            ? AppColors.good
            : share >= 0.8
                ? AppColors.warning
                : AppColors.critical;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(
              total == 0 ? 'none' : '${Fmt.int_(online)} of ${Fmt.int_(total)} · ${Fmt.ratio(share)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        RatioMeter(value: share ?? 0, color: color),
      ],
    );
  }
}

/// Sections 3 and 4 — portfolio uptime, clients and traffic per day.
class NetworkTrendCard extends StatelessWidget {
  const NetworkTrendCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final d = insights;
    if (d.dailyClients.isEmpty) {
      return const SectionCard(
        title: 'Use over time',
        child: EmptyState(
          message: 'No daily counters yet. The cloud exposes no usage history, so this series is built from the '
              'app\'s own observations — it fills in from the next sync onwards, one point per day.',
          icon: Icons.show_chart,
        ),
      );
    }
    final p = ChartPalette.of(context);
    final groups = [
      for (var i = 0; i < d.dailyClients.length; i++)
        BarGroup(
          label: Fmt.shortDay(d.dailyClients[i].day),
          fullLabel: '${Fmt.shortDay(d.dailyClients[i].day)} · ${Fmt.int_(d.dailyClients[i].clients)} devices · ${Fmt.bytes(d.dailyBytes[i].bytes)}',
          values: [d.dailyClients[i].clients.toDouble()],
        ),
    ];
    return ChartOrTable(
      title: 'Client devices per day',
      subtitle: 'Unique devices seen across every school, last ${d.days} days',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnergyBarChart(
            seriesLabels: const ['Devices'],
            seriesColors: [p.load],
            groups: groups,
            height: 220,
            maxLabels: 10,
            unitFormatter: (v) => Fmt.int_(v),
            emptyMessage: 'No client counts recorded yet',
          ),
          const MutedNote(
            'Unique device identifiers are a proxy for devices, not for students: modern phones randomise their MAC '
            'address unless they authenticate, so a device count can move without the number of users changing.',
          ),
        ],
      ),
      table: ChartTable(
        columns: const ['Day', 'Devices', 'Traffic', 'Mean uptime'],
        rows: [
          for (var i = d.dailyClients.length - 1; i >= 0; i--)
            [
              Fmt.shortDay(d.dailyClients[i].day),
              Fmt.int_(d.dailyClients[i].clients),
              Fmt.bytes(d.dailyBytes[i].bytes),
              Fmt.ratio(d.dailyUptime.where((u) => u.day == d.dailyClients[i].day).firstOrNull?.uptime, decimals: 1),
            ],
        ],
      ),
    );
  }
}

/// Section 4 — where the traffic goes, by SSID.
class SsidSplitCard extends StatelessWidget {
  const SsidSplitCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final rows = insights.ssidTraffic;
    if (rows.isEmpty) {
      return const SectionCard(
        title: 'Traffic by SSID',
        child: EmptyState(
          message: 'This GWN API version lists SSIDs but reports no traffic against them, so the staff / student / '
              'admin split cannot be computed from it.',
          icon: Icons.wifi_tethering,
        ),
      );
    }
    final p = ChartPalette.of(context);
    final total = rows.fold<int>(0, (a, r) => a + r.bytes);
    return SectionCard(
      title: 'Traffic by SSID',
      subtitle: 'Separates staff, student and admin use over the last ${insights.days} days',
      child: DonutChart(
        slices: [
          for (var i = 0; i < rows.length && i < 6; i++)
            (rows[i].ssid, rows[i].bytes.toDouble(), p.categorical[i % p.categorical.length]),
        ],
        centerLabel: 'Total',
        centerValue: Fmt.bytes(total),
        valueFormatter: Fmt.bytes,
      ),
    );
  }
}

/// Per-governorate roll-up.
class NetworkRegionCard extends StatelessWidget {
  const NetworkRegionCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) {
    final rows = insights.byRegion;
    if (rows.isEmpty) {
      return const SectionCard(
        title: 'By governorate',
        child: EmptyState(message: 'No network could be matched to a school yet.', icon: Icons.map_outlined),
      );
    }
    return SectionCard(
      title: 'By governorate',
      subtitle: 'Schools with a monitored network, and how they are doing',
      child: ChartTable(
        columns: const ['Governorate', 'Schools', 'Connected', 'Active', 'Mean index', 'Mean uptime'],
        rows: [
          for (final r in rows)
            [
              r.region,
              Fmt.int_(r.schools),
              Fmt.int_(r.connected),
              Fmt.int_(r.active),
              r.meanIndex == null ? '–' : r.meanIndex!.toStringAsFixed(0),
              Fmt.ratio(r.meanUptime, decimals: 1),
            ],
        ],
      ),
    );
  }
}

/// Section 11 — what the dashboard cannot answer, and what it would take.
class MissingSourcesCard extends StatelessWidget {
  const MissingSourcesCard({super.key, required this.insights});

  final NetworkInsights insights;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Indicators that need another source',
        subtitle: 'From the framework, but not answerable from the network account alone',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in insights.missingSources)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.indicator, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Needs: ${m.source}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            const MutedNote(
              'These are listed rather than shown empty so the dashboard says why a figure is absent. Connecting any of '
              'them fills in its indicators and raises the share of the index weight that can be scored.',
            ),
          ],
        ),
      );
}
