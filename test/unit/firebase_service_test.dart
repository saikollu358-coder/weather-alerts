import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/config/app_config.dart';
import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/services/firebase/firebase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseService', () {
    test('missing configuration degrades to unavailable instead of crashing',
        () async {
      final service = FirebaseService(
        config: AppConfig.fromEnvironment(),
        logger: AppLogger(enabled: false),
      );

      await service.bootstrap();

      expect(service.isAvailable, isFalse);
    });

    test('bootstrap is idempotent', () async {
      final service = FirebaseService(
        config: AppConfig.fromEnvironment(),
        logger: AppLogger(enabled: false),
      );

      await service.bootstrap();
      await service.bootstrap();

      expect(service.isAvailable, isFalse);
    });
  });
}
