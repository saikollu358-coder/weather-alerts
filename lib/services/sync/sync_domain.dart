import '../../services/firebase/firestore_paths.dart';

/// Data domains synchronized between the local SQLite store and the user's
/// Firestore sub-collections (Phase 14).
enum SyncDomain {
  /// User-monitored locations (`users/{uid}/locations`).
  locations(FirestorePaths.locationsCollection, 'locations'),

  /// User preferences (`users/{uid}/preferences`).
  preferences(FirestorePaths.preferencesCollection, 'preferences'),

  /// Local alert history (`users/{uid}/user_alerts`).
  alerts(FirestorePaths.userAlertsCollection, 'alerts');

  const SyncDomain(this.collection, this.syncKey);

  /// Firestore sub-collection name under `users/{uid}`.
  final String collection;

  /// `sync_state` domain key used for attempt/success tracking.
  final String syncKey;
}