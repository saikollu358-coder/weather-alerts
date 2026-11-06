import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:weather_alerts/app.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/features/alerts/application/alert_tap_controller.dart';
import 'package:weather_alerts/features/alerts/presentation/alert_detail_screen.dart';
import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/routing/app_router.dart';
import 'package:weather_alerts/routing/app_routes.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/notifications/notification_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

import '../helpers/fakes.dart';
import '../helpers/pipeline_fakes.dart';

/// A fingerprint exactly like the one `WeatherRiskEvaluator.fingerprintFor`
/// produces: `:` and `,` inside a single path segment.
const String kFingerprint =
    'v8:Thunderstorm:42.123,-71.988:2026-09-06T12:00:00.000Z';

AlertRecord recordWith({bool acknowledged = false}) => AlertRecord(
      fingerprint: kFingerprint,
      hazard: 'Thunderstorm',
      severity: 'SEVERE',
      status: AlertStatus.escalated,
      title: 'Severe Thunderstorm',
      description: 'Lightning strikes within 10 km.',
      reason: 'Lightning strikes detected within 10 km.',
      locationKey: '42.123,-71.988',
      payload: const {'value': 4.2, 'unit': 'strikes/min'},
      detectedAtUtc: DateTime.utc(2026, 9, 6, 12),
      updatedAtUtc: DateTime.utc(2026, 9, 6, 12, 30),
      acknowledged: acknowledged,
    );

String jsonPayload(String fingerprint) =>
    '{"fingerprint":"$fingerprint","hazard":"Thunderstorm"}';

Widget _wrapDetail({
  String? fingerprint,
  InMemoryAlertHistory? history,
}) {
  return ProviderScope(
    overrides: [
      alertHistoryRepositoryProvider.overrideWithValue(
        history ?? InMemoryAlertHistory(seed: [recordWith()]),
      ),
      appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
    ],
    child: MaterialApp(
      home: AlertDetailScreen(fingerprint: fingerprint ?? kFingerprint),
    ),
  );
}

