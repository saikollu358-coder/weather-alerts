import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/weather_analysis/weather_analysis.dart';
import '../../../services/weather_analysis/weather_analysis_providers.dart';
import '../../weather/application/weather_providers.dart';
import 'dashboard_controller.dart';
import 'dashboard_state.dart';

/// Deterministic risk analysis of the current weather bundle.
///
/// Anchored to the bundle's fetch time so the same data always yields the same
/// analysis (and the same alert fingerprints) regardless of when the widget
/// tree rebuilds.
final weatherAnalysisProvider = Provider<WeatherAnalysis?>((ref) {
  final weather = ref.watch(weatherControllerProvider);
  final bundle = weather.bundle;
  if (bundle == null) return null;
  return ref
      .watch(weatherRiskEvaluatorProvider)
      .analyze(bundle, now: bundle.fetchedAtUtc);
});

/// Orchestrates the dashboard data pipeline and exposes its state.
final dashboardControllerProvider =
    NotifierProvider<DashboardController, DashboardState>(DashboardController.new);