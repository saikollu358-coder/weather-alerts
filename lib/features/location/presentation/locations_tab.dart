import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/monitored_location_record.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/location_providers.dart';
import '../application/locations_state.dart';
import 'locations_map_view.dart';

/// Saved-location presentation mode: classic list or the map view.
enum _LocationsView { list, map }

/// Locations tab of the dashboard shell: saved monitored locations with
/// use / make-primary / remove actions and an add-current-location flow,
/// plus a Google Map of the saved points.
///
/// The list is driven by [locationsControllerProvider]; widgets never touch
/// the location repository directly.
class LocationsTab extends ConsumerStatefulWidget {
  const LocationsTab({super.key, required this.onSelect});

  /// Called when the user wants to monitor a saved location (switches the
  /// shell back to the home tab).
  final ValueChanged<MonitoredLocationRecord> onSelect;

  @override
  ConsumerState<LocationsTab> createState() => _LocationsTabState();
}

class _LocationsTabState extends ConsumerState<LocationsTab> {
  bool _isAdding = false;
  _LocationsView _view = _LocationsView.list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(locationsControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('add_current_location_button'),
                  onPressed: _isAdding ? null : _addCurrent,
                  icon: _isAdding
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _isAdding
                        ? 'Getting your current location...'
                        : 'Add current location',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_LocationsView>(
                key: const ValueKey('locations_view_toggle'),
                segments: const [
                  ButtonSegment(
                    value: _LocationsView.list,
                    label: Text('List'),
                    icon: Icon(Icons.view_list_outlined),
                  ),
                  ButtonSegment(
                    value: _LocationsView.map,
                    label: Text('Map'),
                    icon: Icon(Icons.map_outlined),
                  ),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _view = selection.first),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(theme, state)),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Body
  // ------------------------------------------------------------------

  Widget _buildBody(ThemeData theme, LocationsState state) {
    switch (state.status) {
      case LocationsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LocationsStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: ref.read(locationsControllerProvider.notifier).refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      case LocationsStatus.ready:
        if (_view == _LocationsView.map) {
          return LocationsMapView(
            locations: state.locations,
            onSelect: widget.onSelect,
          );
        }
        final records = state.locations;
        if (records.isEmpty) {
          return _EmptyLocations(
            icon: Icons.place_outlined,
            message: 'No saved locations yet.',
          );
        }
        return RefreshIndicator(
          onRefresh: ref.read(locationsControllerProvider.notifier).refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: records.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final record = records[index];
              return _LocationTile(
                record: record,
                onSelect: () => widget.onSelect(record),
                onSetPrimary: () => ref
                    .read(locationsControllerProvider.notifier)
                    .setPrimary(record.id!),
                onRemove: () async {
                  final id = record.id!;
                  final confirmed = await _confirmRemove(context);
                  if (confirmed) {
                    await ref
                        .read(locationsControllerProvider.notifier)
                        .remove(id);
                  }
                },
              );
            },
          ),
        );
    }
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _addCurrent() async {
    setState(() => _isAdding = true);
    try {
      final saved = await ref
          .read(dashboardControllerProvider.notifier)
          .useCurrentGps();
      if (!mounted) return;
      if (saved != null) {
        await ref.read(locationsControllerProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current location added.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission required to add the current '
                'location.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove location?'),
        content: const Text(
          'This removes the saved location and stops monitoring it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ------------------------------------------------------------------
// Sub-widgets
// ------------------------------------------------------------------

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.record,
    required this.onSelect,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final MonitoredLocationRecord record;
  final VoidCallback onSelect;
  final VoidCallback onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(
          record.isPrimary ? Icons.home_rounded : Icons.place_outlined,
          color: record.isPrimary
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(record.name, style: theme.textTheme.titleMedium),
        subtitle: Text(
          '${record.latitude.toStringAsFixed(4)}, '
          '${record.longitude.toStringAsFixed(4)}'
          '${record.isMonitored ? ' · monitored' : ''}',
        ),
        onTap: onSelect,
        trailing: PopupMenuButton<String>(
          tooltip: 'Location actions',
          onSelected: (value) => switch (value) {
            'use' => onSelect(),
            'primary' => onSetPrimary(),
            'remove' => onRemove(),
            _ => null,
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'use', child: Text('Use for weather')),
            if (!record.isPrimary)
              const PopupMenuItem(
                value: 'primary',
                child: Text('Make primary'),
              ),
            if (record.id != null)
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class _EmptyLocations extends StatelessWidget {
  const _EmptyLocations({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}