void main() {
  group('alert detail route', () {
    test('percent-encodes a fingerprint into a single path segment', () {
      final path = RoutePath.alertDetailsFor(kFingerprint);

      expect(path, startsWith('/alerts/'));
      // The raw ':' and ',' must not survive into the path, otherwise the id
      // would be ambiguous as a route parameter.
      expect(path.substring('/alerts/'.length), isNot(contains(':')));
      expect(path, isNot(contains('v8:Thunderstorm')));
    });

    testWidgets('the router decodes the encoded id back to the fingerprint',
        (tester) async {
      final router = GoRouter(
        initialLocation: RoutePath.alertDetailsFor(kFingerprint),
        routes: [
          GoRoute(
            path: RoutePath.alertDetails,
            name: RouteName.alertDetails,
            builder: (context, state) => Scaffold(
              body: Text(state.pathParameters['id'] ?? 'missing'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alertHistoryRepositoryProvider
                .overrideWithValue(InMemoryAlertHistory(seed: [recordWith()])),
            appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(kFingerprint), findsOneWidget);
    });
  });

  group('AlertDetailScreen', () {
    testWidgets('shows the record, its measurements and the disclaimer',
        (tester) async {
      await tester.pumpWidget(_wrapDetail());
      await tester.pumpAndSettle();

      expect(find.text('Severe Thunderstorm'), findsOneWidget);
      expect(find.text('Escalated'), findsWidgets);
      expect(find.text('42.123,-71.988'), findsOneWidget);
      expect(find.text('4.2 strikes/min'), findsOneWidget);
      expect(find.textContaining('does not replace official'), findsOneWidget);
    });

    testWidgets('acknowledging hides the action and persists the change',
        (tester) async {
      final history = InMemoryAlertHistory(seed: [recordWith()]);
      await tester.pumpWidget(_wrapDetail(history: history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();

      expect(find.text('Acknowledge'), findsNothing);
      expect(
        (await history.alertByFingerprint(kFingerprint))!.acknowledged,
        isTrue,
      );
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('explains an alert that is no longer stored', (tester) async {
      await tester.pumpWidget(_wrapDetail(history: InMemoryAlertHistory()));
      await tester.pumpAndSettle();

      expect(find.text('This alert is no longer available'), findsOneWidget);
      expect(find.text('Acknowledge'), findsNothing);
    });

    testWidgets('offers a retry when the lookup fails', (tester) async {
final history = InMemoryAlertHistory(seed: [recordWith()])
        ..failLookups = true;
      await tester.pumpWidget(_wrapDetail(history: history));
      await tester.pumpAndSettle();

      expect(find.text('Could not load this alert'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      history.failLookups = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Severe Thunderstorm'), findsOneWidget);
    });

    testWidgets('an empty id never renders a stale alert', (tester) async {
      await tester.pumpWidget(_wrapDetail(fingerprint: ''));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('This alert is no longer available'), findsOneWidget);
    });
  });

  group('tap navigation', () {
    testWidgets('a tapped notification opens the alert exactly once',
        (tester) async {
      final user = const AuthUser(uid: 'u1', email: 'u@example.com');
      final auth = FakeAuthRepository();
      final notifications = FakeNotificationService();
      addTearDown(auth.dispose);
      addTearDown(notifications.disposeOpenedStream);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((ref) => auth),
            currentLocationRepositoryProvider.overrideWith(
              (ref) => InMemoryCurrentLocation(),
            ),
            alertHistoryRepositoryProvider.overrideWith(
              (ref) => InMemoryAlertHistory(seed: [recordWith()]),
            ),
            weatherServiceProvider.overrideWith((ref) => FakeWeatherService()),
            locationServiceProvider.overrideWith(
              (ref) => FakeLocationService(
                permission: LocationPermissionStatus.denied,
              ),
            ),
            notificationServiceProvider.overrideWithValue(notifications),
            appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          ],
          child: const WeatherAlertsApp(),
        ),
      );
      auth.emit(user);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDetailScreen), findsNothing);

      notifications.openPayload(jsonPayload(kFingerprint));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('Severe Thunderstorm'), findsOneWidget);

      // Going back must not re-open the detail: the tap was consumed, so a
      // rebuild (or another tap for the same alert) is what drives navigation.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AlertDetailScreen)),
      );
      expect(
        container.read(alertTapControllerProvider).hasPendingTap,
        isFalse,
      );

      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDetailScreen), findsNothing);
    });

    testWidgets('a tap that arrives before the dashboard still opens the alert',
        (tester) async {
      final user = const AuthUser(uid: 'u1', email: 'u@example.com');
      final auth = FakeAuthRepository();
      final notifications = FakeNotificationService();
      addTearDown(auth.dispose);
      addTearDown(notifications.disposeOpenedStream);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((ref) => auth),
            currentLocationRepositoryProvider.overrideWith(
              (ref) => InMemoryCurrentLocation(),
            ),
            alertHistoryRepositoryProvider.overrideWith(
              (ref) => InMemoryAlertHistory(seed: [recordWith()]),
            ),
            weatherServiceProvider.overrideWith((ref) => FakeWeatherService()),
            locationServiceProvider.overrideWith(
              (ref) => FakeLocationService(
                permission: LocationPermissionStatus.denied,
              ),
            ),
            notificationServiceProvider.overrideWithValue(notifications),
            appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          ],
          child: const WeatherAlertsApp(),
        ),
      );

      // Cold start: the tap lands while the app is still resolving auth, so the
      // dashboard shell does not exist yet.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WeatherAlertsApp)),
      );
      // Attach the tap streams, then let the controller finish wiring them: a
      // broadcast event emitted before the listener exists is dropped.
      container.read(alertTapControllerProvider);
      await tester.pump();
      notifications.openPayload(jsonPayload(kFingerprint));
      await tester.pump();

      auth.emit(user);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('Severe Thunderstorm'), findsOneWidget);
    });

    testWidgets('a tap for an unknown alert still lands somewhere honest',
        (tester) async {
      final user = const AuthUser(uid: 'u1', email: 'u@example.com');
      final auth = FakeAuthRepository();
      final notifications = FakeNotificationService();
      addTearDown(auth.dispose);
      addTearDown(notifications.disposeOpenedStream);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((ref) => auth),
            currentLocationRepositoryProvider.overrideWith(
              (ref) => InMemoryCurrentLocation(),
            ),
            // Empty history: the pushed alert was never stored locally.
            alertHistoryRepositoryProvider.overrideWith(
              (ref) => InMemoryAlertHistory(),
            ),
            weatherServiceProvider.overrideWith((ref) => FakeWeatherService()),
            locationServiceProvider.overrideWith(
              (ref) => FakeLocationService(
                permission: LocationPermissionStatus.denied,
              ),
            ),
            notificationServiceProvider.overrideWithValue(notifications),
            appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
          ],
          child: const WeatherAlertsApp(),
        ),
      );
      auth.emit(user);
      await tester.pumpAndSettle();

      notifications.openPayload(jsonPayload('v8:Ice:50.0,-80.0:2026-09-06T12:00:00.000Z'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDetailScreen), findsOneWidget);
      expect(find.text('This alert is no longer available'), findsOneWidget);
    });
  });
}