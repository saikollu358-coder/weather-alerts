import 'weather_json.dart';

/// One hourly forecast point for a location.
class HourlyForecastPoint {
  const HourlyForecastPoint({
    required this.timeUtc,
    required this.temperatureC,
    this.precipitationProbability,
    required this.weatherCode,
    required this.windSpeedKmh,
  });

  /// UTC instant the forecast point represents.
  final DateTime timeUtc;

  /// Temperature in degrees Celsius.
  final double temperatureC;

  /// Chance of precipitation (0-100), or null when unavailable.
  final int? precipitationProbability;

  /// WMO weather code (see [CurrentWeather.weatherCode]).
  final int weatherCode;

  /// Wind speed at 10 m, in kilometres per hour.
  final double windSpeedKmh;

  /// Parses a single point from its cached payload representation.
  factory HourlyForecastPoint.fromJson(Map<String, dynamic> json) {
    return HourlyForecastPoint(
      timeUtc: parseUtcInstant(asString(json['time']) ?? ''),
      temperatureC: asDouble(json['temperature_2m']) ?? 0,
      precipitationProbability: asInt(json['precipitation_probability']),
      weatherCode: asInt(json['weather_code']) ?? 0,
      windSpeedKmh: asDouble(json['wind_speed_10m']) ?? 0,
    );
  }

  /// Serializes to the payload map used by the local cache.
  Map<String, dynamic> toJson() => {
        'time': timeUtc.toIso8601String(),
        'temperature_2m': temperatureC,
        'precipitation_probability': precipitationProbability,
        'weather_code': weatherCode,
        'wind_speed_10m': windSpeedKmh,
      };

  /// Parses the parallel-array `hourly` block from Open-Meteo into points.
  ///
  /// Rows are aligned by index; optional arrays shorter than `time`/temperature
  /// contribute null values. Throws [FormatException] on invalid timestamps.
  static List<HourlyForecastPoint> listFromOpenMeteo(Map<String, dynamic> json) {
    final times = jsonList(json['time']);
    final temperatures = jsonList(json['temperature_2m']);
    final probabilities = jsonList(json['precipitation_probability']);
    final codes = jsonList(json['weather_code']);
    final winds = jsonList(json['wind_speed_10m']);
    final count = times.length < temperatures.length
        ? times.length
        : temperatures.length;
    final points = <HourlyForecastPoint>[];
    for (var i = 0; i < count; i++) {
      points.add(HourlyForecastPoint(
        timeUtc: parseUtcInstant(stringAt(times, i) ?? ''),
        temperatureC: doubleAt(temperatures, i) ?? 0,
        precipitationProbability: intAt(probabilities, i),
        weatherCode: intAt(codes, i) ?? 0,
        windSpeedKmh: doubleAt(winds, i) ?? 0,
      ));
    }
    return points;
  }

  /// Restores points from a cached payload (`{'points': [...]}`), or returns an
  /// empty list when the payload is absent or malformed.
  static List<HourlyForecastPoint> listFromPayload(
    Map<String, dynamic>? payload,
  ) {
    final value = payload?['points'];
    if (value is! List) return const [];
    final points = <HourlyForecastPoint>[];
    for (final element in value) {
      if (element is Map) {
        points.add(HourlyForecastPoint.fromJson(Map<String, dynamic>.from(element)));
      }
    }
    return points;
  }

  @override
  String toString() => 'HourlyForecastPoint(${timeUtc.toIso8601String()}, '
      '${temperatureC.toStringAsFixed(1)}°C, code $weatherCode)';
}