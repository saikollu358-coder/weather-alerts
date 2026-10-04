import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/cached_forecast_entry.dart';
import 'package:weather_alerts/domain/entities/cached_weather_entry.dart';
import 'package:weather_alerts/domain/entities/weather/daily_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/hourly_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/weather_snapshot.dart';
import 'package:weather_alerts/domain/repositories/weather_cache_repository.dart';
import 'package:weather_alerts/services/weather/open_meteo_weather_service.dart';

const testConfig = AppConfig(
  environment: 'test',
  weatherApiBaseUrl: 'https://api.test.example/v1',
  geocodingApiBaseUrl: 'https://geocode.test.example/v1',
  reverseGeocodingApiBaseUrl: 'https://reverse.test.example/reverse',
  reverseGeocodingProvider: ReverseGeocodingProvider.bigDataCloud,
  openWeatherApiKey: '',
  loggingEnabled: false,
  firebaseWebApiKey: '',
  firebaseWebAuthDomain: '',
  firebaseWebProjectId: '',
  firebaseWebStorageBucket: '',
  firebaseWebMessagingSenderId: '',
  firebaseWebAppId: '',
);

final testLogger = AppLogger(enabled: false);

String sampleForecastBody() => jsonEncode({
      'latitude': 52.52,
      'longitude': 13.41,
      'timezone': 'UTC',
      'current': {
        'time': '2026-09-06T12:00',
        'temperature_2m': 18.2,
        'relative_humidity_2m': 64,
        'apparent_temperature': 18.0,
        'is_day': 1,
        'precipitation': 0.0,
        'weather_code': 2,
        'wind_speed_10m': 5.1,
        'wind_direction_10m': 230,
        'wind_gusts_10m': 8.3,
      },
      'hourly': {
        'time': ['2026-09-06T13:00', '2026-09-06T14:00'],
        'temperature_2m': [18.5, 18.9],
        'precipitation_probability': [10, null],
        'weather_code': [2, 3],
        'wind_speed_10m': [5.0, 5.4],
      },
      'daily': {
        'time': ['2026-09-06', '2026-09-07'],
        'weather_code': [2, 61],
        'temperature_2m_max': [21.0, 19.5],
        'temperature_2m_min': [12.0, 11.0],
        'precipitation_sum': [0.0, 2.1],
        'precipitation_probability_max': [10, 60],
      },
    });

/// In-memory [WeatherCacheRepository] recording writes for assertions.
class FakeCacheRepository implements WeatherCacheRepository {
  final Map<String, CachedWeatherEntry> _current = {};
  final Map<String, Map<ForecastType, CachedForecastEntry>> _forecast = {};
  CachedWeatherEntry? lastStoredCurrent;
  CachedForecastEntry? lastStoredHourly;
  CachedForecastEntry? lastStoredDaily;

  @override
  Future<void> saveCurrentWeather(CachedWeatherEntry entry) async {
    _current[entry.locationKey] = entry;
    lastStoredCurrent = entry;
  }

  @override
  Future<CachedWeatherEntry?> currentWeather(String locationKey) async =>
      _current[locationKey];

  @override
  Future<bool> hasFreshCurrentWeather(
    String locationKey,
    Duration maxAge, {
    DateTime? at,
  }) async =>
      true;

  @override
  Future<void> saveForecast(CachedForecastEntry entry) async {
    _forecast.putIfAbsent(entry.locationKey, () => {})[entry.type] = entry;
    if (entry.type == ForecastType.hourly) lastStoredHourly = entry;
    if (entry.type == ForecastType.daily) lastStoredDaily = entry;
  }

  @override
  Future<CachedForecastEntry?> forecast(
    String locationKey,
    ForecastType type,
  ) async =>
      _forecast[locationKey]?[type];

  @override
  Future<bool> hasFreshForecast(
    String locationKey,
    ForecastType type,
    Duration maxAge, {
    DateTime? at,
  }) async =>
      true;

  @override
  Future<void> deleteLocation(String locationKey) async {}

  @override
  Future<void> clear() async {}
}

/// Fresh cached entries, relative to [now], carrying distinct temperatures so
/// cache-vs-network origins are distinguishable in assertions.
CachedWeatherEntry freshCurrentEntry(String locationKey, DateTime now) {
  final fetchedAt = now.subtract(const Duration(minutes: 5));
  return CachedWeatherEntry(
    locationKey: locationKey,
    payload: CurrentWeather(
      observedAtUtc: fetchedAt,
      temperatureC: 15.0,
      apparentTemperatureC: 14.5,
      weatherCode: 1,
    ).toJson(),
    fetchedAtUtc: fetchedAt,
    expiresAtUtc: fetchedAt.add(OpenMeteoWeatherService.currentMaxAge),
    dataSource: OpenMeteoWeatherService.dataSource,
  );
}

