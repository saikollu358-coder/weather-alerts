import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/errors/app_exception.dart';
import 'core/utils/logger.dart';
import 'data/repositories/local_repository_providers.dart';
import 'services/firebase/firebase_providers.dart';
import 'services/notifications/notification_service_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is optional: bootstrap never throws. When no configuration is
  // present the app runs in local-only (offline-first) mode.
  final container = ProviderContainer();
  await container.read(firebaseServiceProvider).bootstrap();

  // SQLite is optional too: on web (or when the platform cannot open it) the
  // app degrades gracefully without local persistence.
  final logger = container.read(appLoggerProvider);
  final localDatabase = container.read(localDatabaseProvider);
  try {
    await localDatabase.ensureOpen();
    logger.info('LocalDatabase', 'local storage ready at ${localDatabase.databasePath}');
  } on AppException catch (e) {
    logger.warning('LocalDatabase', 'local storage unavailable: ${e.runtimeType}');
  }

  // Notifications are optional too: the bootstrap never throws and degrades
  // gracefully on unsupported platforms.
  await container.read(notificationAppBootstrapProvider).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WeatherAlertsApp(),
    ),
  );
}