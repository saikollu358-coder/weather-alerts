import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../http_client_provider.dart';
import 'rain_viewer_service.dart';
import 'weather_map_layers.dart';

/// Shared [RainViewerService]; overridable in tests with a fake client.
final rainViewerServiceProvider = Provider<RainViewerService>(
  (ref) => RainViewerService(
    client: ref.watch(httpClientProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Radar tile index, refreshed once per provider scope.
final rainViewerRadarProvider = FutureProvider<RainViewerRadar?>(
  (ref) => ref.watch(rainViewerServiceProvider).fetchRadarFrames(),
);

/// Resolves which weather layers can be shown from the active config and the
/// current radar state.
final weatherMapLayersProvider = Provider<WeatherMapLayers>(
  (ref) => WeatherMapLayers(
    config: ref.watch(appConfigProvider),
    radar: ref.watch(rainViewerRadarProvider).value,
  ),
);