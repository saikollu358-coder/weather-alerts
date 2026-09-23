import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Application logger.
///
/// Rules:
///  - Logging is disabled in production builds unless explicitly enabled.
///  - Never log secrets: passwords, tokens, API keys, FCM tokens, full auth
///    payloads. Only log opaque identifiers when necessary.
///  - Never log raw user PII.
class AppLogger {
  AppLogger({required this.enabled});

  /// Whether logging produces output (disabled in production by default).
  final bool enabled;

  /// Creates a logger honoring the current [AppConfig].
  factory AppLogger.fromConfig(AppConfig config) =>
      AppLogger(enabled: config.loggingEnabled && !config.isProduction);

  void verbose(String tag, String message) => _log('V', tag, message);

  void debug(String tag, String message) => _log('D', tag, message);

  void info(String tag, String message) => _log('I', tag, message);

  void warning(String tag, String message) => _log('W', tag, message);

  void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) return;
    debugPrint('[$tag] E: $message');
    if (error != null) {
      // Deliberately coarse: class name only, to avoid leaking internals.
      debugPrint('[$tag]   cause: ${error.runtimeType}');
    }
  }

  void _log(String level, String tag, String message) {
    if (!enabled) return;
    debugPrint('[$tag] $level: $message');
  }
}

/// Provider exposing the shared [AppLogger], honors [AppConfig] logging policy.
final appLoggerProvider = Provider<AppLogger>(
  (ref) => AppLogger.fromConfig(ref.watch(appConfigProvider)),
);