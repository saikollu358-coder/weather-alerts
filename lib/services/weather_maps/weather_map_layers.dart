import '../../core/config/app_config.dart';
import 'rain_viewer_service.dart';

/// Overlay layers available on the base map.
enum WeatherMapLayer {
  base('Base'),
  radar('Radar'),
  temperature('Temperature'),
  wind('Wind');

  const WeatherMapLayer(this.label);

  final String label;

  /// Named OpenWeatherMap tile layer, or null for base/radar.
  String? get openWeatherTileLayer => switch (this) {
        WeatherMapLayer.temperature => 'temp_new',
        WeatherMapLayer.wind => 'wind_new',
        _ => null,
      };

  /// Whether [openWeatherTileLayer] applies to this layer.
  bool get requiresOpenWeatherKey => openWeatherTileLayer != null;
}

/// A resolved tile layer ready for a `TileLayer` in `FlutterMap`.
class WeatherTileSpec {
  const WeatherTileSpec({required this.urlTemplate, this.opacity = 0.7});

  final String urlTemplate;
  final double opacity;
}

/// Determines which weather layers can be displayed from the active config
/// and current radar state. Pure and deterministic; no network calls here.
class WeatherMapLayers {
  WeatherMapLayers({required this.config, this.radar});

  /// OpenStreetMap base layer; free with attribution and always available.
  static const WeatherTileSpec baseSpec = WeatherTileSpec(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    opacity: 1,
  );

  final AppConfig config;
  final RainViewerRadar? radar;

  bool get hasOpenWeatherKey => config.openWeatherApiKey.isNotEmpty;

  bool get hasRadarTiles {
    final radar = this.radar;
    return radar != null &&
        radar.host.isNotEmpty &&
        radar.latestFrame != null;
  }

  /// Whether [layer] can be rendered right now.
  bool supports(WeatherMapLayer layer) {
    return switch (layer) {
      WeatherMapLayer.base => true,
      WeatherMapLayer.radar => hasRadarTiles,
      _ => hasOpenWeatherKey,
    };
  }

  /// Tile spec for [layer], or null when [supports] is false.
  WeatherTileSpec? tileSpec(WeatherMapLayer layer) {
    switch (layer) {
      case WeatherMapLayer.base:
        return baseSpec;
      case WeatherMapLayer.radar:
        final radar = this.radar;
        if (!hasRadarTiles) return null;
        final host = radar!.host;
        final frame = radar.latestFrame!;
        return WeatherTileSpec(
          // Universal-blue scheme (color 2), snow tint (options 1_1).
          urlTemplate: '$host${frame.path}/256/{z}/{x}/{y}/2/1_1.png',
        );
      default:
        if (!hasOpenWeatherKey) return null;
        return WeatherTileSpec(
          urlTemplate:
              'https://tile.openweathermap.org/map/'
              '${layer.openWeatherTileLayer}/{z}/{x}/{y}.png'
              '?appid=${config.openWeatherApiKey}',
        );
    }
  }
}