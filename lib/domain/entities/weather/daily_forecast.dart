import 'weather_json.dart';

/// One daily forecast summary for a location.
class DailyForecastPoint {
  const DailyForecastPoint({
    required this.dateUtc,
    required this.weatherCode,
    required this.temperatureMaxC,
    required this.temperatureMinC,
    required this.precipitationSumMm,
    this.precipitationProbabilityMax,
  });

  /// UTC midnight of the forecast day.
  final DateTime dateUtc;

  /// WMO weather code (see [CurrentWeather.weatherCode]).
  final int weatherCode;

  /// Maximum temperature in degrees Celsius.
  final double temperatureMaxC;

  /// Minimum temperature in degrees Celsius.
  final double temperatureMinC;

  /// Total precipitation for the day, in millimetres.
  final double precipitationSumMm;

  /// Maximum chance of precipitation (0-100), or null when unavailable.
  final int? precipitationProbabilityMax;

  /// Parses a single day from its cached payload representation.
  factory DailyForecastPoint.fromJson(Map<String, dynamic> json) {
    return DailyForecastPoint(
      dateUtc: parseUtcInstant(asString(json['time']) ?? '', dateOnly: true),
      weatherCode: asInt(json['weather_code']) ?? 0,
      temperatureMaxC: asDouble(json['temperature_2m_max']) ?? 0,
      temperatureMinC: asDouble(json['temperature_2m_min']) ?? 0,
      precipitationSumMm: asDouble(json['precipitation_sum']) ?? 0,
      precipitationProbabilityMax: asInt(json['precipitation_probability_max']),
    );
  }

  /// Serializes to the payload map used by the local cache.
  Map<String, dynamic> toJson() => {
        'time': dateUtc.toIso8601String(),
        'weather_code': weatherCode,
        'temperature_2m_max': temperatureMaxC,
        'temperature_2m_min': temperatureMinC,
        'precipitation_sum': precipitationSumMm,
        'precipitation_probability_max': precipitationProbabilityMax,
      };

  /// Parses the parallel-array `daily` block from Open-Meteo into points.
  ///
  /// Rows are aligned by index; optional arrays shorter than `time` contribute
  /// null values. Throws [FormatException] on invalid dates.
  static List<DailyForecastPoint> listFromOpenMeteo(Map<String, dynamic> json) {
    final times = jsonList(json['time']);
    final codes = jsonList(json['weather_code']);
    final maxes = jsonList(json['temperature_2m_max']);
    final mins = jsonList(json['temperature_2m_min']);
    final precip = jsonList(json['precipitation_sum']);
    final precipProbs = jsonList(json['precipitation_probability_max']);
    final points = <DailyForecastPoint>[];
    for (var i = 0; i < times.length; i++) {
      points.add(DailyForecastPoint(
        dateUtc: parseUtcInstant(stringAt(times, i) ?? '', dateOnly: true),
        weatherCode: intAt(codes, i) ?? 0,
        temperatureMaxC: doubleAt(maxes, i) ?? 0,
        temperatureMinC: doubleAt(mins, i) ?? 0,
        precipitationSumMm: doubleAt(precip, i) ?? 0,
        precipitationProbabilityMax: intAt(precipProbs, i),
      ));
    }
    return points;
  }

  /// Restores days from a cached payload (`{'points': [...]}`), or returns an
  /// empty list when the payload is absent or malformed.
  static List<DailyForecastPoint> listFromPayload(Map<String, dynamic>? payload) {
    final value = payload?['points'];
    if (value is! List) return const [];
    final points = <DailyForecastPoint>[];
    for (final element in value) {
      if (element is Map) {
        points.add(DailyForecastPoint.fromJson(Map<String, dynamic>.from(element)));
      }
    }
    return points;
  }

  @override
  String toString() => 'DailyForecastPoint(${dateUtc.toIso8601String()}, '
      '${temperatureMinC.toStringAsFixed(0)}..'
      '${temperatureMaxC.toStringAsFixed(0)}°C, code $weatherCode)';
}