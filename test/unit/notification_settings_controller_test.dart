import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/enums/notification_permission.dart';
import 'package:weather_alerts/features/notifications/application/notification_preferences.dart';
import 'package:weather_alerts/features/notifications/application/notification_settings_providers.dart';
import 'package:weather_alerts/features/notifications/application/notification_settings_state.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';

import '../helpers/pipeline_fakes.dart';

void main() {
  late FakeNotificationService service;
  late InMemoryPreferences preferences;
  late ProviderContainer container;

  /// Starts the controller's async resolve and flushes pending futures.
  Future<void> load() async {
    container.read(notificationSettingsControllerProvider);
    await pumpEventQueue();
  }

  NotificationSettingsState state() =>
      container.read(notificationSettingsControllerProvider);

  group('NotificationSettingsController', () {
    setUp(() {
      service = FakeNotificationService();
      preferences = InMemoryPreferences();
      container = ProviderContainer(
        overrides: [
          appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          preferenceRepositoryProvider.overrideWithValue(preferences),
          notificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
    });

    test('resolves defaults when nothing is persisted', () async {
      await load();

      expect(state().isLoading, isFalse);
      expect(state().enabled, isTrue);
      expect(state().permission, NotificationPermissionStatus.granted);
      expect(state().promptDismissed, isFalse);
      expect(state().errorMessage, isNull);
    });

    test('resolves persisted disabled master switch', () async {
      await preferences.write(NotificationPreferences.enabledKey, 'false');
      await load();

      expect(state().enabled, isFalse);
    });

    test('resolves a denied OS permission', () async {
      service.permission = NotificationPermissionStatus.denied;
      await load();

      expect(state().permission, NotificationPermissionStatus.denied);
      expect(state().canShowPrompt, isTrue);
    });

    test('resolves a previously dismissed prompt', () async {
      await preferences.write(
        NotificationPreferences.promptDismissedKey,
        'true',
      );
      await load();

      expect(state().promptDismissed, isTrue);
      expect(state().canShowPrompt, isFalse);
    });

    test('toggleEnabled(false) persists the master switch off', () async {
      await load();
      await container
          .read(notificationSettingsControllerProvider.notifier)
          .toggleEnabled(false);
      await pumpEventQueue();

      expect(state().enabled, isFalse);
      expect(state().canShowPrompt, isFalse);
      expect(
        await preferences.read(NotificationPreferences.enabledKey),
        'false',
      );
    });

    test('toggleEnabled(true) writes the switch back on', () async {
      await preferences.write(NotificationPreferences.enabledKey, 'false');
      await load();
      expect(state().enabled, isFalse);

      await container
          .read(notificationSettingsControllerProvider.notifier)
          .toggleEnabled(true);
      await pumpEventQueue();

      expect(state().enabled, isTrue);
      expect(
        await preferences.read(NotificationPreferences.enabledKey),
        'true',
      );
    });

    test('allowNotifications grants permission and refreshes the state',
        () async {
      service.permission = NotificationPermissionStatus.denied;
      service.grantOnRequest = true;
      await load();
      expect(state().permission, NotificationPermissionStatus.denied);

      await container
          .read(notificationSettingsControllerProvider.notifier)
          .allowNotifications();
      await pumpEventQueue();

      expect(service.requestPermissionCalled, isTrue);
      expect(state().permission, NotificationPermissionStatus.granted);
    });

    test('allowNotifications keeps denied when the user declines', () async {
      service.permission = NotificationPermissionStatus.denied;
      await load();

      await container
          .read(notificationSettingsControllerProvider.notifier)
          .allowNotifications();
      await pumpEventQueue();

      expect(service.requestPermissionCalled, isTrue);
      expect(state().permission, NotificationPermissionStatus.denied);
      expect(state().canShowPrompt, isTrue);
    });

    test('dismissPrompt persists so the banner stays hidden', () async {
      service.permission = NotificationPermissionStatus.denied;
      await load();
      expect(state().canShowPrompt, isTrue);

      await container
          .read(notificationSettingsControllerProvider.notifier)
          .dismissPrompt();
      await pumpEventQueue();

      expect(state().promptDismissed, isTrue);
      expect(state().canShowPrompt, isFalse);
      expect(
        await preferences.read(NotificationPreferences.promptDismissedKey),
        'true',
      );
    });

    test('openSystemSettings delegates to the service', () async {
      await load();
      await container
          .read(notificationSettingsControllerProvider.notifier)
          .openSystemSettings();
      await pumpEventQueue();

      expect(service.openSystemSettingsCalled, isTrue);
    });

    test('preference failure degrades without crashing', () async {
      final failingPrefs = InMemoryPreferences()..failReads = true;
      final failingContainer = ProviderContainer(
        overrides: [
          appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          preferenceRepositoryProvider.overrideWithValue(failingPrefs),
          notificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(failingContainer.dispose);

      failingContainer.read(notificationSettingsControllerProvider);
      await pumpEventQueue();

      final state = failingContainer.read(notificationSettingsControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.enabled, isTrue);
      expect(state.errorMessage, isNotNull);
    });
  });
}