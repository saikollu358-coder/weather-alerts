import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../domain/services/notification_service.dart';
import '../firebase/device_token_providers.dart';
import '../firebase/firebase_providers.dart';
import 'local_notification_service.dart';
import 'notification_app_bootstrap.dart';

/// Local notification plugin service (widget-test safe: degrades gracefully).
final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService(),
);

/// Exposed [NotificationService] boundary used by features.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => ref.watch(localNotificationServiceProvider),
);

/// One-time startup wiring for notifications and the scheduled background task.
final notificationAppBootstrapProvider = Provider<NotificationAppBootstrap>(
  (ref) => NotificationAppBootstrap(
    localService: ref.watch(localNotificationServiceProvider),
    fcm: ref.watch(fcmServiceProvider),
    deviceTokenService: ref.watch(deviceTokenServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);