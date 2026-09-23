import '../entities/device_token_record.dart';

/// Repository boundary for device token management (Phase 12).
///
/// Tokens are persisted under `users/{uid}/devices/{deviceId}` in Firestore
/// so the server-side push router can match alerts to the right devices by
/// `locationKey`. The push router (`functions/src/server_alerts/push_router.ts`)
/// reads this collection directly via the Admin SDK; this repository owns the
/// client-side registration and lifecycle.
abstract interface class DeviceTokenRepository {
  /// Registers (or upserts) a device token for the current user.
  Future<void> registerToken(DeviceTokenRecord record);

  /// Updates the monitored [locationKeys] for an existing device token.
  Future<void> updateLocations({
    required String uid,
    required String deviceId,
    required List<String> locationKeys,
  });

  /// Removes a specific device token (e.g. on logout or token rotation).
  Future<void> removeToken({required String uid, required String deviceId});

  /// Removes all device tokens for a user (e.g. on account deletion).
  Future<void> removeAllTokens({required String uid});

  /// Lists all device tokens for a user.
  Future<List<DeviceTokenRecord>> tokensForUser(String uid);
}
