import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'weather_risk_evaluator.dart';

/// Shared [WeatherRiskEvaluator] instance.
///
/// The engine is stateless and deterministic, so a single const instance is
/// shared across the app.
final weatherRiskEvaluatorProvider = Provider<WeatherRiskEvaluator>(
  (ref) => const WeatherRiskEvaluator(),
);