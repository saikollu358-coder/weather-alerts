import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import 'firebase_availability.dart';

/// Owns Firebase lifecycle for the app.
///
/// The application supports running without a Firebase backend:
///  - Android / iOS: configuration is read from the platform config files
///    (`google-services.json` / `GoogleService-Info.plist`). Absent or invalid
///    configuration degrades gracefully instead of crashing.
///  - Web: uses Dart defines supplied at build time; if absent, tries the
///    auto-injected `firebaseConfig` in `web/index.html` (flutterfire flow).
///
/// When unavailable, every Firebase-dependent service reports
/// [FirebaseUnavailableException] and the app operates in offline/local mode.
class FirebaseService implements FirebaseAvailability {
  FirebaseService({required this.config, required this.logger});

  final AppConfig config;
  final AppLogger logger;

  bool _bootstrapped = false;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  /// Attempts initialization. Never throws: failures are recorded and the app
  /// continues with Firebase disabled.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    try {
      if (kIsWeb) {
        final webOptions = config.firebaseWebOptions;
        if (webOptions != null) {
          await Firebase.initializeApp(options: webOptions);
        } else {
          await Firebase.initializeApp();
        }
      } else {
        await Firebase.initializeApp();
      }
      _available = true;
      logger.info('FirebaseService', 'Firebase initialized');
    } catch (e) {
      _available = false;
      logger.warning(
        'FirebaseService',
        'Firebase unavailable: ${e.runtimeType}. '
        'Running in local-only mode.',
      );
    }
  }
}