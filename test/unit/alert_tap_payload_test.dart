import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/features/alerts/application/alert_tap_payload.dart';

void main() {
  group('AlertTapPayload', () {
    test('parses the payload shape produced by the background check', () {
      // Same keys as BackgroundWeatherCheckUseCase._notify.
      final raw = jsonEncode({
        'fingerprint': 'v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z',
        'notificationKey': 'v8:Thunderstorm:42.123,-71.988',
        'locationKey': '42.123,-71.988',
        'hazard': 'Thunderstorm',
        'severity': 'SEVERE',
        'rulesVersion': '8',
      });

      final payload = AlertTapPayload.tryParseJson(raw);

      expect(payload, isNotNull);
      expect(payload!.fingerprint,
          'v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z');
      expect(payload.hazard, 'Thunderstorm');
      expect(payload.severity, 'SEVERE');
      expect(payload.locationKey, '42.123,-71.988');
      expect(payload.hasAlert, isTrue);
    });

    test('parses the string-only FCM data map from push_router', () {
      final payload = AlertTapPayload.fromMap({
        'fingerprint': 'v8:Heat:42.123,-71.988:2026-09-06T12:00:00.000Z',
        'notificationKey': 'v8:Heat:42.123,-71.988',
        'locationKey': '42.123,-71.988',
        'hazard': 'Heat',
        'severity': 'HIGH',
        'rulesVersion': '8',
      });

      expect(payload.fingerprint, contains('Heat'));
      expect(payload.hasAlert, isTrue);
    });

    test('rejects payloads that are blank or not JSON objects', () {
      expect(AlertTapPayload.tryParseJson(null), isNull);
      expect(AlertTapPayload.tryParseJson(''), isNull);
      expect(AlertTapPayload.tryParseJson('   '), isNull);
      expect(AlertTapPayload.tryParseJson('not json'), isNull);
      expect(AlertTapPayload.tryParseJson('[1,2,3]'), isNull);
      expect(AlertTapPayload.tryParseJson('"a string"'), isNull);
    });

    test('a payload without a usable id is not actionable', () {
      expect(
        AlertTapPayload.tryParseJson('{"hazard":"Rain"}')!.hasAlert,
        isFalse,
      );
      expect(
        AlertTapPayload.fromMap({'fingerprint': ''}).hasAlert,
        isFalse,
      );
      // Whitespace-padded ids would never match a stored record.
      expect(
        AlertTapPayload.fromMap({'fingerprint': '   '}).hasAlert,
        isFalse,
      );
    });

    test('non-string values from the JSON path are coerced', () {
      final payload = AlertTapPayload.fromMap({'severity': 3, 'hazard': 42});

      expect(payload.severity, '3');
      expect(payload.hazard, '42');
    });
  });
}