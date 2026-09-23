import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/services/firebase/firebase_availability.dart';
import 'package:weather_alerts/services/firebase/firestore_service.dart';

class _FakeAvailability implements FirebaseAvailability {
  _FakeAvailability(this.available);

  final bool available;

  @override
  bool get isAvailable => available;
}

void main() {
  group('FirestoreService', () {
    group('in local-only mode', () {
      late FirestoreService service;

      setUp(() {
        service = FirestoreService(
          firebase: _FakeAvailability(false),
          logger: AppLogger(enabled: false),
        );
      });

      test('isAvailable is false', () {
        expect(service.isAvailable, isFalse);
      });

      test('getDocument throws FirebaseUnavailableException', () async {
        expect(
          () => service.getDocument(
            ownerId: 'u1',
            collection: 'prefs',
            documentId: 'd1',
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });

      test('setDocument throws FirebaseUnavailableException', () async {
        expect(
          () => service.setDocument(
            ownerId: 'u1',
            collection: 'prefs',
            documentId: 'd1',
            data: const {'a': 1},
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });

      test('deleteDocument throws FirebaseUnavailableException', () async {
        expect(
          () => service.deleteDocument(
            ownerId: 'u1',
            collection: 'prefs',
            documentId: 'd1',
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });

      test('queryDocuments throws FirebaseUnavailableException', () async {
        expect(
          () => service.queryDocuments(
            ownerId: 'u1',
            collection: 'alerts',
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });

      test('watchDocument throws FirebaseUnavailableException', () {
        expect(
          () => service.watchDocument(
            ownerId: 'u1',
            collection: 'prefs',
            documentId: 'd1',
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });

      test('watchQuery throws FirebaseUnavailableException', () {
        expect(
          () => service.watchQuery(
            ownerId: 'u1',
            collection: 'alerts',
          ),
          throwsA(isA<FirebaseUnavailableException>()),
        );
      });
    });
  });
}

