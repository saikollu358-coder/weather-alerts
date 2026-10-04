import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/application/dashboard_providers.dart';
import '../application/location_providers.dart';
import '../application/location_state.dart';
import 'locations_map_view.dart';

/// Map tab of the dashboard shell: a map of the device's current position with
/// optional precipitation radar.
///
/// There is nothing to add or choose here: the only location is wherever the
/// device is, so this tab is the map itself plus whatever the location
/// permission state requires.
class LocationsTab extends ConsumerWidget {
  const LocationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(locationControllerProvider);

    // Only gate on states where the map genuinely cannot render. Transient
    // states such as [LocationStatus.waitingPermission] still show the map
    // shell so the tab does not flash between layouts while GPS warms up.
    switch (locationState.status) {
      case LocationStatus.deniedForever:
      case LocationStatus.unavailable:
      case LocationStatus.denied:
        return _LocationGate(state: locationState);
      case LocationStatus.unknown:
      case LocationStatus.waitingPermission:
      case LocationStatus.ready:
      case LocationStatus.error:
        return const LocationsMapView();
    }
  }
}

/// Shown instead of the map when the app cannot know where it is.
class _LocationGate extends ConsumerWidget {
  const _LocationGate({required this.state});

  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(dashboardControllerProvider.notifier);

    final (IconData icon, String message) = switch (state.status) {
      LocationStatus.deniedForever => (
          Icons.location_disabled,
          'Location permission was denied permanently. Allow it in system '
              'Settings to see your position on the map.',
        ),
      LocationStatus.unavailable => (
          Icons.location_off_outlined,
          'Location services are turned off. Turn them on to see your position '
              'on the map.',
        ),
      _ => (
          Icons.location_disabled,
          'Location permission is needed to show your position on the map.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (state.status == LocationStatus.deniedForever)
              OutlinedButton.icon(
                key: const ValueKey('open_settings_button'),
                onPressed: controller.openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Settings'),
              )
            else
              FilledButton.icon(
                key: const ValueKey('allow_location_button'),
                onPressed: controller.requestPermission,
                icon: const Icon(Icons.my_location),
                label: const Text('Allow location access'),
              ),
          ],
        ),
      ),
    );
  }
}