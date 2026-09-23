import 'weather_severity.dart';

/// Aggregate risk level for a location across all detected hazards.
///
/// Derived deterministically from the individual hazard severities:
/// the highest individual severity drives the overall level. Keep ordering
/// stable; values are compared via [WeatherSeverity] ordering.
enum RiskLevel {
  /// No hazards detected — safe baseline.
  low,

  /// One or more minor/moderate hazards present.
  moderate,

  /// At least one high-severity hazard present.
  high,

  /// At least one severe hazard present, or an extreme combination.
  critical;

  static RiskLevel fromSeverity(WeatherSeverity severity) {
    switch (severity) {
      case WeatherSeverity.none:
      case WeatherSeverity.minor:
        return RiskLevel.low;
      case WeatherSeverity.moderate:
        return RiskLevel.moderate;
      case WeatherSeverity.high:
        return RiskLevel.high;
      case WeatherSeverity.severe:
        return RiskLevel.critical;
    }
  }
}