/// Lifecycle states of a weather-risk alert.
///
/// Mirrors the alert lifecycle defined in the master specification. This enum
/// is independent of the typed hazard/severity enums introduced in Phase 8
/// (see `lib/services/weather_analysis/`); records persist hazards and
/// severities as canonical strings so storage stays decoupled.
enum AlertStatus {
  /// The hazardous condition was just detected.
  detected,

  /// The alert is live and being reported.
  active,

  /// Severity increased while the alert was active.
  escalated,

  /// The hazardous condition no longer applies.
  resolved,

  /// The alert exceeded its maximum lifetime without resolution.
  expired,
}