import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../services/weather_analysis/weather_analysis_providers.dart';
import 'alert_ingest_use_case.dart';
import 'alerts_controller.dart';
import 'alerts_state.dart';

/// The single alert-listing state provider for the application.
final alertsControllerProvider =
    NotifierProvider<AlertsController, AlertsState>(AlertsController.new);

/// Converts analyses into persisted alerts (dashboard pipeline step).
final alertIngestUseCaseProvider = Provider<AlertIngestUseCase>(
  (ref) => AlertIngestUseCase(
    alerts: ref.watch(alertHistoryRepositoryProvider),
    evaluator: ref.watch(weatherRiskEvaluatorProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);