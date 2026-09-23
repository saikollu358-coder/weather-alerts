/// Application-wide constants.
///
/// Rationale: refresh intervals, cache time-to-live and limits used to protect
/// against battery drain and excessive API usage. Safety-rule thresholds do
/// NOT belong here — they live in the centralized, versioned rule definitions
/// (see `services/weather_analysis/` and WEATHER_SAFETY_RULES.md).
abstract final class AppConstants {
  AppConstants._();

  /// Public display name of the application.
  static const String appName = 'Weather Alerts';

  /// Stable identity used in logs / notifications / route names.
  static const String appId = 'weather_alerts';

  /// Honest positioning: an assessment, never a prediction service.
  static const String tagline = 'Weather Risk Assessment';

  /// Static disclaimer shown in alerts and safety surfaces.
  static const String assessmentDisclaimer =
      'This is an application-generated weather risk assessment and does not '
      'replace official emergency warnings. Always follow instructions from '
      'official authorities.';

  // ---------------------------------------------------------------------
  // Refresh / caching policy
  // ---------------------------------------------------------------------

  /// Minimum interval between unconditional weather refreshes.
  static const Duration weatherRefreshInterval = Duration(minutes: 15);

  /// Consider current-weather cache stale after this age.
  static const Duration currentWeatherCacheTtl = Duration(minutes: 30);

  /// Consider forecast cache stale after this age.
  static const Duration forecastCacheTtl = Duration(hours: 3);

  /// Consider an alert fully expired (not just resolved) after this age.
  static const Duration alertRetention = Duration(days: 7);

  /// Maximum number of cached alerts kept locally for a location.
  static const int maxCachedAlertsPerLocation = 200;

  /// Alert notification cooldown: repeated identical alerts are suppressed.
  static const Duration alertNotificationCooldown = Duration(hours: 3);

  /// Location monitoring: ignore GPS updates closer than this.
  static const double locationMinDistanceMeters = 250;

  /// Location monitoring: minimum time between GPS polls.
  static const Duration locationMinTimeBetweenUpdates = Duration(minutes: 10);
}