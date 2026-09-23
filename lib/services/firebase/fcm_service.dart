import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import 'firebase_availability.dart';

/// Wraps Firebase Cloud Messaging.
///
/// Guards every call with [FirebaseAvailability] so the local-only build never
/// touches the plugin. Token values are delivered to callers for persistence;
/// this service never writes tokens to logs.
class FcmService {
  FcmService({required this.firebase, required this.logger});

  final FirebaseAvailability firebase;
  final AppLogger logger;

  FirebaseMessaging get _messaging {
    _requireAvailable();
    return FirebaseMessaging.instance;
  }

  void _requireAvailable() {
    if (!firebase.isAvailable) {
      throw const FirebaseUnavailableException();
    }
  }

  bool get isAvailable => firebase.isAvailable;

  /// Requests notification permission (no-op / default on platforms where it
  /// is not needed). Returns false when permission is denied or unavailable.
  Future<bool> requestPermission() async {
    if (!firebase.isAvailable) return false;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } on Exception catch (e) {
      logger.warning('FcmService', 'permission request failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Retrieves the current registration token. Null when unavailable.
  Future<String?> getToken() async {
    if (!firebase.isAvailable) return null;
    try {
      return await _messaging.getToken();
    } on Exception catch (e) {
      logger.warning('FcmService', 'getToken failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Stream of refreshed tokens (useful for background token rotation).
  Stream<String> onTokenRefresh() {
    if (!firebase.isAvailable) return const Stream.empty();
    return _messaging.onTokenRefresh.handleError(_logAndRethrow);
  }

  /// Foreground push messages (default flow: forward to local notifications).
  Stream<RemoteMessage> onForegroundMessage() {
    if (!firebase.isAvailable) return const Stream.empty();
    return FirebaseMessaging.onMessage.handleError(_logAndRethrow);
  }

  /// Message that opened the app from a terminated state.
  Future<RemoteMessage?> getInitialMessage() async {
    if (!firebase.isAvailable) return null;
    try {
      return await _messaging.getInitialMessage();
    } on Exception catch (e) {
      logger.warning('FcmService', 'getInitialMessage failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Message that opened the app from background/ resumed state.
  Stream<RemoteMessage> onMessageOpenedApp() {
    if (!firebase.isAvailable) return const Stream.empty();
    return FirebaseMessaging.onMessageOpenedApp.handleError(_logAndRethrow);
  }

  Never _logAndRethrow(Object e, StackTrace st) {
    logger.warning('FcmService', 'message stream failed: ${e.runtimeType}');
    throw _mapEdgeToApp(e);
  }

  AppException _mapEdgeToApp(Object e) {
    if (e is AppException) return e;
    return const FirebaseOperationException(
      code: 'fcm',
      message: 'Push notifications could not be processed.',
    );
  }
}

