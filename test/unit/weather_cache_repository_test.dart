import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/datasources/local/local_database_io.dart';
import 'package:weather_alerts/data/repositories/weather_cache_repository_impl.dart';
import 'package:weather_alerts/domain/entities/cached_forecast_entry.dart';
import 'package:weather_alerts/domain/entities/cached_weather_entry.dart';

import '../helpers/test_database.dart';

void main() {
  late SqfliteDatabase db;
  late Directory dir;
  late WeatherCacheRepositoryImpl repository;

  setUp(() async {
    final created = await createTestDatabase();
    db = created.$1;
    dir = created.$2;
    repository = WeatherCacheRepositoryImpl(
      db: db,
      logger: AppLogger(enabled: false),
    );
  });

  tearDown(() async => teardownTestDatabase(db, dir));

  CachedWeatherEntry entry({
    String key = '12.3,45.6',
    DateTime? fetched,
    DateTime? expires,
  }) =>
      CachedWeatherEntry(
        locationKey: key,
        payload: {
          'temperature': 21.5,
          'condition': 'Partly cloudy',
        },
        fetchedAtUtc: fetched ?? DateTime.utc(2026, 1, 1, 12),
        expiresAtUtc: expires,
        dataSource: 'open-meteo',
      );

  CachedForecastEntry forecastEntry(
    String key,
    ForecastType type,
  ) =>
      CachedForecastEntry(
        locationKey: key,
        type: type,
        payload: {
          'hours': [1, 2, 3],
        },
        fetchedAtUtc: DateTime.utc(2026, 1, 1, 12),
        expiresAtUtc: DateTime.utc(2026, 1, 1, 15),
        dataSource: 'open-meteo',
      );

  test('round-trips current weather preserving payload and metadata', () async {
    final original = entry();
    await repository.saveCurrentWeather(original);

    final loaded = await repository.currentWeather('12.3,45.6');
    expect(loaded, isNotNull);
    expect(loaded!.locationKey, '12.3,45.6');
    expect(loaded.payload, {'temperature': 21.5, 'condition': 'Partly cloudy'});
    expect(loaded.dataSource, 'open-meteo');
    expect(loaded.fetchedAtUtc, DateTime.utc(2026, 1, 1, 12));
  });

  test('saving the same location replaces the previous snapshot', () async {
    await repository.saveCurrentWeather(entry());
    await repository.saveCurrentWeather(entry(fetched: DateTime.utc(2026, 1, 2)));

    final all = await db.query('cached_weather');
    expect(all, hasLength(1));
    final loaded = await repository.currentWeather('12.3,45.6');
    expect(loaded!.fetchedAtUtc, DateTime.utc(2026, 1, 2));
  });

  test('hasFreshCurrentWeather honors expiry and maxAge fallback', () async {
    final now = DateTime.utc(2026, 1, 2);
    final expired = entry(expires: DateTime.utc(2026, 1, 1, 13));
    await repository.saveCurrentWeather(expired);
    expect(
      await repository.hasFreshCurrentWeather(
        '12.3,45.6',
        const Duration(hours: 3),
        at: now,
      ),
      isFalse,
    );

    // Same data, but no server expiry: freshness falls back to maxAge.
    await repository.saveCurrentWeather(entry());
    expect(
      await repository.hasFreshCurrentWeather(
        '12.3,45.6',
        const Duration(hours: 2),
        at: DateTime.utc(2026, 1, 1, 13, 59),
      ),
      isTrue,
    );
    expect(
      await repository.hasFreshCurrentWeather(
        '12.3,45.6',
        const Duration(hours: 2),
        at: DateTime.utc(2026, 1, 1, 14, 1),
      ),
      isFalse,
    );
    expect(
      await repository.hasFreshCurrentWeather(
        'missing',
        const Duration(hours: 2),
        at: now,
      ),
      isFalse,
    );
  });

  test('stores hourly and daily forecasts independently', () async {
    await repository.saveForecast(forecastEntry('9,9', ForecastType.hourly));
    await repository.saveForecast(forecastEntry('9,9', ForecastType.daily));

    final hourly = (await repository.forecast('9,9', ForecastType.hourly))!;
    final daily = (await repository.forecast('9,9', ForecastType.daily))!;
    expect(hourly.payload, {'hours': [1, 2, 3]});
    expect(hourly.type, ForecastType.hourly);
    expect(daily.type, ForecastType.daily);

    final hasFresh = await repository.hasFreshForecast(
      '9,9',
      ForecastType.hourly,
      const Duration(hours: 3),
      at: DateTime.utc(2026, 1, 1, 13),
    );
    expect(hasFresh, isTrue);
  });

  test('deleteLocation removes weather and all forecasts for only that key',
      () async {
    await repository.saveCurrentWeather(entry());
    await repository.saveCurrentWeather(entry(key: 'o,o'));
    await repository.saveForecast(forecastEntry('12.3,45.6', ForecastType.hourly));

    await repository.deleteLocation('12.3,45.6');

    expect(await repository.currentWeather('12.3,45.6'), isNull);
    expect(await repository.forecast('12.3,45.6', ForecastType.hourly), isNull);
    // The other location is untouched.
    expect(await repository.currentWeather('o,o'), isNotNull);
  });

  test('clear removes all cached weather and forecasts', () async {
    await repository.saveCurrentWeather(entry());
    await repository.saveForecast(forecastEntry('9,9', ForecastType.hourly));

    await repository.clear();

    expect(await repository.currentWeather('12.3,45.6'), isNull);
    expect(await repository.forecast('9,9', ForecastType.hourly), isNull);
    expect(await db.query('cached_weather'), isEmpty);
    expect(await db.query('cached_forecast'), isEmpty);
  });
}