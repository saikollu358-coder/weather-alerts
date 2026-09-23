import '../entities/weather/weather_bundle.dart';

/// Boundary for acquiring current weather and forecasts for a location.
///
/// Implementations are cache-first: they return fresh locally cached data
/// without touching the network, and fall back to fetching (and caching) from
/// the provider. Failures surface as user-safe `AppException`s.
abstract interface class WeatherService {
  /// Loads the weather data set for the location at [latitude]/[longitude].
  ///
  /// [locationKey] matches the storage key used for the local cache.
  /// Set [forceRefresh] to bypass a fresh cache.
  Future<WeatherBundle> load({
    required String locationKey,
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  });
}