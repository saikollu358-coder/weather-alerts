import '../../domain/entities/weather/weather_bundle.dart';

/// Aggregated, metric-level view of a [WeatherBundle] used purely for rule
/// evaluation.
///
/// All values are derived deterministically from the bundle so the evaluator
/// itself stays free of business logic and mirrors `functions/` exactly.
class WeatherRiskInput {
  const WeatherRiskInput({
    required this.locationKey,
    required this.peakGustKmh,
    required this.peakSustainedWindKmh,
    required this.maxTemperatureC,
    required this.minTemperatureC,
    required this.maxApparentTemperatureC,
    required this.minApparentTemperatureC,
    required this.maxDailyPrecipMm,
    required this.maxDailySnowMm,
    required this.currentWeatherCode,
    required this.upcomingWeatherCodes,
    required this.currentHourlyPrecipMm,
    required this.humidityPercent,
    required this.windowHours,
    required this.accumulationHours,
  });

  final String locationKey;

  /// Highest wind-gust value (km/h) across current + window, or null.
  final double? peakGustKmh;

  /// Highest sustained wind (km/h) across current + window, or null.
  final double? peakSustainedWindKmh;

  /// Warmest air temperature (°C) across current + window.
  final double maxTemperatureC;

  /// Coldest air temperature (°C) across current + window.
  final double minTemperatureC;

  /// Warmest apparent temperature (°C) across current + window.
  final double maxApparentTemperatureC;

  /// Coldest apparent temperature (°C) across current + window.
  final double minApparentTemperatureC;

  /// Largest rolling-24 h precipitation total (mm) across the accumulation
  /// window, or the current rate when no daily data is present.
  final double maxDailyPrecipMm;

  /// Largest single-day water-equivalent snow amount (mm) across the
  /// accumulation window, only counting days whose maximum temperature allows
  /// snowfall.
  final double maxDailySnowMm;

  /// WMO code of the current observation.
  final int currentWeatherCode;

  /// WMO codes inside the [windowHours] alert window (excludes current).
  final List<int> upcomingWeatherCodes;

  /// Current precipitation rate (mm), used for short-window rain intensity.
  final double currentHourlyPrecipMm;

  /// Relative humidity (%) of the current observation, or null.
  final double? humidityPercent;

  /// Alert window size used for these inputs.
  final int windowHours;

  /// Accumulation window size used for snow/flooding totals.
  final int accumulationHours;

  /// Builds inputs from a [bundle] relative to [now], using the given window
  /// sizes. Pure and deterministic.
  static WeatherRiskInput fromBundle(
    WeatherBundle bundle, {
    DateTime? now,
    int windowHours = 24,
    int accumulationHours = 72,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    final current = bundle.current;
    final hourly = bundle.hourly;
    final daily = bundle.daily;

    final windowEnd = reference.add(Duration(hours: windowHours));
    final accumulationEnd = reference.add(Duration(hours: accumulationHours));

    double? peakGust = current.windGustsKmh;
    double? peakSustained =
        current.windSpeedKmh > 0 ? current.windSpeedKmh : null;
    var maxTemp = current.temperatureC;
    var minTemp = current.temperatureC;
    var maxApparent = current.apparentTemperatureC;
    var minApparent = current.apparentTemperatureC;
    final upcomingCodes = <int>[];

    for (final point in hourly) {
      if (!point.timeUtc.isAfter(reference)) continue;
      if (point.timeUtc.isAfter(windowEnd)) break;
      upcomingCodes.add(point.weatherCode);
      if (point.windSpeedKmh > (peakGust ?? 0)) peakGust = point.windSpeedKmh;
      if (point.windSpeedKmh > (peakSustained ?? 0)) {
        peakSustained = point.windSpeedKmh;
      }
      if (point.temperatureC > maxTemp) maxTemp = point.temperatureC;
      if (point.temperatureC < minTemp) minTemp = point.temperatureC;
    }

    var maxDailyPrecip = current.precipitationMm;
    var maxDailySnow = 0.0;
    for (final day in daily) {
      final dayEnd = day.dateUtc.add(const Duration(days: 1));
      if (!dayEnd.isAfter(reference)) continue;
      if (day.dateUtc.isAfter(accumulationEnd)) break;
      if (day.precipitationSumMm > maxDailyPrecip) {
        maxDailyPrecip = day.precipitationSumMm;
      }
      if (day.temperatureMaxC <= 2 && day.temperatureMinC <= 2) {
        if (day.precipitationSumMm > maxDailySnow) {
          maxDailySnow = day.precipitationSumMm;
        }
      }
      if (day.temperatureMaxC > maxTemp) maxTemp = day.temperatureMaxC;
      if (day.temperatureMinC < minTemp) minTemp = day.temperatureMinC;
    }

    return WeatherRiskInput(
      locationKey: bundle.locationKey,
      peakGustKmh: peakGust != null && peakGust > 0 ? peakGust : null,
      peakSustainedWindKmh:
          peakSustained != null && peakSustained > 0 ? peakSustained : null,
      maxTemperatureC: maxTemp,
      minTemperatureC: minTemp,
      maxApparentTemperatureC: maxApparent > current.temperatureC
          ? maxApparent
          : maxTemp,
      minApparentTemperatureC: minApparent < current.temperatureC
          ? minApparent
          : minTemp,
      maxDailyPrecipMm: maxDailyPrecip,
      maxDailySnowMm: maxDailySnow,
      currentWeatherCode: current.weatherCode,
      upcomingWeatherCodes: upcomingCodes,
      currentHourlyPrecipMm: current.precipitationMm,
      humidityPercent: current.humidityPercent,
      windowHours: windowHours,
      accumulationHours: accumulationHours,
    );
  }
}