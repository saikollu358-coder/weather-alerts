import '../enums/notification_permission.dart';

/// Boundary for delivering weather-risk alerts to the OS.
///
/// Implementations wrap a local notification plugin (or a fake in tests).
/// Every method must degrade gracefully when notifications are unsupported or
/// permission is denied, so the app stays fully usable without them.
abstract interface class NotificationService {
  /// Requests OS-level notification permission.
  ///
  /// Returns true when the app is allowed to post notifications (or when the
  /// platform needs no explicit permission). After the user dismisses the
  /// system prompt twice, the platform usually stops showing it and the caller
  /// should route to [openSystemSettings].
  Future<bool> requestPermission();

  /// Current OS-level notification permission, for the settings UI and the
  /// in-app permission prompt.
  Future<NotificationPermissionStatus> permissionStatus();

  /// Opens the OS settings page for this app where notification permission can
  /// be re-granted after a permanent denial. Degrades to a no-op on platforms
  /// without an app-settings deep link.
  Future<void> openSystemSettings();

  /// Posts an alert notification for the user to open or read.
  Future<void> showAlert({
    required String title,
    required String body,
    required String payload,
  });

  /// Payloads of notifications the user tapped/opened.
  ///
  /// The payload is the json string passed to [showAlert], letting a later
  /// phase navigate to the matching alert detail route.
  Stream<String> onOpenedPayloads();
}