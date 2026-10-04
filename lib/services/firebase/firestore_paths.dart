/// Centralized Firestore path builders.
///
/// Firestore holds identity and push routing only: the user's profile and the
/// FCM tokens the alert router needs. Weather, places and alert history stay on
/// the device, so `firestore.rules` can enforce per-user ownership with a
/// single pattern (`isOwner(uid)`).
abstract final class FirestorePaths {
  FirestorePaths._();

  /// A user's profile document id (under users/{uid}/profile).
  static const String profileCollection = 'profile';
  static const String profileDocument = 'default';

  /// Full path to the profile document of [uid].
  static String userProfile(String uid) =>
      'users/$uid/$profileCollection/$profileDocument';

  // -----------------------------------------------------------------
  // Device tokens (push routing)
  // -----------------------------------------------------------------

  /// Sub-collection holding registered FCM tokens for [uid].
  static const String devicesCollection = 'devices';

  /// Full path to a specific device document under the user.
  static String userDevice(String uid, String deviceId) =>
      'users/$uid/$devicesCollection/$deviceId';

  /// The `devices` collection reference path for [uid].
  static String userDevicesCollection(String uid) =>
      'users/$uid/$devicesCollection';
}