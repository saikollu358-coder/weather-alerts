import '../entities/cached_forecast_entry.dart';
import '../entities/cached_weather_entry.dart';

/// Repository boundary for locally cached weather observations and forecasts.
///
/// Implementations store serialized payloads in SQLite so the app remains
/// useful offline. Consumers must always check staleness and present cached
/// data clearly labelled, never as live weather.
abstract interface class WeatherCacheRepository {
  /// Persists (or replaces) the cached current weather for a location.
  Future<void> saveCurrentWeather(CachedWeatherEntry entry);

  /// Returns the cached current weather for a location, or null.
  Future<CachedWeatherEntry?> currentWeather(String locationKey);

  /// Whether a fresh enough current-weather snapshot exists at [at].
  Future<bool> hasFreshCurrentWeather(
    String locationKey,
    Duration maxAge, {
    DateTime? at,
  });

  /// Persists (or replaces) the cached forecast for a location and type.
  Future<void> saveForecast(CachedForecastEntry entry);

  /// Returns the cached forecast for a location and type, or null.
  Future<CachedForecastEntry?> forecast(
    String locationKey,
    ForecastType type,
  );

  /// Whether a fresh enough forecast snapshot exists at [at].
  Future<bool> hasFreshForecast(
    String locationKey,
    ForecastType type,
    Duration maxAge, {
    DateTime? at,
  });

  /// Removes all cached data (current + forecasts) for a location.
  Future<void> deleteLocation(String locationKey);

  /// Removes all cached weather and forecast data.
  Future<void> clear();
}