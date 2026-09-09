import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import 'sync_status_bar.dart';

/// Tablet shell: navigation rail on the left, sync status strip on top.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    (path: '/dashboard', icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (path: '/analytics', icon: Icons.insights_outlined, selected: Icons.insights, label: 'Analytics'),
    (path: '/stations', icon: Icons.school_outlined, selected: Icons.school, label: 'Schools'),
    (path: '/alarms', icon: Icons.notifications_outlined, selected: Icons.notifications, label: 'Alarms'),
    (path: '/map', icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
    (path: '/settings', icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
  ];

  int get _index {
    final i = _destinations.indexWhere((d) => location == d.path || location.startsWith('${d.path}/'));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final insights = ref.watch(fleetInsightsProvider).value;
    final alarmCount = insights?.activeAlertsByLevel.values.fold(0, (a, b) => a + b) ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            minExtendedWidth: 190,
            selectedIndex: _index,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.wb_sunny, color: Colors.white),
                  ),
                  if (wide) ...[
                    const SizedBox(height: 8),
                    Text('School Solar', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('UNICEF Lebanon', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: d.path == '/alarms' && alarmCount > 0
                      ? Badge(label: Text('$alarmCount'), child: Icon(d.icon))
                      : Icon(d.icon),
                  selectedIcon: d.path == '/alarms' && alarmCount > 0
                      ? Badge(label: Text('$alarmCount'), child: Icon(d.selected))
                      : Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const SyncStatusBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
