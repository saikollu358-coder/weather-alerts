import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/services/firebase/firebase_availability.dart';
import 'package:weather_alerts/services/firebase/fcm_service.dart';

class _FakeAvailability implements FirebaseAvailability {
  _FakeAvailability(this.available);

  final bool available;

  @override
  bool get isAvailable => available;
}

void main() {
  group('FcmService', () {
    group('in local-only mode', () {
      late FcmService service;

      setUp(() {
        service = FcmService(
          firebase: _FakeAvailability(false),
          logger: AppLogger(enabled: false),
        );
      });

      test('isAvailable is false', () {
        expect(service.isAvailable, isFalse);
      });

      test('requestPermission returns false', () async {
        expect(await service.requestPermission(), isFalse);
      });

      test('getToken returns null', () async {
        expect(await service.getToken(), isNull);
      });

      test('getInitialMessage returns null', () async {
        expect(await service.getInitialMessage(), isNull);
      });

      test('token refresh stream is empty', () async {
        final events = await service.onTokenRefresh().toList();
        expect(events, isEmpty);
      });

      test('foreground message stream is empty', () async {
        final events = await service.onForegroundMessage().toList();
        expect(events, isEmpty);
      });

      test('opened-app stream is empty', () async {
        final events = await service.onMessageOpenedApp().toList();
        expect(events, isEmpty);
      });
    });
  });
}
