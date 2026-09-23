import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/device_token_record.dart';
import '../../domain/repositories/device_token_repository.dart';
import '../../domain/repositories/monitored_location_repository.dart';
import '../../domain/repositories/preference_repository.dart';
import '../../domain/services/auth_service.dart';
import '../../services/firebase/fcm_service.dart';

/// Manages FCM device token lifecycle for push notification routing (Phase 12).
///
/// On every app start (and whenever the FCM token rotates), this service:
/// 1. Obtains the current FCM token.
/// 2. Persists it under `users/{uid}/devices/{deviceId}` in Firestore.
/// 3. Keeps the `locationKeys` array in sync with the user's monitored locations.
///
/// The server-side push router reads these documents to decide which devices
/// should receive alerts for each location.
class DeviceTokenService {
  DeviceTokenService({
    required this.fcm,
    required this.auth,
    required this.deviceTokens,
    required this.locations,
    required this.preferences,
    required this.logger,
  });

  final FcmService fcm;
  final AuthService auth;
  final DeviceTokenRepository deviceTokens;
  final MonitoredLocationRepository locations;
  final PreferenceRepository preferences;
  final AppLogger logger;

  static const String _deviceIdKey = 'device_id';
  bool _listening = false;
  bool _authListening = false;
  String? _lastUid;

  /// Registers the current device token and starts listening for rotations
  /// and auth changes.
  ///
  /// Safe to call multiple times; listeners are started only once.
  /// Idempotent: if the token hasn't changed, Firestore is not touched.
  Future<void> initialize() async {
    if (!fcm.isAvailable) return;
    await _registerCurrentToken();
    _startTokenRefreshListener();
    _startAuthListener();
  }

  /// Refreshes the `locationKeys` for the current device.
  ///
  /// Call when the user adds, removes or changes monitored locations.
  Future<void> syncLocations() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final deviceId = await _getOrCreateDeviceId();
    final allLocations = await locations.allLocations();
    final keys = allLocations.map((l) => l.locationKey).toList();
    await deviceTokens.updateLocations(
      uid: uid,
      deviceId: deviceId,
      locationKeys: keys,
    );
    logger.debug('DeviceTokenService', 'synced ${keys.length} location key(s)');
  }

  /// Removes the current device's token (e.g. on logout).
  Future<void> removeCurrentDevice() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final deviceId = await _getOrCreateDeviceId();
    await deviceTokens.removeToken(uid: uid, deviceId: deviceId);
    logger.debug('DeviceTokenService', 'removed device $deviceId');
  }

  // ------------------------------------------------------------------

  Future<void> _registerCurrentToken() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      logger.debug(
        'DeviceTokenService',
        'no signed-in user; skipping token registration',
      );
      return;
    }
    _lastUid = uid;
    final token = await fcm.getToken();
    if (token == null) {
      logger.debug('DeviceTokenService', 'FCM token unavailable');
      return;
    }
    final deviceId = await _getOrCreateDeviceId();
    final allLocations = await locations.allLocations();
    final keys = allLocations.map((l) => l.locationKey).toList();

    // Idempotent: skip the Firestore write when token and locations are
    // unchanged, so re-runs (app start, auth event) are cheap.
    final existing = await deviceTokens.tokensForUser(uid);
    final unchanged = existing.any(
      (r) =>
          r.deviceId == deviceId &&
          r.token == token &&
          _sameKeys(r.locationKeys, keys),
    );
    if (unchanged) {
      logger.debug('DeviceTokenService', 'token unchanged; skipping write');
      return;
    }

    await deviceTokens.registerToken(DeviceTokenRecord(
      token: token,
      deviceId: deviceId,
      uid: uid,
      locationKeys: keys,
      platform: defaultTargetPlatform.name,
      createdAtUtc: DateTime.now().toUtc(),
    ));
    logger.debug('DeviceTokenService', 'registered token for device $deviceId');
  }

  bool _sameKeys(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.toSet().containsAll(b);
  }

  void _startTokenRefreshListener() {
    if (_listening) return;
    _listening = true;
    fcm.onTokenRefresh().listen(
      (newToken) => _onTokenRefreshed(newToken),
      onError: (Object e) {
        logger.warning('DeviceTokenService', 'token refresh stream error: ${e.runtimeType}');
      },
    );
  }

  /// Registers / removes the device token as the auth session changes so a
  /// user who signs in after app start still gets push routing, and sign-out
  /// stops routing to this device.
  void _startAuthListener() {
    if (_authListening) return;
    _authListening = true;
    auth.watchAuthState().listen((user) {
      if (user == null) {
        unawaited(_removeForSignedOutUser());
      } else {
        _lastUid = user.uid;
        unawaited(_registerCurrentToken());
      }
    });
  }

  Future<void> _removeForSignedOutUser() async {
    final uid = _lastUid;
    if (uid == null) return;
    try {
      final deviceId = await _getOrCreateDeviceId();
      await deviceTokens.removeToken(uid: uid, deviceId: deviceId);
      logger.debug('DeviceTokenService', 'removed token for signed-out session');
    } catch (e) {
      logger.warning(
        'DeviceTokenService',
        'sign-out cleanup failed: ${e.runtimeType}',
      );
    } finally {
      _lastUid = null;
    }
  }

  Future<void> _onTokenRefreshed(String newToken) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    _lastUid = uid;
    final deviceId = await _getOrCreateDeviceId();
    final allLocations = await locations.allLocations();
    final keys = allLocations.map((l) => l.locationKey).toList();

    await deviceTokens.registerToken(DeviceTokenRecord(
      token: newToken,
      deviceId: deviceId,
      uid: uid,
      locationKeys: keys,
      platform: defaultTargetPlatform.name,
      createdAtUtc: DateTime.now().toUtc(),
    ));
    logger.debug('DeviceTokenService', 'refreshed token for device $deviceId');
  }

  /// Returns the stable device identifier, generating one if it doesn't exist.
  Future<String> _getOrCreateDeviceId() async {
    final existing = await preferences.read(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateDeviceId();
    await preferences.write(_deviceIdKey, id);
    return id;
  }

  /// Generates a short, URL-safe device identifier.
  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
