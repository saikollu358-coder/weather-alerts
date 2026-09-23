/// Application-level notification permission state, mapping the platform's
/// states to the three cases the UI needs to branch on.
///
/// Platforms without a runtime notification permission (e.g. Android < 13)
/// consistently report [granted].
enum NotificationPermissionStatus {
  /// The user has not granted notification access, or denied it once and may
  /// still be re-prompted (the OS dialog is allowed once more).
  denied,

  /// The user denied repeatedly and the OS no longer shows the prompt; only
  /// the system settings page can re-grant access.
  permanentlyDenied,

  /// Notification access is granted.
  granted,
}