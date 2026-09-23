/// Hazard categories used by the weather-risk analysis engine (Phase 8).
///
/// These are the canonical hazard identifiers referenced by storage-layer
/// records (see `domain/entities/alert_record.dart`), which persist them as
/// canonical strings to stay decoupled from this typed enum.
enum WeatherHazard {
  thunderstorm,
  rain,
  flooding,
  snow,
  ice,
  heat,
  cold,
  fog,
  highWind,
  uvExposure,
  airQuality,
  hail,
  lightning,
  drought;

  static WeatherHazard? tryParse(String? value) {
    if (value == null) return null;
    for (final hazard in WeatherHazard.values) {
      if (hazard.name.toLowerCase() == value.toLowerCase()) return hazard;
    }
    return null;
  }
}
