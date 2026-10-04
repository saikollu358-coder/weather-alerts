import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/app.dart';
import 'package:weather_alerts/core/constants/app_constants.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/features/authentication/application/auth_state.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

import '../helpers/fakes.dart';
import '../helpers/pipeline_fakes.dart';

void main() {
  group('App boot', () {
    testWidgets('boots into the splash screen while auth resolves',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: WeatherAlertsApp()));

      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text(AppConstants.tagline), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('redirects unauthenticated users to login', (tester) async {
      final auth = FakeAuthRepository();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((ref) => auth),
            // This test simulates a cloud-connected build: the auth backend is
            // available, so the router may show the login flow.
            authServiceProvider.overrideWithValue(
              FakeAuthService(available: true),
            ),
          ],
          child: const WeatherAlertsApp(),
        ),
      );
      auth.emit(null);
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byKey(const ValueKey('login_email')), findsOneWidget);
    });

    testWidgets('local-only builds show the local-mode gate, not the login page',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: WeatherAlertsApp()));
      // Drive the redirect away from the splash screen without pumpAndSettle
      // (an indeterminate splash spinner never settles by itself).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Running in local mode'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue_locally_button')),
        findsOneWidget,
      );
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('authenticated users land on the dashboard', (tester) async {
      final user = const AuthUser(uid: 'u1', email: 'u@example.com');
      final auth = FakeAuthRepository(user: user);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((ref) => auth),
            currentLocationRepositoryProvider.overrideWith(
              (ref) => InMemoryCurrentLocation(),
            ),
            alertHistoryRepositoryProvider.overrideWith(
              (ref) => InMemoryAlertHistory(),
            ),
            weatherServiceProvider.overrideWith((ref) => FakeWeatherService()),
            locationServiceProvider.overrideWith(
              (ref) =>
                  FakeLocationService(permission: LocationPermissionStatus.denied),
            ),
          ],
          child: const WeatherAlertsApp(),
        ),
      );
      auth.emit(user);
      await tester.pumpAndSettle();

      // The post-auth shell renders the home tab, which asks for location
      // access because the app has no position for this device yet.
      expect(find.text('Weather'), findsWidgets);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('allow_location_button')),
        findsOneWidget,
      );
    });

    test('AuthState helpers', () {
      expect(const AuthState.unknown().isLoading, isTrue);
      expect(
        const AuthState.authenticated(
          AuthUser(uid: 'u', email: 'e'),
        ).isAuthenticated,
        isTrue,
      );
      expect(
        const AuthState.authenticated(
          AuthUser(uid: 'local-guest', isLocalGuest: true),
        ).usesCloudAccount,
        isFalse,
      );
      expect(const AuthState.unauthenticated().isAuthenticated, isFalse);
    });
  });
}