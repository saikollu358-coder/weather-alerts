/// Sync delivery state for a synchronization domain.
enum SyncStatus { never, pending, success, failure }

/// Synchronization metadata for a sync domain (e.g. `alerts`, `preferences`,
/// `locations`), stored locally so retries resume after connectivity returns.
class SyncStateRecord {
  const SyncStateRecord({
    required this.syncKey,
    this.value,
    required this.lastAttemptAtUtc,
    this.lastSuccessAtUtc,
    this.status = SyncStatus.never,
  });

  /// Domain key, e.g. `alerts`, `preferences`.
  final String syncKey;

  /// Optional opaque payload/token associated with the sync domain.
  final String? value;

  /// When the last sync attempt happened (always UTC).
  final DateTime lastAttemptAtUtc;

  /// When the last successful sync happened (always UTC).
  final DateTime? lastSuccessAtUtc;

  final SyncStatus status;

  SyncStateRecord copyWith({
    String? value,
    bool clearValue = false,
    DateTime? lastAttemptAtUtc,
    DateTime? lastSuccessAtUtc,
    bool clearLastSuccess = false,
    SyncStatus? status,
  }) {
    return SyncStateRecord(
      syncKey: syncKey,
      value: clearValue ? null : (value ?? this.value),
      lastAttemptAtUtc: lastAttemptAtUtc ?? this.lastAttemptAtUtc,
      lastSuccessAtUtc:
          clearLastSuccess ? null : (lastSuccessAtUtc ?? this.lastSuccessAtUtc),
      status: status ?? this.status,
    );
  }

  @override
  String toString() => 'SyncStateRecord($syncKey, ${status.name})';
}