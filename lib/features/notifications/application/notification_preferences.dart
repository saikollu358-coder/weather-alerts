/// Preference keys controlling notification behavior.
abstract final class NotificationPreferences {
  NotificationPreferences._();

  /// Master switch for alert notifications (default: enabled).
  static const String enabledKey = 'notifications_enabled';

  /// When the user dismissed the in-app permission prompt ("Not now").
  static const String promptDismissedKey = 'notification_prompt_dismissed';

  /// True when a stored [value] means notifications are switched on.
  ///
  /// Absent value (never set) defaults to enabled.
  static bool enabledFrom(String? value) => value == null || value != 'false';

  /// True when a stored [value] means the prompt was dismissed.
  ///
  /// Absent value (never set) defaults to false (prompt may show).
  static bool promptDismissedFrom(String? value) => value == 'true';
}