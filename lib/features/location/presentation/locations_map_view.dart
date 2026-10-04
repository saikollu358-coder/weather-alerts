import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/entities/current_location.dart';
import '../../../services/weather_maps/weather_map_layers.dart';
import '../../../services/weather_maps/weather_map_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/location_providers.dart';

/// Map of the device's current position, shown in the Map tab.
///
/// Uses a free OpenStreetMap base layer plus optional weather overlays:
/// precipitation radar (RainViewer, free) and, when an OpenWeatherMap key is
/// supplied at build time, temperature and wind layers. There is only ever one
/// point on this map: wherever the device currently is.
///
/// The camera is not moved automatically as GPS updates arrive — the marker
/// follows the user, and the locate button re-centres on demand. Snapping the
/// camera to every streamed fix would fight anyone trying to pan elsewhere.
class LocationsMapView extends ConsumerStatefulWidget {
  const LocationsMapView({super.key});

  @override
  ConsumerState<LocationsMapView> createState() => _LocationsMapViewState();
}

class _LocationsMapViewState extends ConsumerState<LocationsMapView> {
  final MapController _mapController = MapController();

  /// Radar is the default because it is the only weather overlay that works
  /// without a paid API key.
  WeatherMapLayer _selectedLayer = WeatherMapLayer.radar;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layers = ref.watch(weatherMapLayersProvider);
    final radarAsync = ref.watch(rainViewerRadarProvider);

    final position = ref.watch(locationControllerProvider).position;
    // Prefer the dashboard's resolved location so the banner shows the same
    // place name as the weather tab; fall back to the raw fix before the
    // pipeline has resolved one.
    final resolved = ref.watch(
      dashboardControllerProvider.select((state) => state.location),
    );
    final current = resolved ??
        (position == null ? null : CurrentLocation.fromPosition(position));

    if (current == null) {
      return const _MapMessage(
        icon: Icons.my_location,
        message: 'Waiting for your current position…',
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
                  initialCenter: _centerOf(current),
                  initialZoom: 12,
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
                  ..._positionLayers(current),
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
                  onZoomIn: () => _zoomBy(1),
                  onZoomOut: () => _zoomBy(-1),
                  onLocate: () => _recenter(current),
                ),
              ),
              _PlaceBanner(location: current),
            ],
          ),
        ),
      ],
    );
  }

  LatLng _centerOf(CurrentLocation location) =>
      LatLng(location.latitude, location.longitude);

  List<Widget> _positionLayers(CurrentLocation location) {
    final center = _centerOf(location);
    final accuracy = location.position.accuracy;
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

  /// Recentres on [location].
  void _recenter(CurrentLocation location) {
    _mapController.move(_centerOf(location), 14);
  }

  String? _activeHint(WeatherMapLayers layers) =>
      _selectedLayer == WeatherMapLayer.radar && !layers.hasRadarTiles
          ? 'Radar data is currently unavailable.'
          : null;
}

// ---------------------------------------------------------------------
// Overlays
// ---------------------------------------------------------------------

class _PlaceBanner extends StatelessWidget {
  const _PlaceBanner({required this.location});

  final CurrentLocation location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                location.label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
  });

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
        const SizedBox(height: 8),
        IconButton(
          key: const ValueKey('map_locate'),
          icon: const Icon(Icons.my_location),
          tooltip: 'Show my location',
          style: style,
          onPressed: onLocate,
        ),
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
                  onSelected:
                      layers.supports(layer) ? (_) => onSelected(layer) : null,
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