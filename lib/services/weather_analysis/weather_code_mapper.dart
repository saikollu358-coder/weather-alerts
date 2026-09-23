import 'weather_hazard.dart';

/// Maps the WMO weather-code vocabulary (as used by Open-Meteo) to hazard
/// categories consumed by the analysis engine.
///
/// Pure and deterministic: given the same code it always returns the same
/// constant. Unknown/unclassified codes resolve to no hazard.
class WeatherCodeMapper {
  const WeatherCodeMapper._();

  /// Returns the hazard(s) associated with [code].
  ///
  /// A single WMO code can map to multiple hazards (e.g. a thunderstorm with
  /// hail maps to both [WeatherHazard.thunderstorm] and [WeatherHazard.hail]).
  static List<WeatherHazard> hazardsFor(int code) {
    return switch (code) {
      0 || 1 || 2 || 3 => const [],
      // Fog / rime fog.
      45 || 48 => const [WeatherHazard.fog],
      // Drizzle.
      51 || 53 || 55 => const [WeatherHazard.rain],
      // Freezing drizzle.
      56 || 57 => const [WeatherHazard.ice, WeatherHazard.rain],
      // Rain.
      61 || 63 || 65 => const [WeatherHazard.rain],
      // Freezing rain.
      66 || 67 => const [WeatherHazard.ice, WeatherHazard.rain],
      // Snow / snow grains.
      71 || 73 || 75 || 77 => const [WeatherHazard.snow],
      // Rain showers.
      80 || 81 || 82 => const [WeatherHazard.rain],
      // Snow showers.
      85 || 86 => const [WeatherHazard.snow],
      // Thunderstorm (no hail).
      95 => const [WeatherHazard.thunderstorm, WeatherHazard.lightning],
      // Thunderstorm with hail.
      96 || 99 => const [
          WeatherHazard.thunderstorm,
          WeatherHazard.lightning,
          WeatherHazard.hail,
        ],
      _ => const [],
    };
  }
}