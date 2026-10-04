import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/domain/entities/device_token_record.dart';
import 'package:weather_alerts/domain/repositories/device_token_repository.dart';
import 'package:weather_alerts/domain/services/auth_service.dart';
import 'package:weather_alerts/services/firebase/device_token_service.dart';
import 'package:weather_alerts/services/firebase/fcm_service.dart';
import 'package:weather_alerts/services/firebase/local_auth_service.dart';

import '../helpers/pipeline_fakes.dart';

class _MockFcmService extends Mock implements FcmService {}

/// Controllable [AuthService] so tests can drive sign-in / sign-out events
/// through [DeviceTokenService]'s auth listener.
class _FakeAuthService implements AuthService {
  _FakeAuthService({this.user}) {
    if (user != null) emitNull(user!);
  }

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  AuthUser? user;

  void emitNull(AuthUser? next) {
    user = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();

  @override
  bool get isAvailable => true;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> watchAuthState() => _controller.stream;

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    throw StateError('not used');
  }

  @override
  Future<void> logout() async => emitNull(null);

  @override
  Future<AuthUser> updateProfile({required String name}) async {
    throw StateError('not used');
  }

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async {
    throw StateError('not used');
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}
}

const _userA = AuthUser(uid: 'user-a', email: 'a@example.com');

class _InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final List<DeviceTokenRecord> records = [];

  @override
  Future<void> registerToken(DeviceTokenRecord record) async {
    final index = records.indexWhere((r) => r.deviceId == record.deviceId);
    if (index < 0) {
      records.add(record);
    } else {
      records[index] = record;
    }
  }

  @override
  Future<void> updateLocations({
    required String uid,
    required String deviceId,
    required List<String> locationKeys,
  }) async {
    final index = records.indexWhere((r) => r.deviceId == deviceId);
    if (index >= 0) {
      records[index] = records[index].copyWith(locationKeys: locationKeys);
    }
  }

  @override
  Future<void> removeToken({
    required String uid,
    required String deviceId,
  }) async {
    records.removeWhere((r) => r.deviceId == deviceId);
  }

  @override
  Future<void> removeAllTokens({required String uid}) async {
    records.clear();
  }

  @override
  Future<List<DeviceTokenRecord>> tokensForUser(String uid) async {
    return records.where((r) => r.uid == uid).toList();
  }
}

