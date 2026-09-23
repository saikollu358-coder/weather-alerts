import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/features/authentication/presentation/screens/login_screen.dart';

import '../helpers/fakes.dart';

Widget _wrap(FakeAuthRepository auth) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWith((ref) => auth)],
    child: const MaterialApp(home: LoginScreen()),
  );
}

void main() {
  /// Pumps the login screen and resolves auth to unauthenticated.
  Future<void> pumpLogin(WidgetTester tester, FakeAuthRepository auth) async {
    await tester.pumpWidget(_wrap(auth));
    auth.emit(null);
    await tester.pump();
  }

  testWidgets('renders email, password and submit', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await pumpLogin(tester, auth);

    expect(find.byKey(const ValueKey('login_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_submit')), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('shows validation errors for empty fields', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await pumpLogin(tester, auth);

    await tester.tap(find.byKey(const ValueKey('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email address.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
  });

  testWidgets('login failure surfaces the error banner', (tester) async {
    final auth = FakeAuthRepository(
      loginError: StateError('nope'),
    );
    addTearDown(auth.dispose);
    await pumpLogin(tester, auth);

    await tester.enterText(
      find.byKey(const ValueKey('login_email')),
      'e@x.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login_password')),
      'secret123',
    );
    await tester.tap(find.byKey(const ValueKey('login_submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('An unexpected problem occurred. Please try again.'),
      findsOneWidget,
    );
  });
}