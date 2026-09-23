/// A registered device token for push notification delivery (Phase 12).
///
/// Stored under `users/{uid}/devices/{deviceId}` in Firestore so token
/// lifecycle is tied to the owning user and automatically cleaned up on
/// account deletion.
class DeviceTokenRecord {
  const DeviceTokenRecord({
    required this.token,
    required this.deviceId,
    required this.uid,
    this.locationKeys = const [],
    this.platform,
    this.createdAtUtc,
    this.updatedAtUtc,
  });

  /// FCM registration token.
  final String token;

  /// Stable device identifier (e.g. Android install UUID, iOS identifierForVendor).
  final String deviceId;

  /// Owning Firebase Auth uid.
  final String uid;

  /// Location keys this device should receive alerts for (e.g. `["30.2672,-97.7431"]`).
  ///
  /// Updated when the user adds, removes or changes monitored locations.
  /// The push router reads this field to decide which alerts to deliver.
  final List<String> locationKeys;

  /// Platform string (e.g. `android`, `ios`).
  final String? platform;

  /// Token creation timestamp (UTC).
  final DateTime? createdAtUtc;

  /// Last update timestamp (UTC); bumped when [locationKeys] or [token] changes.
  final DateTime? updatedAtUtc;

  DeviceTokenRecord copyWith({
    String? token,
    String? deviceId,
    String? uid,
    List<String>? locationKeys,
    String? platform,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) {
    return DeviceTokenRecord(
      token: token ?? this.token,
      deviceId: deviceId ?? this.deviceId,
      uid: uid ?? this.uid,
      locationKeys: locationKeys ?? this.locationKeys,
      platform: platform ?? this.platform,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}
