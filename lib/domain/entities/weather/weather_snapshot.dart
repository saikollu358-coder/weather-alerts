import 'weather_json.dart';

/// Typed snapshot of current conditions for a location.
class CurrentWeather {
  const CurrentWeather({
    required this.observedAtUtc,
    required this.temperatureC,
    required this.apparentTemperatureC,
    this.humidityPercent,
    this.precipitationMm = 0,
    required this.weatherCode,
    this.isDay = true,
    this.windSpeedKmh = 0,
    this.windDirectionDeg,
    this.windGustsKmh,
  });

  /// UTC instant the observation represents.
  final DateTime observedAtUtc;

  /// Air temperature in degrees Celsius.
  final double temperatureC;

  /// Perceived temperature (wind chill / heat index) in degrees Celsius.
  final double apparentTemperatureC;

  /// Relative humidity (0-100), or null when the provider omitted it.
  final double? humidityPercent;

  /// Liquid precipitation over the underlying interval, in millimetres.
  final double precipitationMm;

  /// WMO weather code. Opaque to the data layer; risk classification is a
  /// weather-analysis concern.
  final int weatherCode;

  /// True when the observation is during daylight.
  final bool isDay;

  /// Wind speed at 10 m, in kilometres per hour.
  final double windSpeedKmh;

  /// Wind direction in degrees (0-360), or null when the provider omitted it.
  final double? windDirectionDeg;

  /// Wind gusts at 10 m, in kilometres per hour, or null when omitted.
  final double? windGustsKmh;

  /// Parses a `current` block from the Open-Meteo forecast response.
  ///
  /// Throws [FormatException] when required fields are missing or invalid.
  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      observedAtUtc: parseUtcInstant(asString(json['time']) ?? ''),
      temperatureC: asDouble(json['temperature_2m']) ?? 0,
      apparentTemperatureC: asDouble(json['apparent_temperature']) ?? 0,
      humidityPercent: asDouble(json['relative_humidity_2m']),
      precipitationMm: asDouble(json['precipitation']) ?? 0,
      weatherCode: asInt(json['weather_code']) ?? 0,
      isDay: asBool(json['is_day'], fallback: true),
      windSpeedKmh: asDouble(json['wind_speed_10m']) ?? 0,
      windDirectionDeg: asDouble(json['wind_direction_10m']),
      windGustsKmh: asDouble(json['wind_gusts_10m']),
    );
  }

  /// Serializes back to a payload map (for the local cache).
  Map<String, dynamic> toJson() => {
        'time': observedAtUtc.toIso8601String(),
        'temperature_2m': temperatureC,
        'relative_humidity_2m': humidityPercent,
        'apparent_temperature': apparentTemperatureC,
        'is_day': isDay,
        'precipitation': precipitationMm,
        'weather_code': weatherCode,
        'wind_speed_10m': windSpeedKmh,
        'wind_direction_10m': windDirectionDeg,
        'wind_gusts_10m': windGustsKmh,
      };

  @override
  String toString() => 'CurrentWeather(${temperatureC.toStringAsFixed(1)}°C, '
      'code $weatherCode, ${observedAtUtc.toIso8601String()})';
}