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
  static String alertDetailsFor(String alertId) => '/alerts/$alertId';
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