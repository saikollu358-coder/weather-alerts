import '../../../domain/enums/notification_permission.dart';

/// Immutable notification-settings state consumed by the settings screen and
/// the dashboard permission prompt.
class NotificationSettingsState {
  const NotificationSettingsState({
    required this.isLoading,
    required this.enabled,
    required this.permission,
    required this.promptDismissed,
    this.errorMessage,
  });

  /// Loading placeholder; values are resolved from preferences + the service.
  const NotificationSettingsState.initial()
      : this(
          isLoading: true,
          enabled: true,
          permission: NotificationPermissionStatus.denied,
          promptDismissed: false,
        );

  /// True until preferences and OS permission have been resolved.
  final bool isLoading;

  /// Master switch for alert notifications (persisted preference).
  final bool enabled;

  /// OS-level notification permission, resolved from the service.
  final NotificationPermissionStatus permission;

  /// Whether the user dismissed the dashboard "Not now" prompt.
  final bool promptDismissed;

  /// User-safe message for the most recent failure.
  final String? errorMessage;

  /// Whether the dashboard prompt should ask for permission right now.
  bool get canShowPrompt =>
      enabled &&
      !promptDismissed &&
      permission != NotificationPermissionStatus.granted;

  NotificationSettingsState copyWith({
    bool? isLoading,
    bool? enabled,
    NotificationPermissionStatus? permission,
    bool? promptDismissed,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotificationSettingsState(
      isLoading: isLoading ?? this.isLoading,
      enabled: enabled ?? this.enabled,
      permission: permission ?? this.permission,
      promptDismissed: promptDismissed ?? this.promptDismissed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'NotificationSettingsState(enabled: $enabled, permission: $permission)';
}