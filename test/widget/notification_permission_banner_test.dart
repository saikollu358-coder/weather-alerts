import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/enums/notification_permission.dart';
import 'package:weather_alerts/features/dashboard/presentation/dashboard_shell.dart';
import 'package:weather_alerts/features/notifications/application/notification_preferences.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

import '../helpers/pipeline_fakes.dart';

Widget _shell({
  FakeNotificationService? notifications,
  InMemoryPreferences? preferences,
}) {
  final at = DateTime.utc(2026, 9, 6, 12);
  return ProviderScope(
    overrides: [
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
      preferenceRepositoryProvider.overrideWithValue(
        preferences ?? InMemoryPreferences(),
      ),
      notificationServiceProvider.overrideWithValue(
        notifications ?? FakeNotificationService(),
      ),
      monitoredLocationRepositoryProvider.overrideWithValue(
        InMemoryMonitoredLocations(
          seed: [sampleLocation(id: 1, name: 'Testville', isPrimary: true)],
        ),
      ),
      alertHistoryRepositoryProvider.overrideWithValue(InMemoryAlertHistory()),
      weatherServiceProvider.overrideWithValue(
        FakeWeatherService(bundle: sampleBundle(atUtc: at)),
      ),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ],
    child: const MaterialApp(home: DashboardShell()),
  );
}

void main() {
  group('NotificationPermissionBanner on the dashboard home tab', () {
    testWidgets('is hidden when OS permission is granted', (tester) async {
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('allow_notifications_banner_button')),
        findsNothing,
      );
      expect(find.textContaining('Enable weather alerts'), findsNothing);
    });

    testWidgets('is hidden when the master switch is off', (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.denied,
      );
      final preferences = InMemoryPreferences();
      await preferences.write(NotificationPreferences.enabledKey, 'false');
      await tester.pumpWidget(
        _shell(notifications: service, preferences: preferences),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('allow_notifications_banner_button')),
        findsNothing,
      );
    });

    testWidgets('offers Allow + Not now when permission is denied',
        (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.denied,
      );
      await tester.pumpWidget(_shell(notifications: service));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enable weather alerts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('allow_notifications_banner_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dismiss_notifications_banner_button')),
        findsOneWidget,
      );
    });

    testWidgets('Allow grants permission and the banner disappears',
        (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.denied,
      )
        ..grantOnRequest = true;
      await tester.pumpWidget(_shell(notifications: service));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('allow_notifications_banner_button')),
      );
      await tester.pumpAndSettle();

      expect(service.requestPermissionCalled, isTrue);
      expect(find.textContaining('Enable weather alerts'), findsNothing);
    });

    testWidgets('Not now dismisses and persists the dismissal', (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.denied,
      );
      final preferences = InMemoryPreferences();
      await tester.pumpWidget(
        _shell(notifications: service, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dismiss_notifications_banner_button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Enable weather alerts'), findsNothing);
      expect(
        await preferences.read(NotificationPreferences.promptDismissedKey),
        'true',
      );
    });

    testWidgets('permanently denied routes to system settings', (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.permanentlyDenied,
      );
      await tester.pumpWidget(_shell(notifications: service));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('open_system_settings_banner_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('allow_notifications_banner_button')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('open_system_settings_banner_button')),
      );
      await tester.pumpAndSettle();
      expect(service.openSystemSettingsCalled, isTrue);
    });
  });
}