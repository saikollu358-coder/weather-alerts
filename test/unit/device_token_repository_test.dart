import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/data/repositories/device_token_firestore_repository.dart';
import 'package:weather_alerts/domain/entities/device_token_record.dart';
import 'package:weather_alerts/services/firebase/firestore_service.dart';

class _MockFirestoreService extends Mock implements FirestoreService {}

void main() {
  final logger = AppLogger(enabled: false);

  group('DeviceTokenFirestoreRepository', () {
    late _MockFirestoreService firestore;
    late DeviceTokenFirestoreRepository repo;

    setUp(() {
      firestore = _MockFirestoreService();
      repo = DeviceTokenFirestoreRepository(
        firestore: firestore,
        logger: logger,
      );
    });

    test('registerToken persists a token document under the user', () async {
      when(() => firestore.setDocument(
        ownerId: any(named: 'ownerId'),
        collection: any(named: 'collection'),
        documentId: any(named: 'documentId'),
        data: any(named: 'data'),
      )).thenAnswer((_) async {});

      await repo.registerToken(const DeviceTokenRecord(
        token: 'token-1',
        deviceId: 'device-1',
        uid: 'u1',
        locationKeys: ['1.0,2.0'],
        platform: 'android',
      ));

      verify(() => firestore.setDocument(
        ownerId: 'u1',
        collection: 'devices',
        documentId: 'device-1',
        data: any(named: 'data'),
      )).called(1);
    });

    test('updateLocations writes the new location keys', () async {
      when(() => firestore.setDocument(
        ownerId: any(named: 'ownerId'),
        collection: any(named: 'collection'),
        documentId: any(named: 'documentId'),
        data: any(named: 'data'),
      )).thenAnswer((_) async {});

      await repo.updateLocations(
        uid: 'u1',
        deviceId: 'device-1',
        locationKeys: const ['3.0,4.0'],
      );

      final captured = verify(() => firestore.setDocument(
        ownerId: 'u1',
        collection: 'devices',
        documentId: 'device-1',
        data: captureAny(named: 'data'),
      )).captured.single as Map<String, dynamic>;
      expect(captured['locationKeys'], const ['3.0,4.0']);
      expect(captured['updatedAtUtc'], isA<int>());
    });

    test('removeToken deletes the device document', () async {
      when(() => firestore.deleteDocument(
        ownerId: any(named: 'ownerId'),
        collection: any(named: 'collection'),
        documentId: any(named: 'documentId'),
      )).thenAnswer((_) async {});

      await repo.removeToken(uid: 'u1', deviceId: 'device-1');

      verify(() => firestore.deleteDocument(
        ownerId: 'u1',
        collection: 'devices',
        documentId: 'device-1',
      )).called(1);
    });

    test('tokensForUser maps Firestore rows into records', () async {
      when(() => firestore.queryDocuments(
        ownerId: any(named: 'ownerId'),
        collection: any(named: 'collection'),
      )).thenAnswer(
        (_) async => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
      );

      final result = await repo.tokensForUser('u1');

      expect(result, isEmpty);
      verify(() => firestore.queryDocuments(
        ownerId: 'u1',
        collection: 'devices',
      )).called(1);
    });
  });
}