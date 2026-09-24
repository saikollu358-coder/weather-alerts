import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/services/firebase/local_auth_service.dart';

void main() {
  group('LocalAuthService', () {
    test('is never cloud-available', () {
      expect(LocalAuthService().isAvailable, isFalse);
    });

    test('has no signed-in user until the local guest is activated',
        () async {
      final service = LocalAuthService();

      expect(service.currentUser, isNull);

      final states = <AuthUser?>[];
      await for (final user in service.watchAuthState().take(1)) {
        states.add(user);
      }
      expect(states, [null]);

      service.startLocalGuest();
      expect(service.currentUser, isNotNull);
      expect(service.currentUser!.isLocalGuest, isTrue);
      expect(service.currentUser!.uid, LocalAuthService.guest.uid);
    });

    test('emits the local guest to existing listeners when activated',
        () async {
      final service = LocalAuthService();
      final events = <AuthUser?>[];
      final subscription = service.watchAuthState().listen(events.add);
      await Future<void>.delayed(Duration.zero);

      expect(events, [null]);

      service.startLocalGuest();
      await Future<void>.delayed(Duration.zero);

      expect(events.last, LocalAuthService.guest);
      await subscription.cancel();
    });

    test('startLocalGuest is idempotent', () {
      final service = LocalAuthService();
      service.startLocalGuest();
      final first = service.currentUser;
      service.startLocalGuest();
      expect(service.currentUser, same(first));
    });

    test('login and register fail with a friendly cloud-required error', () {
      final service = LocalAuthService();

      expect(
        () => service.login(email: 'a@example.com', password: 'x'),
        throwsA(isA<FirebaseUnavailableException>()),
      );
      expect(
        () => service.register(
          username: 'a',
          email: 'a@example.com',
          password: 'x',
        ),
        throwsA(isA<FirebaseUnavailableException>()),
      );
    });

    test('logout keeps the local guest session', () async {
      final service = LocalAuthService()..startLocalGuest();
      await service.logout();
      expect(service.currentUser, isNotNull);
    });
  });
}