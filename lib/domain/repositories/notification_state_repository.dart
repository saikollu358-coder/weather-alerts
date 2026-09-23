import '../entities/notification_state_record.dart';

/// Repository boundary for notification delivery state.
///
/// Used to deduplicate alerts and enforce cooldowns: the same unchanged
/// condition must not notify the user repeatedly.
abstract interface class NotificationStateRepository {
  /// Delivery record for [fingerprint], or null.
  Future<NotificationStateRecord?> recordFor(String fingerprint);

  /// Records (or updates) a delivery for [fingerprint], incrementing the
  /// delivery count. Call for every actually-sent notification.
  Future<void> recordNotification(
    String fingerprint, {
    DateTime? at,
    String status = 'sent',
  });

  /// Whether [fingerprint] may be notified again now, given the unchanged
  /// alert must respect a [cooldown] since its last notification.
  Future<bool> shouldNotify(
    String fingerprint,
    Duration cooldown, {
    DateTime? now,
  });

  /// Delivery records updated since [since], newest first.
  Future<List<NotificationStateRecord>> recent(DateTime since);

  /// Removes delivery records whose last update predates [cutoff].
  Future<void> purgeOlderThan(DateTime cutoff);
}