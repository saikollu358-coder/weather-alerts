import 'daily_forecast.dart';
import 'hourly_forecast.dart';
import 'weather_snapshot.dart';

/// A complete weather data set for one location: current conditions plus
/// hourly and daily forecasts.
class WeatherBundle {
  const WeatherBundle({
    required this.locationKey,
    required this.current,
    required this.hourly,
    required this.daily,
    required this.fetchedAtUtc,
    required this.expiresAtUtc,
    this.dataSource = 'open-meteo',
  });

  /// Stable key identifying the location (e.g. `lat,lng`).
  final String locationKey;

  /// Current conditions snapshot.
  final CurrentWeather current;

  /// Hourly forecast points (typically 168h / 7 days).
  final List<HourlyForecastPoint> hourly;

  /// Daily forecast summaries (typically 7 days).
  final List<DailyForecastPoint> daily;

  /// When the payload was captured (UTC).
  final DateTime fetchedAtUtc;

  /// When the bundle as a whole is considered stale (UTC).
  final DateTime expiresAtUtc;

  /// Provider/source of the data.
  final String dataSource;

  /// True once the data has passed its freshness window.
  bool isStale({DateTime? now}) =>
      (now ?? DateTime.now()).toUtc().isAfter(expiresAtUtc.toUtc());

  @override
  String toString() =>
      'WeatherBundle($locationKey, ${current.temperatureC.toStringAsFixed(1)}°C, '
      'hourly ×${hourly.length}, daily ×${daily.length}, '
      'fetched ${fetchedAtUtc.toIso8601String()})';
}