import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/entities/geo_position.dart';
import '../../../domain/entities/monitored_location_record.dart';
import '../../../services/weather_maps/weather_map_layers.dart';
import '../../../services/weather_maps/weather_map_providers.dart';
import '../application/location_providers.dart';

/// Map of the saved monitored locations, shown in the Locations tab.
///
/// Uses a free OpenStreetMap base layer plus optional weather overlays:
/// precipitation radar (RainViewer, free) and, when an OpenWeatherMap key is
/// supplied at build time, temperature and wind layers. Tapping a marker
/// selects that location for the weather dashboard.
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
  final MapController _mapController = MapController();
  WeatherMapLayer _selectedLayer = WeatherMapLayer.radar;
  bool _cameraFitDone = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layers = ref.watch(weatherMapLayersProvider);
    final radarAsync = ref.watch(rainViewerRadarProvider);
    final locationState = ref.watch(locationControllerProvider);
    final myPosition = locationState.position;

    if (widget.locations.isEmpty) {
      return const _MapMessage(
        icon: Icons.place_outlined,
        message: 'No saved locations to show on the map yet.',
      );
    }

    final layerSpec = layers.tileSpec(_selectedLayer);
    final isRadarLoading =
        _selectedLayer == WeatherMapLayer.radar && radarAsync.isLoading;

    return Column(
      children: [
        _LayerSelector(
          layers: layers,
          selected: _selectedLayer,
          hint: _activeHint(layers),
          onSelected: (layer) => setState(() => _selectedLayer = layer),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                key: const ValueKey('locations_map'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter(),
                  initialZoom: _initialZoom(),
                  onMapReady: _onMapReady,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.flingAnimation |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: WeatherMapLayers.baseSpec.urlTemplate,
                    userAgentPackageName: 'com.weatheralerts.app',
                  ),
                  if (layerSpec != null &&
                      _selectedLayer != WeatherMapLayer.base)
                    Opacity(
                      opacity: layerSpec.opacity,
                      child: TileLayer(
                        urlTemplate: layerSpec.urlTemplate,
                        maxNativeZoom:
                            _selectedLayer == WeatherMapLayer.radar ? 7 : 19,
                      ),
                    ),
                  if (myPosition != null) ..._myLocationLayers(myPosition),
                  MarkerLayer(markers: _buildMarkers()),
                  const _MapAttribution(),
                ],
              ),
              if (isRadarLoading)
                const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 28,
                child: _MapControls(
                  hasPosition: myPosition != null,
                  onZoomIn: () => _zoomBy(1),
                  onZoomOut: () => _zoomBy(-1),
                  onLocate: _locateMe,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _myLocationLayers(GeoPosition position) {
    final center = LatLng(position.latitude, position.longitude);
    final accuracy = position.accuracy;
    return [
      if (accuracy != null && accuracy > 0)
        CircleLayer(
          circles: [
            CircleMarker(
              point: center,
              radius: accuracy,
              color: Colors.blue.withValues(alpha: 0.12),
              borderStrokeWidth: 1,
              borderColor: Colors.blue.withValues(alpha: 0.4),
            ),
          ],
        ),
      MarkerLayer(
        markers: [
          Marker(
            point: center,
            width: 26,
            height: 26,
            child: const Icon(
              Icons.my_location,
              key: ValueKey('my_location_marker'),
              color: Colors.blue,
              size: 24,
            ),
          ),
        ],
      ),
    ];
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final zoom = (camera.zoom + delta).clamp(2.0, 18.0);
    _mapController.move(camera.center, zoom);
  }

  void _locateMe() {
    final position = ref.read(locationControllerProvider).position;
    if (position == null) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      14,
    );
  }

  String? _activeHint(WeatherMapLayers layers) {
    if (_selectedLayer == WeatherMapLayer.radar && !layers.hasRadarTiles) {
      return 'Radar data is currently unavailable.';
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Markers
  // ------------------------------------------------------------------

  List<Marker> _buildMarkers() {
    final onSelect = widget.onSelect;
    final color = Theme.of(context).colorScheme.primary;
    return [
      for (final record in widget.locations)
        Marker(
          point: LatLng(record.latitude, record.longitude),
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            key: ValueKey('location_marker_${record.locationKey}'),
            onTap: onSelect == null ? null : () => onSelect(record),
            child: Icon(Icons.location_on, color: color, size: 40),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Camera
  // ------------------------------------------------------------------

  LatLng _initialCenter() {
    final anchor = _primaryOrFirst(widget.locations);
    if (anchor == null) return const LatLng(20, 0);
    return LatLng(anchor.latitude, anchor.longitude);
  }

  double _initialZoom() {
    return widget.locations.length == 1 ? 12 : 6;
  }

  MonitoredLocationRecord? _primaryOrFirst(
    List<MonitoredLocationRecord> locations,
  ) {
    for (final record in locations) {
      if (record.isPrimary) return record;
    }
    return locations.isEmpty ? null : locations.first;
  }

  void _onMapReady() {
    if (_cameraFitDone || widget.locations.length < 2) return;
    _cameraFitDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitToBounds();
    });
  }

  void _fitToBounds() {
    final locations = widget.locations;
    var minLat = locations.first.latitude;
    var maxLat = minLat;
    var minLng = locations.first.longitude;
    var maxLng = minLng;
    for (final record in locations) {
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

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(72),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Layer selector
// ---------------------------------------------------------------------

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.hasPosition,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
  });

  final bool hasPosition;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = IconButton.styleFrom(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
      disabledForegroundColor: scheme.onSurfaceVariant,
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('map_zoom_in'),
          icon: const Icon(Icons.add),
          tooltip: 'Zoom in',
          style: style,
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 8),
        IconButton(
          key: const ValueKey('map_zoom_out'),
          icon: const Icon(Icons.remove),
          tooltip: 'Zoom out',
          style: style,
          onPressed: onZoomOut,
        ),
        if (hasPosition) ...[
          const SizedBox(height: 8),
          IconButton(
            key: const ValueKey('map_locate'),
            icon: const Icon(Icons.my_location),
            tooltip: 'Show my location',
            style: style,
            onPressed: onLocate,
          ),
        ],
      ],
    );
  }
}

class _LayerSelector extends StatelessWidget {
  const _LayerSelector({
    required this.layers,
    required this.selected,
    required this.onSelected,
    this.hint,
  });

  final WeatherMapLayers layers;
  final WeatherMapLayer selected;
  final ValueChanged<WeatherMapLayer> onSelected;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final layer in WeatherMapLayer.values)
                ChoiceChip(
                  key: ValueKey('map_layer_${layer.name}'),
                  label: Text(layer.label),
                  selected: selected == layer,
                  onSelected: layers.supports(layer)
                      ? (_) => onSelected(layer)
                      : null,
                ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else if (!layers.hasOpenWeatherKey)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Temperature and Wind need an OpenWeatherMap key '
                '(WEATHER_ALERTS_OPENWEATHER_API_KEY) at build time.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Non-map states
// ---------------------------------------------------------------------

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomLeft,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '© OpenStreetMap contributors · RainViewer',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
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