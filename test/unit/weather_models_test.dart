import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/domain/entities/weather/daily_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/hourly_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/weather_bundle.dart';
import 'package:weather_alerts/domain/entities/weather/weather_snapshot.dart';

void main() {
  group('CurrentWeather', () {
    test('parses a full Open-Meteo current block', () {
      final model = CurrentWeather.fromJson({
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
      });

      expect(model.observedAtUtc, DateTime.utc(2026, 9, 6, 12));
      expect(model.temperatureC, 18.2);
      expect(model.humidityPercent, 64);
      expect(model.apparentTemperatureC, 18.0);
      expect(model.isDay, isTrue);
      expect(model.precipitationMm, 0);
      expect(model.weatherCode, 2);
      expect(model.windSpeedKmh, 5.1);
      expect(model.windDirectionDeg, 230);
      expect(model.windGustsKmh, 8.3);
    });

    test('defaults optional fields when omitted', () {
      final model = CurrentWeather.fromJson({
        'time': '2026-09-06T12:00',
        'temperature_2m': 10.0,
        'apparent_temperature': 9.0,
      });

      expect(model.humidityPercent, isNull);
      expect(model.precipitationMm, 0);
      expect(model.weatherCode, 0);
      expect(model.isDay, isTrue);
      expect(model.windSpeedKmh, 0);
      expect(model.windDirectionDeg, isNull);
      expect(model.windGustsKmh, isNull);
    });

    test('toJson round-trips back to an equal model', () {
      final original = CurrentWeather(
        observedAtUtc: DateTime.utc(2026, 9, 6, 12),
        temperatureC: 18.2,
        apparentTemperatureC: 17.0,
        humidityPercent: 64,
        precipitationMm: 0.5,
        weatherCode: 61,
        isDay: false,
        windSpeedKmh: 12.0,
        windDirectionDeg: 220,
        windGustsKmh: 30.5,
      );

      final restored = CurrentWeather.fromJson(original.toJson());

      expect(restored.observedAtUtc, original.observedAtUtc);
      expect(restored.temperatureC, original.temperatureC);
      expect(restored.humidityPercent, original.humidityPercent);
      expect(restored.precipitationMm, original.precipitationMm);
      expect(restored.weatherCode, original.weatherCode);
      expect(restored.isDay, original.isDay);
      expect(restored.windSpeedKmh, original.windSpeedKmh);
      expect(restored.windDirectionDeg, original.windDirectionDeg);
      expect(restored.windGustsKmh, original.windGustsKmh);
    });

    test('throws FormatException on a missing or invalid time', () {
      expect(
        () => CurrentWeather.fromJson({'temperature_2m': 10.0}),
        throwsFormatException,
      );
      expect(
        () => CurrentWeather.fromJson(
            {'time': 'not-a-time', 'temperature_2m': 10.0}),
        throwsFormatException,
      );
    });
  });

  group('HourlyForecastPoint', () {
    test('parses parallel monthly arrays aligned by index', () {
      final points = HourlyForecastPoint.listFromOpenMeteo({
        'time': ['2026-09-06T13:00', '2026-09-06T14:00'],
        'temperature_2m': [18.5, 18.9],
        'precipitation_probability': [10, null],
        'weather_code': [2, 3],
        'wind_speed_10m': [5.0, 5.4],
      });

      expect(points, hasLength(2));
      expect(points[0].timeUtc, DateTime.utc(2026, 9, 6, 13));
      expect(points[0].temperatureC, 18.5);
      expect(points[0].precipitationProbability, 10);
      expect(points[0].weatherCode, 2);
      expect(points[1].precipitationProbability, isNull);
      expect(points[1].temperatureC, 18.9);
      expect(points[1].weatherCode, 3);
    });

    test('treats missing optional arrays as null', () {
      final points = HourlyForecastPoint.listFromOpenMeteo({
        'time': ['2026-09-06T13:00'],
        'temperature_2m': [18.5],
      });

      expect(points, hasLength(1));
      expect(points.single.precipitationProbability, isNull);
      expect(points.single.weatherCode, 0);
    });

    test('aligns by the shorter of time and temperature arrays', () {
      final points = HourlyForecastPoint.listFromOpenMeteo({
        'time': ['2026-09-06T13:00', '2026-09-06T14:00'],
        'temperature_2m': [18.5],
      });

      expect(points, hasLength(1));
    });

    test('payload round-trip preserves a point', () {
      final point = HourlyForecastPoint(
        timeUtc: DateTime.utc(2026, 9, 6, 13),
        temperatureC: 18.5,
        precipitationProbability: null,
        weatherCode: 2,
        windSpeedKmh: 5.0,
      );

      final restored = HourlyForecastPoint.listFromPayload(
          {'points': [point.toJson()]});

      expect(restored, hasLength(1));
      expect(restored.single.timeUtc, point.timeUtc);
      expect(restored.single.temperatureC, point.temperatureC);
      expect(restored.single.precipitationProbability, isNull);
      expect(restored.single.weatherCode, point.weatherCode);
    });

    test('listFromPayload handles a missing or malformed payload', () {
      expect(HourlyForecastPoint.listFromPayload(null), isEmpty);
      expect(HourlyForecastPoint.listFromPayload({'points': 'nope'}), isEmpty);
    });
  });

  group('DailyForecastPoint', () {
    test('parses parallel arrays into UTC-midnight days', () {
      final points = DailyForecastPoint.listFromOpenMeteo({
        'time': ['2026-09-06', '2026-09-07'],
        'weather_code': [2, 61],
        'temperature_2m_max': [21.0, 19.5],
        'temperature_2m_min': [12.0, 11.0],
        'precipitation_sum': [0.0, 2.1],
        'precipitation_probability_max': [10, 60],
      });

      expect(points, hasLength(2));
      expect(points[0].dateUtc, DateTime.utc(2026, 9, 6));
      expect(points[0].weatherCode, 2);
      expect(points[0].temperatureMaxC, 21.0);
      expect(points[0].temperatureMinC, 12.0);
      expect(points[0].precipitationSumMm, 0);
      expect(points[0].precipitationProbabilityMax, 10);
      expect(points[1].weatherCode, 61);
    });

    test('payload round-trip preserves a day', () {
      final day = DailyForecastPoint(
        dateUtc: DateTime.utc(2026, 9, 6),
        weatherCode: 61,
        temperatureMaxC: 19.5,
        temperatureMinC: 11.0,
        precipitationSumMm: 2.1,
        precipitationProbabilityMax: 60,
      );

      final restored = DailyForecastPoint.listFromPayload(
          {'points': [day.toJson()]});

      expect(restored, hasLength(1));
      expect(restored.single.dateUtc, day.dateUtc);
      expect(restored.single.weatherCode, day.weatherCode);
      expect(restored.single.precipitationSumMm, day.precipitationSumMm);
      expect(restored.single.precipitationProbabilityMax, 60);
    });
  });

  group('WeatherBundle', () {
    test('reports staleness from its expiry', () {
      final bundle = WeatherBundle(
        locationKey: '1.0,2.0',
        current: CurrentWeather(
          observedAtUtc: DateTime.utc(2026, 9, 6, 12),
          temperatureC: 18.2,
          apparentTemperatureC: 18.0,
          weatherCode: 2,
        ),
        hourly: const [],
        daily: const [],
        fetchedAtUtc: DateTime.utc(2026, 9, 6, 12),
        expiresAtUtc: DateTime.utc(2026, 9, 6, 12, 30),
      );

      expect(bundle.isStale(now: DateTime.utc(2026, 9, 6, 12, 15)), isFalse);
      expect(bundle.isStale(now: DateTime.utc(2026, 9, 6, 12, 31)), isTrue);
    });
  });
}