CachedForecastEntry freshHourlyEntry(String locationKey, DateTime now) {
  final fetchedAt = now.subtract(const Duration(minutes: 5));
  return CachedForecastEntry(
    locationKey: locationKey,
    type: ForecastType.hourly,
    payload: {
      'points': [
        HourlyForecastPoint(
          timeUtc: now.subtract(const Duration(minutes: 5)),
          temperatureC: 15.1,
          weatherCode: 1,
          windSpeedKmh: 4.0,
        ).toJson(),
      ],
    },
    fetchedAtUtc: fetchedAt,
    expiresAtUtc: fetchedAt.add(OpenMeteoWeatherService.hourlyMaxAge),
    dataSource: OpenMeteoWeatherService.dataSource,
  );
}

CachedForecastEntry freshDailyEntry(String locationKey, DateTime now) {
  final fetchedAt = now.subtract(const Duration(minutes: 5));
  return CachedForecastEntry(
    locationKey: locationKey,
    type: ForecastType.daily,
    payload: {
      'points': [
        DailyForecastPoint(
          dateUtc: now.toUtc(),
          weatherCode: 1,
          temperatureMaxC: 15.2,
          temperatureMinC: 9.0,
          precipitationSumMm: 0,
        ).toJson(),
      ],
    },
    fetchedAtUtc: fetchedAt,
    expiresAtUtc: fetchedAt.add(OpenMeteoWeatherService.dailyMaxAge),
    dataSource: OpenMeteoWeatherService.dataSource,
  );
}

/// An always-stale daily entry (regardless of the machine clock).
CachedForecastEntry staleDailyEntry(String locationKey, DateTime now) {
  return CachedForecastEntry(
    locationKey: locationKey,
    type: ForecastType.daily,
    payload: freshDailyEntry(locationKey, now).payload,
    fetchedAtUtc: now.subtract(const Duration(days: 2)),
    expiresAtUtc: now.subtract(const Duration(hours: 1)),
    dataSource: OpenMeteoWeatherService.dataSource,
  );
}

void seedAllFresh(FakeCacheRepository cache, String locationKey, DateTime now) {
  cache.saveCurrentWeather(freshCurrentEntry(locationKey, now));
  cache.saveForecast(freshHourlyEntry(locationKey, now));
  cache.saveForecast(freshDailyEntry(locationKey, now));
}

MockClient failingClient() => MockClient((_) async => http.Response('boom', 500));

