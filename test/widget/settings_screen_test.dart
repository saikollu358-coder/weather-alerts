import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:weather_alerts/core/constants/app_constants.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/enums/notification_permission.dart';
import 'package:weather_alerts/features/dashboard/presentation/dashboard_shell.dart';
import 'package:weather_alerts/features/notifications/application/notification_preferences.dart';
import 'package:weather_alerts/features/settings/presentation/settings_screen.dart';
import 'package:weather_alerts/routing/app_routes.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

import '../helpers/pipeline_fakes.dart';

Widget wrapSettings({
  FakeNotificationService? notifications,
  InMemoryPreferences? preferences,
}) {
  return ProviderScope(
    overrides: [
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
      preferenceRepositoryProvider.overrideWithValue(
        preferences ?? InMemoryPreferences(),
      ),
      notificationServiceProvider.overrideWithValue(
        notifications ?? FakeNotificationService(),
      ),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('renders the notifications switch and about section',
        (tester) async {
      await tester.pumpWidget(wrapSettings());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Weather risk alerts'), findsOneWidget);
      expect(find.byKey(const ValueKey('notifications_switch')), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text(AppConstants.tagline), findsOneWidget);
      expect(find.textContaining('assessment'), findsWidgets);
    });

    testWidgets('switch reflects the persisted preference and persists a change',
        (tester) async {
      final preferences = InMemoryPreferences();
      await tester.pumpWidget(
        wrapSettings(preferences: preferences),
      );
      await tester.pumpAndSettle();

      SwitchListTile switchTile() => tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('notifications_switch')));
      expect(switchTile().value, isTrue);

      await tester.tap(find.byKey(const ValueKey('notifications_switch')));
      await tester.pumpAndSettle();

      expect(switchTile().value, isFalse);
      expect(
        await preferences.read(NotificationPreferences.enabledKey),
        'false',
      );
    });

    testWidgets('denied permission offers allow + app-settings actions',
        (tester) async {
      final service =
          FakeNotificationService(permission: NotificationPermissionStatus.denied);
      await tester.pumpWidget(wrapSettings(notifications: service));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('allow_notifications_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('open_system_settings_button_denied')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('open_system_settings_button_denied')));
      await tester.pumpAndSettle();
      expect(service.openSystemSettingsCalled, isTrue);
    });

    testWidgets('allowing notifications flips the panel to active',
        (tester) async {
      final service = FakeNotificationService(permission: NotificationPermissionStatus.denied)
        ..grantOnRequest = true;
      await tester.pumpWidget(wrapSettings(notifications: service));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('allow_notifications_button')));
      await tester.pumpAndSettle();

      expect(service.requestPermissionCalled, isTrue);
      expect(find.text('Notifications are active'), findsOneWidget);
    });

    testWidgets('permanently denied hides allow and routes to system settings',
        (tester) async {
      final service = FakeNotificationService(
        permission: NotificationPermissionStatus.permanentlyDenied,
      );
      await tester.pumpWidget(wrapSettings(notifications: service));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('allow_notifications_button')), findsNothing);
      expect(
        find.byKey(const ValueKey('open_system_settings_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('open_system_settings_button')));
      await tester.pumpAndSettle();
      expect(service.openSystemSettingsCalled, isTrue);
    });

    testWidgets('granted permission shows the active panel', (tester) async {
      await tester.pumpWidget(wrapSettings());
      await tester.pumpAndSettle();

      expect(find.text('Notifications are active'), findsOneWidget);
    });
  });

  group('Settings entry point', () {
    testWidgets('the dashboard app bar opens the settings screen',
        (tester) async {
      final router = GoRouter(
        initialLocation: RoutePath.home,
        routes: [
          GoRoute(
            path: RoutePath.home,
            name: RouteName.home,
            builder: (_, _) => const DashboardShell(),
          ),
          GoRoute(
            path: RoutePath.settings,
            name: RouteName.settings,
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
            preferenceRepositoryProvider.overrideWithValue(
              InMemoryPreferences(),
            ),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            currentLocationRepositoryProvider.overrideWithValue(
              InMemoryCurrentLocation(),
            ),
            alertHistoryRepositoryProvider.overrideWithValue(
              InMemoryAlertHistory(),
            ),
            weatherServiceProvider.overrideWithValue(FakeWeatherService()),
            locationServiceProvider.overrideWithValue(FakeLocationService()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final settingsButton = find.byKey(const ValueKey('settings_button'));
      expect(settingsButton, findsOneWidget);

      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.text('Weather risk alerts'), findsOneWidget);
    });
  });
}