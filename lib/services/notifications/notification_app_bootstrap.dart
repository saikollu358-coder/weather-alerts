import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../firebase/device_token_service.dart';
import '../firebase/fcm_service.dart';
import 'local_notification_service.dart';
import 'workmanager_dispatcher.dart';

/// One-time startup wiring for notifications and the scheduled background task.
///
/// Safe to run on any platform: unsupported plugins degrade to a no-op so the
/// app still boots in local-only or web mode.
class NotificationAppBootstrap {
  NotificationAppBootstrap({
    required this.localService,
    required this.fcm,
    required this.deviceTokenService,
    required this.logger,
  });

  final LocalNotificationService localService;
  final FcmService fcm;
  final DeviceTokenService deviceTokenService;
  final AppLogger logger;

  bool _started = false;

  /// Opens the local notification plugin, schedules the periodic background
  /// check, registers the FCM device token and forwards foreground FCM
  /// messages to a local notification.
  /// Idempotent.
  ///
  /// OS notification permission is NOT requested here: since Phase 11 the
  /// settings screen and the dashboard prompt own the explicit user-facing
  /// permission request, so notification delivery never dangles off a startup
  /// advisory dialog.
  Future<void> initialize() async {
    if (_started) return;
    _started = true;

    await localService.initialize();
    await _schedulePeriodicCheck();
    _wireFcm();
    await _registerDeviceToken();
  }

  Future<void> _schedulePeriodicCheck() async {
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(weatherAlertsCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        kBackgroundTaskName,
        kBackgroundTaskName,
        frequency: AppConstants.weatherRefreshInterval,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      logger.debug(
        'NotificationBootstrap',
        'periodic background check scheduled '
            '(${AppConstants.weatherRefreshInterval.inMinutes} min)',
      );
    } on Exception catch (e) {
      logger.warning(
        'NotificationBootstrap',
        'periodic task unavailable: ${e.runtimeType}',
      );
    }
  }

  void _wireFcm() {
    if (!fcm.isAvailable) return;
    fcm.onForegroundMessage().listen(
      _forwardForeground,
      onError: (Object _) {
        // Stream failures are advisory; the local pipeline keeps running.
      },
    );
  }

  /// Registers the current device token in Firestore for push routing (Phase 12).
  Future<void> _registerDeviceToken() async {
    try {
      await deviceTokenService.initialize();
    } on Exception catch (e) {
      // Token registration is best-effort; a failure must not block app startup.
      logger.warning(
        'NotificationBootstrap',
        'device token registration failed: ${e.runtimeType}',
      );
    }
  }

  /// Forwards an FCM push that carries our alert payload to a local
  /// notification so the message reaches the tray in any app state.
  Future<void> _forwardForeground(RemoteMessage message) async {
    final data = message.data;
    if (data['fingerprint'] == null && data['hazard'] == null) return;
    final notification = message.notification;
    await localService.showAlert(
      title: notification?.title ?? 'Weather alert',
      body: notification?.body ?? 'A weather hazard requires attention.',
      payload: jsonEncode(data),
    );
  }
}