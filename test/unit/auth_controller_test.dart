import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/auth_exception.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/features/authentication/application/auth_providers.dart';
import 'package:weather_alerts/features/authentication/application/auth_state.dart';

import '../helpers/fakes.dart';

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  ProviderContainer makeContainer(FakeAuthRepository auth) {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWith((ref) => auth)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AuthController', () {
    test('starts unknown then resolves to unauthenticated', () async {
      final auth = FakeAuthRepository();
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      expect(container.read(authControllerProvider), isA<AuthState>());
      expect(container.read(authControllerProvider).status, AuthStatus.unknown);

      container.read(authControllerProvider);
      auth.emit(null);
      await _flush();

      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    });

    test('resolves to authenticated when a user is emitted', () async {
      final auth = FakeAuthRepository(
        user: const AuthUser(uid: 'u1', email: 'e@x.com'),
      );
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      // Subscribe first, then emit (broadcast controllers do not buffer).
      container.read(authControllerProvider);
      auth.emit(const AuthUser(uid: 'u1', email: 'e@x.com'));
      await _flush();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.uid, 'u1');
    });

    test('login success transitions to authenticated', () async {
      final auth = FakeAuthRepository(
        user: const AuthUser(uid: 'u1', email: 'e@x.com'),
      );
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      final ok = await container
          .read(authControllerProvider.notifier)
          .login(email: 'e@x.com', password: 'Secret123');

      expect(ok, isTrue);
      await _flush();
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    test('login failure sets a user-safe error message', () async {
      final auth = FakeAuthRepository(
        loginError: const AuthException(
          code: 'wrong-password',
          message: 'Incorrect password.',
        ),
      );
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      final ok = await container
          .read(authControllerProvider.notifier)
          .login(email: 'e@x.com', password: 'wrong');

      expect(ok, isFalse);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, 'Incorrect password.');
    });

    test('register failure surfaces friendly message', () async {
      final auth = FakeAuthRepository(
        registerError: const AuthException(
          code: 'email-already-in-use',
          message: 'An account with this email already exists.',
        ),
      );
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      final ok = await container
          .read(authControllerProvider.notifier)
          .register(username: 'Test', email: 'e@x.com', password: 'Secret123');

      expect(ok, isFalse);
      expect(
        container.read(authControllerProvider).errorMessage,
        'An account with this email already exists.',
      );
    });

    test('non-AppException failures collapse to a generic message', () async {
      final auth = FakeAuthRepository(
        loginError: StateError('boom at runtime'),
      );
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      final ok = await container
          .read(authControllerProvider.notifier)
          .login(email: 'e@x.com', password: 'x');

      expect(ok, isFalse);
      expect(
        container.read(authControllerProvider).errorMessage,
        'An unexpected problem occurred. Please try again.',
      );
    });
  });

  group('AuthController.updateProfile', () {
    const user = AuthUser(uid: 'u1', name: 'Old', email: 'e@x.com');

    test('updates the signed-in user name on success', () async {
      final auth = FakeAuthRepository(user: user);
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      container.read(authControllerProvider);
      auth.emit(user);
      await _flush();
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      final message = await container
          .read(authControllerProvider.notifier)
          .updateProfile(name: ' New Name ');

      expect(message, isNull);
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.name, 'New Name');
      expect(state.user?.uid, user.uid);
    });

    test(
      'keeps the session authenticated and returns the message on failure',
      () async {
        final auth = FakeAuthRepository(user: user)
          ..updateProfileError = const AuthException(
            code: 'test',
            message: 'Could not update your profile.',
          );
        final container = makeContainer(auth);
        addTearDown(auth.dispose);

        container.read(authControllerProvider);
        auth.emit(user);
        await _flush();

        final message = await container
            .read(authControllerProvider.notifier)
            .updateProfile(name: 'New Name');

        expect(message, 'Could not update your profile.');
        final state = container.read(authControllerProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.name, 'Old');
      },
    );

    test('collapses unexpected failures to a generic message', () async {
      final auth = FakeAuthRepository(user: user)
        ..updateProfileError = StateError('boom at runtime');
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      container.read(authControllerProvider);
      auth.emit(user);
      await _flush();

      final message = await container
          .read(authControllerProvider.notifier)
          .updateProfile(name: 'New Name');

      expect(message, 'An unexpected problem occurred. Please try again.');
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    test('no-op without a signed-in user', () async {
      final auth = FakeAuthRepository();
      final container = makeContainer(auth);
      addTearDown(auth.dispose);

      container.read(authControllerProvider);
      auth.emit(null);
      await _flush();

      final message = await container
          .read(authControllerProvider.notifier)
          .updateProfile(name: 'New Name');

      expect(message, 'No account is signed in.');
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    });
  });
}
