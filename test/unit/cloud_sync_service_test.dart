import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/domain/entities/monitored_location_record.dart';
import 'package:weather_alerts/domain/entities/sync_state_record.dart';
import 'package:weather_alerts/domain/entities/user_preference.dart';
import 'package:weather_alerts/domain/repositories/preference_repository.dart';
import 'package:weather_alerts/domain/repositories/sync_state_repository.dart';
import 'package:weather_alerts/domain/services/auth_service.dart';
import 'package:weather_alerts/services/sync/cloud_sync_service.dart';
import 'package:weather_alerts/services/sync/sync_domain.dart';

import '../helpers/fakes.dart';
import '../helpers/pipeline_fakes.dart';

DateTime tAt(int minute) => DateTime.utc(2026, 1, 5, 8, minute);
int ms(DateTime d) => d.millisecondsSinceEpoch;

MonitoredLocationRecord loc({
  required String name,
  double latitude = 1.0,
  double longitude = 2.0,
  required DateTime updatedAtUtc,
}) {
  return MonitoredLocationRecord(
    name: name,
    latitude: latitude,
    longitude: longitude,
    isMonitored: true,
    isPrimary: true,
    createdAtUtc: updatedAtUtc,
    updatedAtUtc: updatedAtUtc,
  );
}

AlertRecord alert({
  required String fingerprint,
  AlertStatus status = AlertStatus.detected,
  required DateTime updatedAtUtc,
  bool acknowledged = false,
}) {
  return AlertRecord(
    fingerprint: fingerprint,
    hazard: 'Thunderstorm',
    severity: 'SEVERE',
    status: status,
    title: 'Thunderstorm',
    description: 'Risk of severe thunderstorms.',
    reason: 'hail',
    locationKey: '1.0,2.0',
    payload: const {'a': 1},
    detectedAtUtc: updatedAtUtc,
    updatedAtUtc: updatedAtUtc,
    acknowledged: acknowledged,
  );
}

class _FakeAuth implements AuthService {
  _FakeAuth(this.user);

  AuthUser? user;

  @override
  bool get isAvailable => true;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> watchAuthState() => const Stream.empty();

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async => user!;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> updateProfile({required String name}) async => user!;

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async => user!;

  @override
  Future<void> sendPasswordReset({required String email}) async {}
}

class _FakeCloudDataStore extends InMemoryCloudDataStore {}

class _FakeSyncState implements SyncStateRepository {
  final Map<String, SyncStateRecord> _states = {};

  @override
  Future<void> recordAttempt(String syncKey, {String? value}) async {
    final existing = _states[syncKey];
    _states[syncKey] = SyncStateRecord(
      syncKey: syncKey,
      value: value ?? existing?.value,
      lastAttemptAtUtc: DateTime.utc(2026, 1, 5, 8),
      lastSuccessAtUtc: existing?.lastSuccessAtUtc,
      status: SyncStatus.pending,
    );
  }

  @override
  Future<void> recordFailure(String syncKey, {String? value}) async {
    final existing = _states[syncKey];
    _states[syncKey] = SyncStateRecord(
      syncKey: syncKey,
      value: value ?? existing?.value,
      lastAttemptAtUtc: DateTime.utc(2026, 1, 5, 8),
      lastSuccessAtUtc: existing?.lastSuccessAtUtc,
      status: SyncStatus.failure,
    );
  }

  @override
  Future<void> recordSuccess(
    String syncKey, {
    String? value,
    DateTime? at,
  }) async {
    final atMs = (at ?? DateTime.utc(2026, 1, 5, 8)).toUtc();
    final existing = _states[syncKey];
    _states[syncKey] = SyncStateRecord(
      syncKey: syncKey,
      value: value ?? existing?.value,
      lastAttemptAtUtc: atMs,
      lastSuccessAtUtc: atMs,
      status: SyncStatus.success,
    );
  }

  @override
  Future<List<SyncStateRecord>> all() async => _states.values.toList();

  @override
  Future<SyncStateRecord?> stateFor(String syncKey) async => _states[syncKey];
}

/// Timestamp-aware [PreferenceRepository] fake so LWW times are observable.
class _TimestampPreferences implements PreferenceRepository {
  final Map<String, UserPreference> _values = {};
  int _seq = 0;

  DateTime _stamp() => DateTime.utc(2026, 1, 5, 8, _seq++);

  @override
  Future<UserPreference?> get(String key) async => _values[key];

  @override
  Future<void> write(String key, String value, {DateTime? at}) async {
    _values[key] = UserPreference(
      key: key,
      value: value,
      updatedAtUtc: at ?? _stamp(),
    );
  }

