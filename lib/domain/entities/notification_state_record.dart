/// Delivery state of a single alert notification, used to deduplicate and
/// enforce cooldowns so the same unchanged condition never spams the user.
class NotificationStateRecord {
  const NotificationStateRecord({
    required this.fingerprint,
    required this.lastNotifiedAtUtc,
    this.notificationCount = 1,
    this.status = 'sent',
    this.updatedAtUtc,
  });

  /// Alert fingerprint this delivery belongs to.
  final String fingerprint;

  /// Last time this alert was notified (always UTC).
  final DateTime lastNotifiedAtUtc;

  /// How many times this alert has been notified.
  final int notificationCount;

  /// Delivery state, e.g. `sent`, `failed`, `suppressed`.
  final String status;

  /// Last delivery update (defaults to [lastNotifiedAtUtc]).
  final DateTime? updatedAtUtc;

  @override
  String toString() =>
      'NotificationStateRecord($fingerprint, x$notificationCount @ ${lastNotifiedAtUtc.toIso8601String()})';
}