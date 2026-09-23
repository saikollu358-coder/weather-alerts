import '../entities/alert_record.dart';
import '../entities/alert_status.dart';

/// Repository boundary for locally persisted alert history.
///
/// Alerts are deduplicated by a deterministic [AlertRecord.fingerprint] so the
/// same unchanged condition is never re-created repeatedly.
abstract interface class AlertHistoryRepository {
  /// Inserts a new alert or updates the existing one with the same
  /// fingerprint (deduplication). Always bumps `updatedAtUtc`.
  Future<void> upsertAlert(AlertRecord alert);

  /// Returns the stored alert with [fingerprint], or null.
  Future<AlertRecord?> alertByFingerprint(String fingerprint);

  /// Alerts matching optional filters, newest first.
  Future<List<AlertRecord>> alerts({
    AlertStatus? status,
    String? hazard,
    DateTime? since,
    int? limit,
  });

  /// Alerts currently live (not resolved/expired), newest first.
  Future<List<AlertRecord>> activeAlerts({int? limit});

  /// Transitions an alert's status (deduplicated by fingerprint).
  Future<void> updateStatus(String fingerprint, AlertStatus status);

  /// Marks an alert resolved with an optional resolution time.
  Future<void> markResolved(String fingerprint, {DateTime? at});

  /// Marks an alert as acknowledged by the user.
  Future<void> markAcknowledged(String fingerprint);

  /// Removes alerts detected before [cutoff]; returns the number removed.
  Future<int> purgeOlderThan(DateTime cutoff);

  /// Removes all alert history.
  Future<void> clear();
}