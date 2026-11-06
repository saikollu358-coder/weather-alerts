import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/features/alerts/application/alert_tap_controller.dart';
import 'package:weather_alerts/domain/enums/notification_permission.dart';
import 'package:weather_alerts/domain/services/notification_service.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';

/// Emits tap payloads on demand so tests can drive the controller without a
/// real notification plugin.
class _TapNotificationService implements NotificationService {
  final _controller = StreamController<String>.broadcast();

  void emit(String payload) => _controller.add(payload);

  @override
  Stream<String> onOpenedPayloads() => _controller.stream;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showAlert({
    required String title,
    required String body,
    required String payload,
  }) async {}
}

void main() {
  late _TapNotificationService notifications;
  late ProviderContainer container;

  setUp(() {
    notifications = _TapNotificationService();
    container = ProviderContainer(
      overrides: [
        notificationServiceProvider.overrideWithValue(notifications),
        appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
      ],
    );
  });

  // Individual tests dispose the container themselves (and read it after
  // disposal) where they need to; the default tearDown keeps the rest tidy.
  tearDown(() => container.dispose());

  String? pendingFingerprint() =>
      container.read(alertTapControllerProvider).fingerprint;

  test('starts with no pending tap', () {
    // Reading the provider is what attaches the streams.
    expect(container.read(alertTapControllerProvider).hasPendingTap, isFalse);
  });

  test('records the fingerprint from a local notification tap', () async {
    container.read(alertTapControllerProvider);
    await Future<void>.delayed(Duration.zero);

    notifications.emit(
      jsonEncode({
        'fingerprint': 'v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z',
        'hazard': 'Thunderstorm',
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      pendingFingerprint(),
      'v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z',
    );
  });

  test('ignores unparsable and id-less payloads', () async {
    container.read(alertTapControllerProvider);
    await Future<void>.delayed(Duration.zero);

    notifications.emit('not json');
    notifications.emit('{"hazard":"Rain"}');
    notifications.emit('');
    await Future<void>.delayed(Duration.zero);

    expect(pendingFingerprint(), isNull);
  });

  test('consume clears the pending tap exactly once', () async {
    container.read(alertTapControllerProvider);
    await Future<void>.delayed(Duration.zero);

    notifications.emit('{"fingerprint":"v8:Heat:loc:2026-09-06T12:00:00.000Z"}');
    await Future<void>.delayed(Duration.zero);
    expect(pendingFingerprint(), isNotNull);

    container.read(alertTapControllerProvider.notifier).consume();
    expect(pendingFingerprint(), isNull);

    // A second consume on an empty state must not change anything (and must not
    // throw), so a rebuild cannot clear a newer tap.
    container.read(alertTapControllerProvider.notifier).consume();
    expect(pendingFingerprint(), isNull);
  });

  test('a failing tap stream does not break the controller', () async {
    container.read(alertTapControllerProvider);
    await Future<void>.delayed(Duration.zero);

    notifications.emit('{"fingerprint":"v8:Heat:loc:2026-09-06T12:00:00.000Z"}');
    await Future<void>.delayed(Duration.zero);
    expect(pendingFingerprint(), isNotNull);
  });

  test('subscriptions are released when the provider is disposed', () async {
    final seen = <String?>[];
    final subscription = container.listen<AlertTapState>(
      alertTapControllerProvider,
      (_, next) => seen.add(next.fingerprint),
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);

    notifications.emit('{"fingerprint":"v8:Heat:loc:2026-09-06T12:00:00.000Z"}');
    await Future<void>.delayed(Duration.zero);
    expect(seen, [null, 'v8:Heat:loc:2026-09-06T12:00:00.000Z']);

    subscription.close();
    await Future<void>.delayed(Duration.zero);

    // After disposal the tap stream is detached, so a later tap produces no
    // state update (and cannot touch a dead notifier).
    notifications.emit('{"fingerprint":"v8:Ice:loc:2026-09-06T12:00:00.000Z"}');
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, 'v8:Heat:loc:2026-09-06T12:00:00.000Z');
    expect(seen, hasLength(2));
  });
}