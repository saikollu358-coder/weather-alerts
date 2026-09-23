import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/domain/entities/weather/weather_bundle.dart';
import 'package:weather_alerts/features/alerts/application/alert_ingest_use_case.dart';
import 'package:weather_alerts/services/weather_analysis/weather_analysis.dart';
import 'package:weather_alerts/services/weather_analysis/weather_risk_evaluator.dart';

import '../helpers/pipeline_fakes.dart';

const String _locationKey = '1.0,2.0';

AlertIngestUseCase makeIngest(InMemoryAlertHistory repo) => AlertIngestUseCase(
      alerts: repo,
      evaluator: const WeatherRiskEvaluator(),
      logger: AppLogger(enabled: false),
    );

/// Runs the real evaluation engine on [bundle] so tests exercise the
/// analysis -> alert conversion end to end.
WeatherAnalysis analyze(WeatherBundle bundle) =>
    const WeatherRiskEvaluator().analyze(bundle, now: bundle.fetchedAtUtc);

Future<List<AlertRecord>> _ingest(
        AlertIngestUseCase ingest, WeatherBundle bundle) =>
    ingest.ingest(analyze(bundle), locationKey: _locationKey);

void main() {
  final at = DateTime.utc(2026, 9, 6, 12);

  group('AlertIngestUseCase', () {
    test('persists nothing for a benign analysis', () async {
      final repo = InMemoryAlertHistory();
      final ingest = makeIngest(repo);

      final active = await _ingest(ingest, sampleBundle(atUtc: at));

      expect(active, isEmpty);
      expect(repo.recordCount, 0);
    });

    test('creates one alert per actionable finding', () async {
      final repo = InMemoryAlertHistory();
      final ingest = makeIngest(repo);

      final active = await _ingest(
        ingest,
        sampleBundle(atUtc: at, hourly: [thunderHourlyPoint(at)]),
      );

      expect(active.length, 2);
      final byHazard = {for (final a in active) a.hazard: a};
      expect(byHazard['thunderstorm']!.status, AlertStatus.detected);
      expect(byHazard['lightning']!.status, AlertStatus.detected);
      expect(byHazard['thunderstorm']!.locationKey, _locationKey);
      expect(repo.recordCount, 2);
    });

    test('dedupes identical re-ingests within the same hour bucket', () async {
      final repo = InMemoryAlertHistory();
      final ingest = makeIngest(repo);

      await _ingest(
        ingest,
        sampleBundle(atUtc: at, hourly: [thunderHourlyPoint(at)]),
      );
      await _ingest(
        ingest,
        sampleBundle(atUtc: at, hourly: [thunderHourlyPoint(at)]),
      );

      expect(repo.recordCount, 2);
    });

    test('escalates when severity grows within the same hour bucket', () async {
      final repo = InMemoryAlertHistory();
      final ingest = makeIngest(repo);

      // WMO 61 -> light rain (minor).
      await _ingest(ingest, sampleBundle(atUtc: at, weatherCode: 61));
      // WMO 65 -> heavy rain (high) within the same hour.
      await _ingest(
        ingest,
        sampleBundle(
          atUtc: at.add(const Duration(minutes: 30)),
          weatherCode: 65,
        ),
      );

      final alerts = await repo.alerts();
      final rain = alerts.singleWhere((a) => a.hazard == 'rain');
      expect(rain.status, AlertStatus.escalated);
      expect(repo.recordCount, 1);
    });

    test('resolves hazards that are no longer present', () async {
      final repo = InMemoryAlertHistory();
      final ingest = makeIngest(repo);

      await _ingest(
        ingest,
        sampleBundle(atUtc: at, hourly: [thunderHourlyPoint(at)]),
      );
      expect(
        (await repo.activeAlerts()).where((a) => a.hazard == 'thunderstorm'),
        isNotEmpty,
      );

      await _ingest(
        ingest,
        sampleBundle(atUtc: at.add(const Duration(minutes: 30))),
      );

      final active = await repo.activeAlerts();
      expect(active.where((a) => a.hazard == 'thunderstorm'), isEmpty);
      final all = await repo.alerts();
      expect(
        all.singleWhere((a) => a.hazard == 'thunderstorm').status,
        AlertStatus.resolved,
      );
    });
  });
}