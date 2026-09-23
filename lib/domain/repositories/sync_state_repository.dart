import '../entities/sync_state_record.dart';

/// Repository boundary for synchronization metadata.
///
/// Tracks the last attempt/success per sync domain so that after connectivity
/// is restored the app can resume failed synchronizations.
abstract interface class SyncStateRepository {
  /// Metadata for [syncKey], or null when never attempted.
  Future<SyncStateRecord?> stateFor(String syncKey);

  /// Records a sync attempt (status [SyncStatus.pending]).
  Future<void> recordAttempt(String syncKey, {String? value});

  /// Records a successful sync; resets the payload and status.
  Future<void> recordSuccess(String syncKey, {String? value, DateTime? at});

  /// Records a failed sync attempt.
  Future<void> recordFailure(String syncKey, {String? value});

  /// All sync metadata, newest attempts first.
  Future<List<SyncStateRecord>> all();
}