import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../domain/services/geocoding_service.dart';
import '../../domain/services/location_service.dart';
import '../http_client_provider.dart';
import 'geocoding_api_service.dart';
import 'geolocator_location_service.dart';

/// Device location (GPS) service, backed by the geolocator plugin.
final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(logger: ref.watch(appLoggerProvider)),
);

/// Place search / reverse geocoding, backed by Open-Meteo.
final geocodingServiceProvider = Provider<GeocodingService>(
  (ref) => GeocodingApiService(
    config: ref.watch(appConfigProvider),
    client: ref.watch(httpClientProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);