void main() {
  const locationKey = '1.0,2.0';

  OpenMeteoWeatherService buildService(http.Client client, FakeCacheRepository cache) {
    return OpenMeteoWeatherService(
      config: testConfig,
      client: client,
      cache: cache,
      logger: testLogger,
    );
  }

  group('OpenMeteoWeatherService cache-first reads', () {
    test('serves a fully fresh set from cache without any network call', () async {
      final now = DateTime.now().toUtc();
      final cache = FakeCacheRepository();
      seedAllFresh(cache, locationKey, now);
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response('unexpected', 500);
      });

      final bundle = await buildService(client, cache)
          .load(locationKey: locationKey, latitude: 1.0, longitude: 2.0);

      expect(networkCalls, 0);
      expect(bundle.current.temperatureC, 15.0);
      expect(bundle.hourly.single.temperatureC, 15.1);
      expect(bundle.daily.single.temperatureMaxC, 15.2);
      expect(bundle.fetchedAtUtc,
          now.subtract(const Duration(minutes: 5)));
      expect(bundle.expiresAtUtc, now.subtract(const Duration(minutes: 5))
          .add(OpenMeteoWeatherService.currentMaxAge));
    });

    test('fetches once when a slice is missing from cache', () async {
      final now = DateTime.now().toUtc();
      final cache = FakeCacheRepository();
      cache.saveCurrentWeather(freshCurrentEntry(locationKey, now));
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response(sampleForecastBody(), 200);
      });

      final bundle = await buildService(client, cache)
          .load(locationKey: locationKey, latitude: 1.0, longitude: 2.0);

      expect(networkCalls, 1);
      expect(bundle.current.temperatureC, 18.2);
      expect(cache.lastStoredCurrent, isNotNull);
      expect(cache.lastStoredHourly, isNotNull);
      expect(cache.lastStoredDaily, isNotNull);
      expect(cache.lastStoredCurrent!.dataSource, 'open-meteo');
      expect(cache.lastStoredHourly!.type, ForecastType.hourly);
      expect(cache.lastStoredDaily!.type, ForecastType.daily);
    });

    test('refetches when any slice is stale, replacing the fresh ones', () async {
      final now = DateTime.now().toUtc();
      final cache = FakeCacheRepository();
      seedAllFresh(cache, locationKey, now);
      cache.saveForecast(staleDailyEntry(locationKey, now));
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response(sampleForecastBody(), 200);
      });

      final bundle = await buildService(client, cache)
          .load(locationKey: locationKey, latitude: 1.0, longitude: 2.0);

      expect(networkCalls, 1);
      expect(bundle.hourly.first.temperatureC, 18.5,
          reason: 'fetched data wins over the still-fresh cached hourly slice');
    });

    test('forceRefresh bypasses a fully fresh cache', () async {
      final now = DateTime.now().toUtc();
      final cache = FakeCacheRepository();
      seedAllFresh(cache, locationKey, now);
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response(sampleForecastBody(), 200);
      });

      final bundle = await buildService(client, cache)
          .load(
              locationKey: locationKey,
              latitude: 1.0,
              longitude: 2.0,
              forceRefresh: true);

      expect(networkCalls, 1);
      expect(bundle.current.temperatureC, 18.2);
    });

    test('parses the fetched payload into the full bundle', () async {
      final cache = FakeCacheRepository();
      final client =
          MockClient((_) async => http.Response(sampleForecastBody(), 200));

      final bundle = await buildService(client, cache)
          .load(locationKey: locationKey, latitude: 52.52, longitude: 13.41);

      expect(bundle.current.temperatureC, 18.2);
      expect(bundle.current.humidityPercent, 64);
      expect(bundle.current.weatherCode, 2);
      expect(bundle.current.windDirectionDeg, 230);
      expect(bundle.current.isDay, isTrue);
      expect(bundle.current.observedAtUtc, DateTime.utc(2026, 9, 6, 12));

      expect(bundle.hourly, hasLength(2));
      expect(bundle.hourly[0].timeUtc, DateTime.utc(2026, 9, 6, 13));
      expect(bundle.hourly[0].precipitationProbability, 10);
      expect(bundle.hourly[1].precipitationProbability, isNull);

      expect(bundle.daily, hasLength(2));
      expect(bundle.daily[0].dateUtc, DateTime.utc(2026, 9, 6));
      expect(bundle.daily[0].temperatureMaxC, 21.0);
      expect(bundle.daily[1].weatherCode, 61);

      expect(bundle.expiresAtUtc.difference(bundle.fetchedAtUtc),
          OpenMeteoWeatherService.currentMaxAge);
    });

    test('a second load after a fetch comes from cache', () async {
      final cache = FakeCacheRepository();
      var networkCalls = 0;
      final client = MockClient((_) async {
        networkCalls++;
        return http.Response(sampleForecastBody(), 200);
      });
      final service = buildService(client, cache);

      await service.load(locationKey: locationKey, latitude: 1.0, longitude: 2.0);
      final second = await service.load(
          locationKey: locationKey, latitude: 1.0, longitude: 2.0);

      expect(networkCalls, 1);
      expect(second.current.temperatureC, 18.2);
    });
  });

  group('OpenMeteoWeatherService error mapping', () {
    Future<void> expectNetworkExceptionOn(http.Client client) async {
      final service = buildService(client, FakeCacheRepository());
      expect(
        () => service.load(
            locationKey: locationKey, latitude: 1.0, longitude: 2.0),
        throwsA(isA<NetworkException>()),
      );
    }

    test('non-200 responses become a NetworkException', () async {
      await expectNetworkExceptionOn(failingClient());
    });

    test('invalid JSON becomes a NetworkException', () async {
      await expectNetworkExceptionOn(
          MockClient((_) async => http.Response('not json', 200)));
    });

    test('client failures become a NetworkException', () async {
      await expectNetworkExceptionOn(
          MockClient((_) async => throw Exception('boom')));
    });

    test('a missing current block becomes a NetworkException', () async {
      final body = jsonDecode(sampleForecastBody())..remove('current');
      await expectNetworkExceptionOn(
          MockClient((_) async => http.Response(jsonEncode(body), 200)));
    });

    test('a malformed timestamp becomes a NetworkException', () async {
      final body = jsonDecode(sampleForecastBody());
      (body['current'] as Map<String, dynamic>)['time'] = 'not-a-time';
      await expectNetworkExceptionOn(
          MockClient((_) async => http.Response(jsonEncode(body), 200)));
    });
  });
}