  @override
  Future<List<UserPreference>> all() async => _values.values.toList();

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key]?.value;
}

void main() {
  final logger = AppLogger(enabled: false);
  const uid = 'user-1';

  late _FakeCloudDataStore store;
  late _FakeAuth auth;
  late _FakeSyncState syncState;
  late InMemoryMonitoredLocations locations;
  late _TimestampPreferences preferences;
  late InMemoryAlertHistory alerts;

  setUp(() {
    store = _FakeCloudDataStore();
    auth = _FakeAuth(const AuthUser(uid: uid, email: 'u@example.com'));
    syncState = _FakeSyncState();
    locations = InMemoryMonitoredLocations();
    preferences = _TimestampPreferences();
    alerts = InMemoryAlertHistory();
  });

  CloudSyncService buildService() => CloudSyncService(
    store: store,
    auth: auth,
    locations: locations,
    preferences: preferences,
    alerts: alerts,
    syncState: syncState,
    logger: logger,
  );

  group('CloudSyncService locations', () {
    test(
      'uploads a local location with a stable location_key document id',
      () async {
        locations = InMemoryMonitoredLocations(
          seed: [loc(name: 'Home', updatedAtUtc: tAt(1))],
        );
        final service = buildService();

        final result = await service.syncDomain(SyncDomain.locations);

        expect(result.uploaded, 1);
        final doc = store.docs(uid, 'locations')['1.0,2.0'];
        expect(doc, isNotNull);
        expect(doc!['name'], 'Home');
        expect(doc['updatedAtUtc'], ms(tAt(1)));
        expect(await syncState.stateFor('locations'), isNotNull);
        expect(
          (await syncState.stateFor('locations'))!.status,
          SyncStatus.success,
        );
      },
    );

    test('applies a newer remote location into local storage', () async {
      locations = InMemoryMonitoredLocations(
        seed: [
          loc(
            name: 'Stale',
            latitude: 2.0,
            longitude: 3.0,
            updatedAtUtc: tAt(1),
          ),
        ],
      );
      store.docs(uid, 'locations')['2.0,3.0'] = {
        'name': 'Work',
        'latitude': 2.0,
        'longitude': 3.0,
        'source': 'manual',
        'isMonitored': true,
        'isPrimary': false,
        'createdAtUtc': ms(tAt(1)),
        'updatedAtUtc': ms(tAt(30)),
      };
      final service = buildService();

      final result = await service.syncDomain(SyncDomain.locations);

      expect(result.appliedLocal, 1);
      final updated = await locations.allLocations();
      expect(updated.single.name, 'Work');
      expect(updated.single.updatedAtUtc, tAt(30));
    });

    test('propagates a local deletion to the remote copy', () async {
      locations = InMemoryMonitoredLocations(
        seed: [loc(name: 'Home', updatedAtUtc: tAt(1))],
      );
      final service = buildService();
      final first = await service.syncDomain(SyncDomain.locations);
      expect(first.uploaded, 1);
      expect(store.docs(uid, 'locations'), contains('1.0,2.0'));

      await locations.removeLocation(
        (await locations.allLocations()).single.id!,
      );
      final second = await service.syncDomain(SyncDomain.locations);

      expect(second.deletedRemote, 1);
      expect(store.docs(uid, 'locations'), isEmpty);
    });

    test('propagates a remote deletion into local storage', () async {
      locations = InMemoryMonitoredLocations(
        seed: [loc(name: 'Home', updatedAtUtc: tAt(1))],
      );
      final service = buildService();
      await service.syncDomain(SyncDomain.locations);
      store.docs(uid, 'locations').remove('1.0,2.0');

      final second = await service.syncDomain(SyncDomain.locations);

      expect(second.deletedLocal, 1);
      expect(await locations.allLocations(), isEmpty);
    });
  });

  group('CloudSyncService preferences', () {
    test('uploads only whitelisted preference keys', () async {
      await preferences.write('notifications_enabled', 'true', at: tAt(1));
      await preferences.write('device_id', 'secret-token', at: tAt(1));
      final service = buildService();

      final result = await service.syncDomain(SyncDomain.preferences);

      expect(result.uploaded, 1);
      final docs = store.docs(uid, 'preferences');
      expect(docs.keys, ['notifications_enabled']);
      expect(docs['notifications_enabled']!['value'], 'true');
    });

    test('applies a newer remote preference value', () async {
      await preferences.write('notifications_enabled', 'false', at: tAt(1));
      store.docs(uid, 'preferences')['notifications_enabled'] = {
        'value': 'true',
        'updatedAtUtc': ms(tAt(30)),
      };
      final service = buildService();

      await service.syncDomain(SyncDomain.preferences);

      expect(await preferences.read('notifications_enabled'), 'true');
    });

    test('propagates a local preference deletion', () async {
      await preferences.write('notifications_enabled', 'true', at: tAt(1));
      final service = buildService();
      await service.syncDomain(SyncDomain.preferences);
      expect(store.docs(uid, 'preferences'), contains('notifications_enabled'));

      await preferences.delete('notifications_enabled');
      await service.syncDomain(SyncDomain.preferences);

      expect(store.docs(uid, 'preferences'), isEmpty);
    });
  });

  group('CloudSyncService alerts', () {
    test('uploads local alert history into user_alerts', () async {
      alerts = InMemoryAlertHistory(
        seed: [alert(fingerprint: 'fp-1', updatedAtUtc: tAt(1))],
      );
      final service = buildService();

      final result = await service.syncDomain(SyncDomain.alerts);

      expect(result.uploaded, 1);
      final doc = store.docs(uid, 'user_alerts')['fp-1'];
      expect(doc, isNotNull);
      expect(doc!['fingerprint'], 'fp-1');
      expect(doc['status'], 'detected');
      expect(doc['acknowledged'], false);
    });

    test('applies a remote alert and deduplicates by fingerprint', () async {
      alerts = InMemoryAlertHistory(
        seed: [alert(fingerprint: 'fp-1', updatedAtUtc: tAt(1))],
      );
      store.docs(uid, 'user_alerts')['fp-1'] = {
        'fingerprint': 'fp-1',
        'hazard': 'Rain',
        'severity': 'MODERATE',
        'status': 'resolved',
        'title': 'Rain',
        'description': 'd',
        'reason': 'r',
        'locationKey': '1.0,2.0',
        'payload': '{}',
        'detectedAtUtc': ms(tAt(1)),
        'updatedAtUtc': ms(tAt(30)),
        'resolvedAtUtc': ms(tAt(30)),
        'acknowledged': true,
      };
      final service = buildService();

      final result = await service.syncDomain(SyncDomain.alerts);

      expect(result.appliedLocal, 1);
      expect((await alerts.alerts()).single.fingerprint, 'fp-1');
      expect((await alerts.alerts()).single.status, AlertStatus.resolved);
      expect((await alerts.alerts()).single.acknowledged, isTrue);
    });

    test('does not propagate local purge (append-only domain)', () async {
      alerts = InMemoryAlertHistory(
        seed: [alert(fingerprint: 'fp-1', updatedAtUtc: tAt(1))],
      );
      final service = buildService();
      await service.syncDomain(SyncDomain.alerts);

      await alerts.purgeOlderThan(tAt(2));
      expect(await alerts.alerts(), isEmpty);

      await service.syncDomain(SyncDomain.alerts);

      // The purged alert is re-applied from the cloud.
      expect((await alerts.alerts()).single.fingerprint, 'fp-1');
    });
  });

  group('CloudSyncService orchestration', () {
    test('a failing domain does not prevent the others from syncing', () async {
      locations = InMemoryMonitoredLocations(
        seed: [loc(name: 'Home', updatedAtUtc: tAt(1))],
      );
      alerts = InMemoryAlertHistory(
        seed: [alert(fingerprint: 'fp-1', updatedAtUtc: tAt(1))],
      );
      final service = buildService();
      store.failNextWrite = true;

      await service.syncAll();

      expect(
        (await syncState.stateFor('locations'))!.status,
        SyncStatus.failure,
      );
      expect((await syncState.stateFor('alerts'))!.status, SyncStatus.success);
      expect(store.docs(uid, 'user_alerts')['fp-1'], isNotNull);
    });

    test('is a no-op when the store is unavailable', () async {
      locations = InMemoryMonitoredLocations(
        seed: [loc(name: 'Home', updatedAtUtc: tAt(1))],
      );
      store.available = false;
      final service = buildService();

      expect(service.isSyncAvailable, isFalse);
      await service.syncAll();

      expect(store.docs(uid, 'locations'), isEmpty);
      expect(await syncState.all(), isEmpty);
    });

    test('startPeriodic is idempotent and stopPeriodic cancels', () async {
      final service = buildService();
      service.startPeriodic();
      service.startPeriodic();
      service.stopPeriodic();
      service.stopPeriodic();
    });
  });
}
