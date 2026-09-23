import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../data/repositories/local_repository_providers.dart';
import '../../domain/services/weather_service.dart';
import '../http_client_provider.dart';
import 'open_meteo_weather_service.dart';

/// Weather acquisition service, cache-first and backed by Open-Meteo.
final weatherServiceProvider = Provider<WeatherService>(
  (ref) => OpenMeteoWeatherService(
    config: ref.watch(appConfigProvider),
    client: ref.watch(httpClientProvider),
    cache: ref.watch(weatherCacheRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);