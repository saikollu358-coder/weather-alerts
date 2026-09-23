import 'weather_severity.dart';

/// A single ordered set of numeric breakpoints for one hazard metric.
///
/// Breakpoints are given in ascending order for metrics where "more is worse"
/// (wind, heat, rainfall) and descending for metrics where "less is worse"
/// (cold). Evaluation is strictly threshold-based and deterministic.
class WeatherThresholds {
  const WeatherThresholds({
    required this.minor,
    required this.moderate,
    required this.high,
    required this.severe,
    this.exceed = true,
  });

  /// First breakpoint at which the hazard becomes [WeatherSeverity.minor].
  final double minor;

  /// First breakpoint at which the hazard becomes [WeatherSeverity.moderate].
  final double moderate;

  /// First breakpoint at which the hazard becomes [WeatherSeverity.high].
  final double high;

  /// First breakpoint at which the hazard becomes [WeatherSeverity.severe].
  final double severe;

  /// When true, [severityFor] triggers when [value] is at or above a
  /// breakpoint; when false, when it is at or below.
  final bool exceed;

  WeatherSeverity severityFor(double value) {
    if (exceed) {
      if (value >= severe) return WeatherSeverity.severe;
      if (value >= high) return WeatherSeverity.high;
      if (value >= moderate) return WeatherSeverity.moderate;
      if (value >= minor) return WeatherSeverity.minor;
      return WeatherSeverity.none;
    }
    if (value <= severe) return WeatherSeverity.severe;
    if (value <= high) return WeatherSeverity.high;
    if (value <= moderate) return WeatherSeverity.moderate;
    if (value <= minor) return WeatherSeverity.minor;
    return WeatherSeverity.none;
  }
}

/// The centralized, versioned weather-safety rule set.
///
/// This is the single source of truth for every deterministic threshold used
/// to classify hazardous weather. Rules are intentionally plain const data so
/// they can be ported *verbatim* to the Cloud Functions source (`functions/`)
/// and kept in lock-step with the mobile app (AGENTS.md: "port to functions
/// verbatim"). Version fields must be bumped on every threshold change.
///
/// Disclaimer: these thresholds are application-internal assessments. They do
/// NOT replace official warnings, which always take precedence.
abstract final class SafetyRules {
  SafetyRules._();

  /// Canonical rule-set version for the current thresholds.
  static const int version = 1;

  /// ISO date of the last threshold change.
  static const String versionDate = '2026-09-06';

  // ---------------------------------------------------------------------
  // Wind (km/h). Gusts are the primary signal; sustained winds are a fallback
  // when gust data is absent. Values align roughly with the Beaufort scale
  // (Gale ~62 km/h, Strong gale ~75, Violent storm ~103).
  // ---------------------------------------------------------------------

  /// Peak wind-gust breakpoints, in km/h.
  static const WeatherThresholds windGust = WeatherThresholds(
    minor: 40,
    moderate: 60,
    high: 75,
    severe: 90,
  );

  /// Sustained-wind breakpoints, in km/h.
  static const WeatherThresholds windSustained = WeatherThresholds(
    minor: 30,
    moderate: 45,
    high: 60,
    severe: 75,
  );

  // ---------------------------------------------------------------------
  // Heat (°C). Uses the warmer of air and apparent temperature. Values follow
  // common national heat-health guidance.
  // ---------------------------------------------------------------------

  static const WeatherThresholds heat = WeatherThresholds(
    minor: 30,
    moderate: 33,
    high: 36,
    severe: 40,
  );

  // ---------------------------------------------------------------------
  // Cold (°C). Uses the colder of air and apparent temperature.
  // ---------------------------------------------------------------------

  static const WeatherThresholds cold = WeatherThresholds(
    minor: 0,
    moderate: -5,
    high: -10,
    severe: -18,
    exceed: false,
  );

  // ---------------------------------------------------------------------
  // Flooding (mm of liquid precipitation per rolling 24 h, driven by the
  // daily accumulation forecast over the alert window).
  // ---------------------------------------------------------------------

  static const WeatherThresholds flooding = WeatherThresholds(
    minor: 20,
    moderate: 40,
    high: 60,
    severe: 100,
  );

  // ---------------------------------------------------------------------
  // Snow (mm of water-equivalent accumulation in 24 h, only counted on days
  // whose max temperature allows snowfall).
  // ---------------------------------------------------------------------

  static const WeatherThresholds snow = WeatherThresholds(
    minor: 5,
    moderate: 10,
    high: 20,
    severe: 35,
  );

  // ---------------------------------------------------------------------
  // Provenance / review note: thresholds were chosen from widely published
  // national thresholds (heat/cold health guidance, Beaufort-scale wind
  // thresholds, meteorological rainfall accumulation bands). They are a layer
  // of application-specific assessment and never a substitute for official
  // hazardous-weather warnings.
  // ---------------------------------------------------------------------
}