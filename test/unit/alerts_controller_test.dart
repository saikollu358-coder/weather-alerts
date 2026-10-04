import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/features/alerts/application/alerts_providers.dart';
import 'package:weather_alerts/features/alerts/application/alerts_state.dart';

import '../helpers/pipeline_fakes.dart';

AlertRecord sampleAlert({
  required String fingerprint,
  AlertStatus status = AlertStatus.active,
  String hazard = 'thunderstorm',
  String severity = 'high',
  String locationKey = '1.0,2.0',
  bool acknowledged = false,
}) {
  final at = DateTime.utc(2026, 9, 6, 12);
  return AlertRecord(
    fingerprint: fingerprint,
    hazard: hazard,
    severity: severity,
    status: status,
    title: 'High Thunderstorm',
    description: 'Thunderstorm activity expected.',
    reason: 'Thunderstorm activity expected within 24 h.',
    locationKey: locationKey,
    detectedAtUtc: at,
    updatedAtUtc: at,
    acknowledged: acknowledged,
  );
}

void main() {
  group('AlertsController', () {
    test('starts by loading into a ready state with no active alerts', () async {
      final container = makePipelineContainer();
      addTearDown(container.dispose);

      container.read(alertsControllerProvider);
      await pumpUntil(
        () => container.read(alertsControllerProvider).status ==
            AlertsStatus.ready,
      );

      final state = container.read(alertsControllerProvider);
      expect(state.status, AlertsStatus.ready);
      expect(state.active, isEmpty);
      expect(state.hasActive, isFalse);
    });

    test('exposes only active alerts and hides resolved and expired ones',
        () async {
      final alerts = InMemoryAlertHistory(seed: [
        sampleAlert(fingerprint: 'a'),
        sampleAlert(
          fingerprint: 'a2',
          hazard: 'wind',
        ),
        sampleAlert(
          fingerprint: 'r',
          status: AlertStatus.resolved,
          hazard: 'rain',
        ),
        sampleAlert(
          fingerprint: 'e',
          status: AlertStatus.expired,
          hazard: 'heat',
        ),
      ]);
      final container = makePipelineContainer(alerts: alerts);
      addTearDown(container.dispose);

      container.read(alertsControllerProvider);
      await pumpUntil(
        () => container.read(alertsControllerProvider).status ==
            AlertsStatus.ready,
      );

      final state = container.read(alertsControllerProvider);
      expect(state.active.length, 2);
      expect(
        state.active.map((a) => a.hazard),
        containsAll(['thunderstorm', 'wind']),
      );
      expect(state.hasActive, isTrue);
      expect(
        state.active.map((a) => a.hazard),
        isNot(anyOf(contains('rain'), contains('heat'))),
      );
    });

    test('acknowledge marks the alert and refreshes the list', () async {
      final alerts = InMemoryAlertHistory(
        seed: [sampleAlert(fingerprint: 'a')],
      );
      final container = makePipelineContainer(alerts: alerts);
      addTearDown(container.dispose);

      await pumpUntil(
        () => container.read(alertsControllerProvider).status ==
            AlertsStatus.ready,
      );
      await container
          .read(alertsControllerProvider.notifier)
          .acknowledge('a');

      final updated = await container
          .read(alertHistoryRepositoryProvider)
          .alertByFingerprint('a');
      expect(updated!.acknowledged, isTrue);
      expect(container.read(alertsControllerProvider).status, AlertsStatus.ready);
    });

    test('surfaces an error state when the repository throws', () async {
      final alerts = InMemoryAlertHistory()..failLoads = true;
      final container = makePipelineContainer(alerts: alerts);
      addTearDown(container.dispose);

      await pumpUntil(
        () => container.read(alertsControllerProvider).status ==
            AlertsStatus.error,
      );

      final state = container.read(alertsControllerProvider);
      expect(state.status, AlertsStatus.error);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, isNot(contains('boom')));
    });
  });
}