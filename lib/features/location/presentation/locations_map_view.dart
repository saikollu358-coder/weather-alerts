import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../domain/entities/monitored_location_record.dart';

/// Map of the saved monitored locations, shown in the Locations tab.
///
/// The map only renders when a Google Maps API key was supplied at build time
/// (`WEATHER_ALERTS_GOOGLE_MAPS_API_KEY`); without one the widget falls back
/// to a setup hint so the screen stays useful instead of showing a blank map.
/// Tapping a marker selects that location for the weather dashboard.
class LocationsMapView extends ConsumerStatefulWidget {
  const LocationsMapView({
    super.key,
    required this.locations,
    this.onSelect,
  });

  final List<MonitoredLocationRecord> locations;

  final ValueChanged<MonitoredLocationRecord>? onSelect;

  @override
  ConsumerState<LocationsMapView> createState() => _LocationsMapViewState();
}

class _LocationsMapViewState extends ConsumerState<LocationsMapView> {
  bool _cameraFitDone = false;

  @override
  Widget build(BuildContext context) {
    final apiKey = ref.watch(appConfigProvider).googleMapsApiKey;
    if (apiKey.isEmpty) return const _MapSetupHint();
    if (widget.locations.isEmpty) {
      return const _MapMessage(
        icon: Icons.place_outlined,
        message: 'No saved locations to show on the map yet.',
      );
    }

    return GoogleMap(
      key: const ValueKey('locations_map'),
      initialCameraPosition: _initialCamera(),
      markers: _buildMarkers(),
      onMapCreated: _onMapCreated,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  // ------------------------------------------------------------------
  // Markers
  // ------------------------------------------------------------------

  Set<Marker> _buildMarkers() {
    final onSelect = widget.onSelect;
    return {
      for (final record in widget.locations)
        Marker(
          markerId: MarkerId(record.locationKey),
          position: LatLng(record.latitude, record.longitude),
          infoWindow: InfoWindow(
            title: record.name,
            snippet:
                '${record.latitude.toStringAsFixed(4)}, '
                '${record.longitude.toStringAsFixed(4)}',
            onTap: onSelect == null ? null : () => onSelect(record),
          ),
          onTap: onSelect == null ? null : () => onSelect(record),
        ),
    };
  }

  // ------------------------------------------------------------------
  // Camera
  // ------------------------------------------------------------------

  CameraPosition _initialCamera() {
    final locations = widget.locations;
    final anchor = _primaryOrFirst(locations);
    if (anchor == null) {
      return const CameraPosition(target: LatLng(20, 0), zoom: 2);
    }
    return CameraPosition(
      target: LatLng(anchor.latitude, anchor.longitude),
      zoom: locations.length == 1 ? 12 : 6,
    );
  }

  MonitoredLocationRecord? _primaryOrFirst(
    List<MonitoredLocationRecord> locations,
  ) {
    for (final record in locations) {
      if (record.isPrimary) return record;
    }
    return locations.isEmpty ? null : locations.first;
  }

  void _onMapCreated(GoogleMapController controller) {
    if (_cameraFitDone || widget.locations.length < 2) return;
    _cameraFitDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitToBounds(controller);
    });
  }

  void _fitToBounds(GoogleMapController controller) {
    var minLat = widget.locations.first.latitude;
    var maxLat = minLat;
    var minLng = widget.locations.first.longitude;
    var maxLng = minLng;
    for (final record in widget.locations) {
      minLat = math.min(minLat, record.latitude);
      maxLat = math.max(maxLat, record.latitude);
      minLng = math.min(minLng, record.longitude);
      maxLng = math.max(maxLng, record.longitude);
    }

    // Keep a minimum span so coincident points still produce a valid bound.
    if (maxLat - minLat < 0.02) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if (maxLng - minLng < 0.02) {
      minLng -= 0.01;
      maxLng += 0.01;
    }

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Non-map states
// ---------------------------------------------------------------------

class _MapSetupHint extends StatelessWidget {
  const _MapSetupHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Map not configured',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Provide a Google Maps API key when building the app '
              '(WEATHER_ALERTS_GOOGLE_MAPS_API_KEY) to enable the map view.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message});

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
