/// Centralized Firestore path builders.
///
/// All user data lives under `users/{uid}` so `firestore.rules` can enforce
/// per-user ownership with a single pattern (`isOwner(uid)`).
abstract final class FirestorePaths {
  FirestorePaths._();

  /// A user's profile document id (under users/{uid}/profile).
  static const String profileCollection = 'profile';
  static const String profileDocument = 'default';

  /// Full path to the profile document of [uid].
  static String userProfile(String uid) =>
      'users/$uid/$profileCollection/$profileDocument';

  // -----------------------------------------------------------------
  // Device tokens (Phase 12)
  // -----------------------------------------------------------------

  /// Sub-collection holding registered FCM tokens for [uid].
  static const String devicesCollection = 'devices';

  /// Full path to a specific device document under the user.
  static String userDevice(String uid, String deviceId) =>
      'users/$uid/$devicesCollection/$deviceId';

  /// The `devices` collection reference path for [uid].
  static String userDevicesCollection(String uid) =>
      'users/$uid/$devicesCollection';

  // -----------------------------------------------------------------
  // Cloud sync (Phase 14)
  // -----------------------------------------------------------------

  /// User-owned monitored locations, keyed by `location_key`.
  static const String locationsCollection = 'locations';

  /// User-owned preferences, keyed by preference key.
  static const String preferencesCollection = 'preferences';

  /// User-owned alert history, keyed by alert fingerprint.
  static const String userAlertsCollection = 'user_alerts';
}