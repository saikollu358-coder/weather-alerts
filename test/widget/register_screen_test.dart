import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/features/authentication/presentation/screens/register_screen.dart';

import '../helpers/fakes.dart';

Widget _wrap(FakeAuthRepository auth) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWith((ref) => auth)],
    child: const MaterialApp(home: RegisterScreen()),
  );
}

void main() {
  /// Pumps the register screen and resolves auth to unauthenticated.
  Future<void> pumpRegister(
    WidgetTester tester,
    FakeAuthRepository auth,
  ) async {
    await tester.pumpWidget(_wrap(auth));
    auth.emit(null);
    await tester.pump();
  }

  /// Scrolls the submit button into view, taps it and settles.
  Future<void> tapSubmit(WidgetTester tester) async {
    final submit = find.byKey(const ValueKey('register_submit'));
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  testWidgets('renders username, email, password and submit', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await pumpRegister(tester, auth);

    expect(find.byKey(const ValueKey('register_username')), findsOneWidget);
    expect(find.byKey(const ValueKey('register_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('register_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('register_confirm')), findsNothing);
    expect(find.byKey(const ValueKey('register_submit')), findsOneWidget);
  });

  testWidgets('shows validation errors for empty fields', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await pumpRegister(tester, auth);

    await tapSubmit(tester);

    expect(find.text('Please enter a username.'), findsOneWidget);
    expect(find.text('Please enter your email address.'), findsOneWidget);
    expect(find.text('Please enter a password.'), findsOneWidget);
  });

  testWidgets('rejects a username with invalid characters', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await pumpRegister(tester, auth);

    await tester.enterText(
      find.byKey(const ValueKey('register_username')),
      'Jane Doe',
    );
    await tapSubmit(tester);

    expect(
      find.text('Use letters, numbers, underscores, dots or hyphens.'),
      findsOneWidget,
    );
  });

  testWidgets('registration failure surfaces the error banner', (tester) async {
    final auth = FakeAuthRepository(registerError: StateError('nope'));
    addTearDown(auth.dispose);
    await pumpRegister(tester, auth);

    await tester.enterText(
      find.byKey(const ValueKey('register_username')),
      'jane.doe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register_email')),
      'jane@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register_password')),
      'abc12345',
    );
    await tapSubmit(tester);

    expect(
      find.text('An unexpected problem occurred. Please try again.'),
      findsOneWidget,
    );
  });
}
