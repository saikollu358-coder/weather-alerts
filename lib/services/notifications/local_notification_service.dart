import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../../domain/enums/notification_permission.dart';
import '../../domain/services/notification_service.dart';

/// [NotificationService] backed by `flutter_local_notifications`.
///
/// Initialization is lazy and idempotent: the plugin is only opened on the
/// first show/permission call. Every plugin call is guarded so an unsupported
/// platform, a missing plugin or a denied permission never propagates an
/// exception into the alert pipeline.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Android notification channel used for weather-risk alerts.
  static const String channelId = 'weather_alerts';
  static const String channelName = 'Weather alerts';
  static const String channelDescription =
      'Weather risk alerts for monitored locations';

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _opened =
      StreamController<String>.broadcast();

  bool _initialized = false;
  int _nextId = 1;

  /// How many times the user dismissed the OS permission prompt. Used as the
  /// permanently-denied heuristic: after two dismissals the OS stops showing
  /// the dialog, so the UI routes to system settings instead.
  int _permissionPromptAttempts = 0;

  @override
  Stream<String> onOpenedPayloads() => _opened.stream;

  /// Opens the plugin and creates the notification channel. Idempotent and
  /// safe to call from any isolate or platform.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      _initialized = ok ?? true;
    } on Exception {
      _initialized = false;
    }
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty && !_opened.isClosed) {
      _opened.add(payload);
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) {
      await initialize();
    }
    if (!_initialized) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? false;
        if (granted) {
          _permissionPromptAttempts = 0;
        } else {
          _permissionPromptAttempts++;
        }
        return granted;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        if (granted) {
          _permissionPromptAttempts = 0;
        } else {
          _permissionPromptAttempts++;
        }
        return granted;
      }
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    if (!_initialized) {
      await initialize();
    }
    // Graceful defaults: unsupported platforms or plugins always look granted.
    if (!_initialized) return NotificationPermissionStatus.granted;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled() ?? true;
        if (enabled) return NotificationPermissionStatus.granted;
        return _permissionPromptAttempts >= 2
            ? NotificationPermissionStatus.permanentlyDenied
            : NotificationPermissionStatus.denied;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final options = await ios.checkPermissions();
        if (options?.isEnabled ?? false) {
          return NotificationPermissionStatus.granted;
        }
        return _permissionPromptAttempts >= 2
            ? NotificationPermissionStatus.permanentlyDenied
            : NotificationPermissionStatus.denied;
      }
      return NotificationPermissionStatus.granted;
    } on Exception {
      return NotificationPermissionStatus.granted;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    try {
      // Reuses the location plugin's app-settings deep link, which opens this
      // app's OS settings page where notification permission can be re-granted.
      await Geolocator.openAppSettings();
    } on Exception {
      // Degrade to a no-op on platforms without an app-settings deep link.
    }
  }

  @override
  Future<void> showAlert({
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    if (!_initialized) return;
    try {
      // ignore: discarded_futures
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } on Exception {
      // Delivery failures are informational, never fatal.
    }
  }
}