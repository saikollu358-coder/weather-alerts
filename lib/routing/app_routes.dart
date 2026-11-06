/// Centralized route locations and names.
///
/// Keeping route identifiers here (instead of literal strings scattered across
/// the codebase) makes deep links / notification taps and redirect logic
/// consistent and refactor-safe.
abstract final class RoutePath {
  RoutePath._();

  static const String splash = '/';
  static const String localMode = '/local-mode';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String locations = '/locations';
  static const String activeAlerts = '/alerts/active';
  static const String alertDetails = '/alerts/:id';
  static const String alertHistory = '/alerts/history';

  /// Builds an [alertDetails] path for the given alert id.
  ///
  /// Alert fingerprints contain `:` and `,` (for example
  /// `v8:Thunderstorm:42.123,-71.988:2026-10-05T14:00:00.000Z`), so the id is
  /// percent-encoded to keep the path a single, unambiguous segment. go_router
  /// decodes path parameters again, so the screen still receives the raw id.
  static String alertDetailsFor(String alertId) =>
      '/alerts/${Uri.encodeComponent(alertId)}';
}

abstract final class RouteName {
  RouteName._();

  static const String splash = 'splash';
  static const String localMode = 'local-mode';
  static const String login = 'login';
  static const String register = 'register';
  static const String forgotPassword = 'forgot-password';
  static const String home = 'home';
  static const String profile = 'profile';
  static const String settings = 'settings';
  static const String locations = 'locations';
  static const String activeAlerts = 'active-alerts';
  static const String alertDetails = 'alert-details';
  static const String alertHistory = 'alert-history';
}