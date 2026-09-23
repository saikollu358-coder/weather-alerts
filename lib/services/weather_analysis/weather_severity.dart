/// Severity levels for a detected weather hazard, in ascending order.
///
/// Numeric `index` (0–4) is the canonical comparison key and is what gets
/// persisted to storage; keep the ordering stable.
enum WeatherSeverity {
  /// No meaningful hazard present — informational only.
  none,

  /// Minor inconvenience with low to no safety impact.
  minor,

  /// Noticeable conditions that may affect plans or comfort.
  moderate,

  /// Potentially hazardous conditions warranting caution.
  high,

  /// Severe conditions posing a direct threat to safety or property.
  severe;

  static WeatherSeverity? tryParse(String? value) {
    if (value == null) return null;
    for (final severity in WeatherSeverity.values) {
      if (severity.name.toLowerCase() == value.toLowerCase()) return severity;
    }
    return null;
  }
}
