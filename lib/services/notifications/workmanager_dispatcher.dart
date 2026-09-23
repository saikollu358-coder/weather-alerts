import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../../data/datasources/local/local_database_factory.dart';
import '../../data/repositories/alert_history_repository_impl.dart';
import '../../data/repositories/monitored_location_repository_impl.dart';
import '../../data/repositories/notification_state_repository_impl.dart';
import '../../data/repositories/preference_repository_impl.dart';
import '../../data/repositories/weather_cache_repository_impl.dart';
import '../../features/alerts/application/alert_ingest_use_case.dart';
import '../../features/notifications/application/background_weather_check_use_case.dart';
import '../../services/weather/open_meteo_weather_service.dart';
import '../../services/weather_analysis/weather_risk_evaluator.dart';
import 'local_notification_service.dart';

/// Unique name of the periodic background check task.
const String kBackgroundTaskName = 'weather_alerts_background_check';

/// OS entry point invoked by the workmanager plugin in a background isolate.
///
/// Must stay a top-level function annotated exactly like this: the plugin
/// resolves it by name when a scheduled task fires.
@pragma('vm:entry-point')
void weatherAlertsCallbackDispatcher() {
  Workmanager().executeTask(handleBackgroundCheckTask);
}

/// Runs one background weather check in the worker isolate.
///
/// Builds its own object graph (no Riverpod container is reachable here):
/// SQLite connection + repository implementations + cache-first weather
/// service + the same deterministic evaluator the app uses.
///
/// Returns true when the task ran to completion, false only on an unexpected
/// failure (so the OS may retry).
Future<bool> handleBackgroundCheckTask(
  String taskName,
  Map<String, dynamic>? inputData,
) async {
  final appConfig = AppConfig.fromEnvironment();
  final logger = AppLogger.fromConfig(appConfig);
  try {
    final db = createPlatformLocalDatabase();
    await db.ensureOpen();
    final alerts = AlertHistoryRepositoryImpl(db: db, logger: logger);
    final useCase = BackgroundWeatherCheckUseCase(
      locations: MonitoredLocationRepositoryImpl(db: db, logger: logger),
      preferences: PreferenceRepositoryImpl(db: db, logger: logger),
      weather: OpenMeteoWeatherService(
        config: appConfig,
        client: http.Client(),
        cache: WeatherCacheRepositoryImpl(db: db, logger: logger),
        logger: logger,
      ),
      evaluator: const WeatherRiskEvaluator(),
      alertHistory: alerts,
      notificationState: NotificationStateRepositoryImpl(db: db, logger: logger),
      ingest: AlertIngestUseCase(
        alerts: alerts,
        evaluator: const WeatherRiskEvaluator(),
        logger: logger,
      ),
      notifier: LocalNotificationService(),
      logger: logger,
    );
    final result = await useCase.check();
    logger.debug('BackgroundWeatherCheck', 'task completed: $result');
    return true;
  } catch (e) {
    logger.warning(
      'BackgroundWeatherCheck',
      'task failed with ${e.runtimeType}',
    );
    return false;
  }
}