void main() {
  final logger = AppLogger(enabled: false);

  group('DeviceTokenService', () {
    late _MockFcmService fcm;
    late _InMemoryDeviceTokenRepository repo;
    late InMemoryCurrentLocation currentLocation;
    late InMemoryPreferences preferences;

    DeviceTokenService buildService() {
      // The local guest must be explicitly activated (startLocalGuest) before
      // the offline session counts as "signed in".
      final localAuth = LocalAuthService()..startLocalGuest();
      return DeviceTokenService(
        fcm: fcm,
        auth: localAuth,
        deviceTokens: repo,
        currentLocation: currentLocation,
        preferences: preferences,
        logger: logger,
      );
    }

    setUp(() {
      fcm = _MockFcmService();
      repo = _InMemoryDeviceTokenRepository();
      currentLocation = InMemoryCurrentLocation(
        seed: sampleCurrentLocation(label: 'Home'),
      );
      preferences = InMemoryPreferences();
    });

    test('is a no-op when FCM is unavailable', () async {
      when(() => fcm.isAvailable).thenReturn(false);

      await buildService().initialize();

      expect(repo.records, isEmpty);
      verifyNever(() => fcm.getToken());
    });

    test(
      'registers a token with monitored location keys when signed in',
      () async {
        when(() => fcm.isAvailable).thenReturn(true);
        when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
        when(
          () => fcm.onTokenRefresh(),
        ).thenAnswer((_) => const Stream<String>.empty());

        await buildService().initialize();

        expect(repo.records, hasLength(1));
        final record = repo.records.single;
        expect(record.token, 'token-abc');
        expect(record.uid, LocalAuthService.guest.uid);
        expect(record.locationKeys, contains('1.0,2.0'));
        expect(record.platform, isNotEmpty);
        // Device id is generated and persisted across calls.
        final persisted = await preferences.read('device_id');
        expect(persisted, isNotEmpty);
        expect(record.deviceId, persisted);
      },
    );

    test('registers the same device id across consecutive calls', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());

      await buildService().initialize();
      final first = repo.records.single.deviceId;

      await buildService().initialize();

      expect(repo.records.single.deviceId, first);
      // Same device id -> upsert, not duplicate.
      expect(repo.records.length, 1);
    });

    test('skips registration when the FCM token is unavailable', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => null);
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());

      await buildService().initialize();

      expect(repo.records, isEmpty);
    });

    test('refreshes the token when FCM rotates it', () async {
      final refreshController = StreamController<String>();
      var currentToken = 'token-old';
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => currentToken);
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => refreshController.stream);

      final service = buildService();
      await service.initialize();
      expect(repo.records.single.token, 'token-old');

      // Mimic FCM rotating its stored token before notifying.
      currentToken = 'token-new';
      refreshController.add('token-new');
      await pumpUntil(() => repo.records.single.token == 'token-new');

      expect(repo.records.single.token, 'token-new');
      expect(repo.records.length, 1);
      await refreshController.close();
    });

    test(
      'syncCurrentLocation replaces the key with the newest position',
      () async {
        when(() => fcm.isAvailable).thenReturn(true);
        when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
        when(
          () => fcm.onTokenRefresh(),
        ).thenAnswer((_) => const Stream<String>.empty());

        final service = buildService();
        await service.initialize();
        expect(repo.records.single.locationKeys, ['1.0,2.0']);

        await currentLocation.save(
          sampleCurrentLocation(latitude: 3.0, longitude: 4.0, label: 'Work'),
        );
        await service.syncCurrentLocation();

        expect(repo.records.single.locationKeys, ['3.0,4.0']);
      },
    );

    test('advertises no key until a position has been captured', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());
      currentLocation = InMemoryCurrentLocation();

      await buildService().initialize();

      expect(repo.records.single.locationKeys, isEmpty);
    });

    test('removeCurrentDevice deletes the device document', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());

      final service = buildService();
      await service.initialize();
      expect(repo.records, isNotEmpty);

      await service.removeCurrentDevice();

      expect(repo.records, isEmpty);
    });

    test('registers the token when a user signs in after start', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());
      final auth = _FakeAuthService();
      final service = DeviceTokenService(
        fcm: fcm,
        auth: auth,
        deviceTokens: repo,
        currentLocation: currentLocation,
        preferences: preferences,
        logger: logger,
      );

      await service.initialize();
      expect(repo.records, isEmpty);

      auth.emitNull(_userA);
      await pumpUntil(
        () => repo.records.isNotEmpty && repo.records.first.uid == 'user-a',
      );

      expect(repo.records.single.uid, 'user-a');
      await auth.dispose();
    });

    test('removes the device document when the user signs out', () async {
      when(() => fcm.isAvailable).thenReturn(true);
      when(() => fcm.getToken()).thenAnswer((_) async => 'token-abc');
      when(
        () => fcm.onTokenRefresh(),
      ).thenAnswer((_) => const Stream<String>.empty());
      final auth = _FakeAuthService(user: _userA);
      final service = DeviceTokenService(
        fcm: fcm,
        auth: auth,
        deviceTokens: repo,
        currentLocation: currentLocation,
        preferences: preferences,
        logger: logger,
      );
      addTearDown(auth.dispose);

      await service.initialize();
      expect(repo.records.single.uid, 'user-a');

      auth.emitNull(null);
      await pumpUntil(() => repo.records.isEmpty);

      expect(repo.records, isEmpty);
    });
  });
}
