import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:weather_alerts/core/errors/auth_exception.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/features/profile/presentation/profile_screen.dart';

import '../helpers/fakes.dart';

const _cloudUser = AuthUser(uid: 'u1', name: 'Alice', email: 'alice@example.com');
const _guest = AuthUser(
  uid: 'local-guest',
  name: 'Local profile',
  isLocalGuest: true,
);

void main() {
  Future<void> pumpProfile(
    WidgetTester tester,
    FakeAuthRepository auth, {
    bool emitUser = true,
  }) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              const Scaffold(body: Text('Settings screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (emitUser) {
      auth.emit(auth.currentUser);
      await tester.pumpAndSettle();
    }
  }

  group('ProfileScreen', () {
    testWidgets('shows the cloud identity and an edit affordance',
        (tester) async {
      final auth = FakeAuthRepository(user: _cloudUser);
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('Cloud account'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit_profile_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('open_settings_row')), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('local guest has no edit affordance or sign out',
        (tester) async {
      final auth = FakeAuthRepository(user: _guest);
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      expect(find.text('Local profile'), findsWidgets);
      expect(find.textContaining('local-only mode'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit_profile_button')), findsNothing);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('editing the name updates the displayed identity',
        (tester) async {
      final auth = FakeAuthRepository(user: _cloudUser);
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      await tester.tap(find.byKey(const ValueKey('edit_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Edit profile'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('profile_name_field')),
        'Alice Cooper',
      );
      await tester.tap(find.byKey(const ValueKey('save_profile_button')));
      await tester.pumpAndSettle();

      expect(auth.currentUser?.name, 'Alice Cooper');
      expect(find.text('Alice Cooper'), findsOneWidget);
      expect(find.text('Profile updated'), findsOneWidget);
    });

    testWidgets('validation blocks an empty name', (tester) async {
      final auth = FakeAuthRepository(user: _cloudUser);
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      await tester.tap(find.byKey(const ValueKey('edit_profile_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('profile_name_field')),
        '   ',
      );
      await tester.tap(find.byKey(const ValueKey('save_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your name.'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile_name_field')), findsOneWidget);
      expect(auth.currentUser?.name, 'Alice');
    });

    testWidgets('a failed update shows the message and keeps the old name',
        (tester) async {
      final auth = FakeAuthRepository(
        user: _cloudUser,
      )..updateProfileError = const AuthException(
          code: 'test',
          message: 'Could not update your profile.',
        );
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      await tester.tap(find.byKey(const ValueKey('edit_profile_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('profile_name_field')),
        'Alice Cooper',
      );
      await tester.tap(find.byKey(const ValueKey('save_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Could not update your profile.'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('the settings row navigates to the settings screen',
        (tester) async {
      final auth = FakeAuthRepository(user: _cloudUser);
      addTearDown(auth.dispose);
      await pumpProfile(tester, auth);

      await tester.tap(find.byKey(const ValueKey('open_settings_row')));
      await tester.pumpAndSettle();

      expect(find.text('Settings screen'), findsOneWidget);
    });
  });
}