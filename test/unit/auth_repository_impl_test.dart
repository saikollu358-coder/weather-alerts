import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/auth_repository_impl.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';

import '../helpers/fakes.dart';

void main() {
  final logger = AppLogger(enabled: false);
  const user = AuthUser(uid: 'u1', name: 'Old', email: 'e@x.com');

  group('AuthRepositoryImpl.updateProfile', () {
    test(
      'persists the display name into the Firestore profile document',
      () async {
        final auth = FakeAuthService(user: user);
        final store = InMemoryCloudDataStore();
        final repository = AuthRepositoryImpl(
          authService: auth,
          firestore: store,
          logger: logger,
        );

        final updated = await repository.updateProfile(name: ' New Name ');

        expect(updated.name, 'New Name');
        expect(auth.lastUpdatedName, 'New Name');
        final doc = store.docs('u1', 'profile')['default'];
        expect(doc, isNotNull);
        expect(doc!['username'], 'New Name');
        expect(doc['updated_at'], isA<String>());
      },
    );

    test(
      'does not touch the store when the auth backend is local-only',
      () async {
        final auth = FakeAuthService(available: false, user: user);
        final store = InMemoryCloudDataStore();
        final repository = AuthRepositoryImpl(
          authService: auth,
          firestore: store,
          logger: logger,
        );

        final updated = await repository.updateProfile(name: 'New Name');

        expect(updated.name, 'New Name');
        expect(store.docs('u1', 'profile'), isEmpty);
      },
    );

    test(
      'swallows store failures and still returns the updated identity',
      () async {
        final auth = FakeAuthService(user: user);
        final store = InMemoryCloudDataStore()..failNextWrite = true;
        final repository = AuthRepositoryImpl(
          authService: auth,
          firestore: store,
          logger: logger,
        );

        final updated = await repository.updateProfile(name: 'New Name');

        expect(updated.name, 'New Name');
        expect(auth.updateCalls, 1);
      },
    );
  });
}
