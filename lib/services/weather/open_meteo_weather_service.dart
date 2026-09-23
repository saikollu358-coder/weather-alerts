import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/cached_forecast_entry.dart';
import '../../domain/entities/cached_weather_entry.dart';
import '../../domain/entities/weather/daily_forecast.dart';
import '../../domain/entities/weather/hourly_forecast.dart';
import '../../domain/entities/weather/weather_bundle.dart';
import '../../domain/entities/weather/weather_snapshot.dart';
import '../../domain/repositories/weather_cache_repository.dart';
import '../../domain/services/weather_service.dart';

/// [WeatherService] backed by the Open-Meteo forecast API.
///
/// One `/forecast` call returns current, hourly and daily data; each slice is
/// cached separately so a fresh slice can be served while another is refetched.
class OpenMeteoWeatherService implements WeatherService {
  OpenMeteoWeatherService({
    required this.config,
    required this.client,
    required this.cache,
    required this.logger,
  });

  /// Source identifier written to cached entries.
  static const String dataSource = 'open-meteo';

  static const Duration _timeout = Duration(seconds: 20);

  /// Freshness window for current conditions.
  static const Duration currentMaxAge = Duration(minutes: 30);

  /// Freshness window for the hourly forecast.
  static const Duration hourlyMaxAge = Duration(hours: 1);

  /// Freshness window for the daily forecast.
  static const Duration dailyMaxAge = Duration(hours: 6);

  static const String _currentParams =
      'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,'
      'precipitation,weather_code,wind_speed_10m,wind_direction_10m,'
      'wind_gusts_10m';
  static const String _hourlyParams =
      'temperature_2m,precipitation_probability,weather_code,wind_speed_10m';
  static const String _dailyParams = 'weather_code,temperature_2m_max,'
      'temperature_2m_min,precipitation_sum,precipitation_probability_max';

  static const String _unavailableMessage = 'Weather data is currently unavailable.';

  final AppConfig config;
  final http.Client client;
  final WeatherCacheRepository cache;
  final AppLogger logger;

  @override
  Future<WeatherBundle> load({
    required String locationKey,
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now().toUtc();
    if (!forceRefresh) {
      final cached = await _readFromCache(locationKey, now);
      if (cached != null) return cached;
    }
    return _fetchAndCache(locationKey, latitude, longitude, now);
  }

  /// Rebuilds a bundle entirely from fresh cached slices, or null when any
  /// slice is missing or stale.
  Future<WeatherBundle?> _readFromCache(String locationKey, DateTime now) async {
    final current = await cache.currentWeather(locationKey);
    final hourly = await cache.forecast(locationKey, ForecastType.hourly);
    final daily = await cache.forecast(locationKey, ForecastType.daily);
    if (current == null || hourly == null || daily == null) return null;
    if (current.isStale(now: now) ||
        hourly.isStale(now: now) ||
        daily.isStale(now: now)) {
      return null;
    }
    try {
      final currentWeather = CurrentWeather.fromJson(current.payload);
      final hourlyPoints = HourlyForecastPoint.listFromPayload(hourly.payload);
      final dailyPoints = DailyForecastPoint.listFromPayload(daily.payload);
      if (hourlyPoints.isEmpty || dailyPoints.isEmpty) return null;
      final expiry = current.expiresAtUtc ??
          current.fetchedAtUtc.add(currentMaxAge);
      return WeatherBundle(
        locationKey: locationKey,
        current: currentWeather,
        hourly: hourlyPoints,
        daily: dailyPoints,
        fetchedAtUtc: _maxInstant(
            current.fetchedAtUtc, hourly.fetchedAtUtc, daily.fetchedAtUtc),
        expiresAtUtc: expiry,
        dataSource: dataSource,
      );
    } on FormatException {
      return null;
    }
  }

  DateTime _maxInstant(DateTime a, DateTime b, DateTime c) {
    var latest = a;
    if (b.isAfter(latest)) latest = b;
    if (c.isAfter(latest)) latest = c;
    return latest;
  }

  Future<WeatherBundle> _fetchAndCache(
    String locationKey,
    double latitude,
    double longitude,
    DateTime now,
  ) async {
    final uri = Uri.parse('${config.weatherApiBaseUrl}/forecast').replace(
      queryParameters: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'current': _currentParams,
        'hourly': _hourlyParams,
        'daily': _dailyParams,
        'timezone': 'UTC',
        'forecast_days': '7',
      },
    );

    final Map<String, dynamic> body = await _request(uri);

    final currentJson = body['current'];
    final hourlyJson = body['hourly'];
    final dailyJson = body['daily'];
    if (currentJson is! Map || hourlyJson is! Map || dailyJson is! Map) {
      throw const NetworkException(message: _unavailableMessage);
    }

    final CurrentWeather current;
    final List<HourlyForecastPoint> hourly;
    final List<DailyForecastPoint> daily;
    try {
      current = CurrentWeather.fromJson(Map<String, dynamic>.from(currentJson));
      hourly = HourlyForecastPoint.listFromOpenMeteo(
          Map<String, dynamic>.from(hourlyJson));
      daily = DailyForecastPoint.listFromOpenMeteo(
          Map<String, dynamic>.from(dailyJson));
    } on FormatException {
      throw const NetworkException(message: _unavailableMessage);
    }
    if (hourly.isEmpty || daily.isEmpty) {
      throw const NetworkException(message: _unavailableMessage);
    }

    await cache.saveCurrentWeather(CachedWeatherEntry(
      locationKey: locationKey,
      payload: current.toJson(),
      fetchedAtUtc: now,
      expiresAtUtc: now.add(currentMaxAge),
      dataSource: dataSource,
    ));
    await cache.saveForecast(CachedForecastEntry(
      locationKey: locationKey,
      type: ForecastType.hourly,
      payload: {'points': [for (final point in hourly) point.toJson()]},
      fetchedAtUtc: now,
      expiresAtUtc: now.add(hourlyMaxAge),
      dataSource: dataSource,
    ));
    await cache.saveForecast(CachedForecastEntry(
      locationKey: locationKey,
      type: ForecastType.daily,
      payload: {'points': [for (final point in daily) point.toJson()]},
      fetchedAtUtc: now,
      expiresAtUtc: now.add(dailyMaxAge),
      dataSource: dataSource,
    ));

    return WeatherBundle(
      locationKey: locationKey,
      current: current,
      hourly: hourly,
      daily: daily,
      fetchedAtUtc: now,
      expiresAtUtc: now.add(currentMaxAge),
      dataSource: dataSource,
    );
  }

  Future<Map<String, dynamic>> _request(Uri uri) async {
    try {
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        logger.warning(
            'OpenMeteoWeatherService',
            'unexpected HTTP ${response.statusCode} for ${uri.path}');
        throw const NetworkException(message: _unavailableMessage);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on NetworkException {
      rethrow;
    } on TimeoutException {
      logger.warning('OpenMeteoWeatherService', 'request timed out for ${uri.path}');
      throw const NetworkException(message: _unavailableMessage);
    } on FormatException {
      logger.warning('OpenMeteoWeatherService', 'invalid JSON for ${uri.path}');
      throw const NetworkException(message: _unavailableMessage);
    } catch (e) {
      logger.warning(
          'OpenMeteoWeatherService', 'request failed: ${e.runtimeType} for ${uri.path}');
      throw const NetworkException(message: _unavailableMessage);
    }
  }
}