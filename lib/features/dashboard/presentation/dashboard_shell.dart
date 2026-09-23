import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alerts/presentation/alerts_tab.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../location/presentation/locations_tab.dart';
import '../../../routing/app_routes.dart';
import 'dashboard_home_tab.dart';

/// Post-authentication shell for the Phase 7 dashboard pipeline.
///
/// Hosts the three pipeline tabs (home weather, alerts, locations) in an
/// [IndexedStack] behind a Material 3 [NavigationBar]. Profile is reachable
/// from the app bar.
class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _index = 0;

  static const List<String> _titles = ['Weather', 'Alerts', 'Locations'];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardHomeTab(
        onOpenLocations: () => setState(() => _index = 2),
        onOpenAlerts: () => setState(() => _index = 1),
      ),
      const AlertsTab(),
      LocationsTab(
        onSelect: (record) {
          ref.read(dashboardControllerProvider.notifier).selectLocation(record);
          setState(() => _index = 0);
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            key: const ValueKey('settings_button'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(RoutePath.settings),
          ),
          IconButton(
            key: const ValueKey('profile_button'),
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push(RoutePath.profile),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            key: ValueKey('nav_weather'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Weather',
          ),
          NavigationDestination(
            key: ValueKey('nav_alerts'),
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Alerts',
          ),
          NavigationDestination(
            key: ValueKey('nav_locations'),
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Locations',
          ),
        ],
      ),
    );
  }
}