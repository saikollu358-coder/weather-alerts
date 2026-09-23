/// Base exception for all application errors.
///
/// Messages surfaced to the user must come from [message] and must never
/// contain internal technical details, secrets, API keys or stack traces.
abstract class AppException implements Exception {
  const AppException({required this.message, this.cause});

  /// User-safe, human readable description of the failure.
  final String message;

  /// Underlying cause (if any). Never logged verbatim if it may hold secrets.
  final Object? cause;

  @override
  String toString() => message;
}

/// Raised when a Firebase-backed feature is requested but the Firebase
/// configuration is absent or initialization failed (the supported
/// degraded/offline mode).
class FirebaseUnavailableException extends AppException {
  const FirebaseUnavailableException()
      : super(message: 'Cloud services are not available in this build.');

  const FirebaseUnavailableException.withMessage(String message)
      : super(message: message);
}

/// Raised when a Firebase operation fails (permission, rules, offline, etc.).
class FirebaseOperationException extends AppException {
  const FirebaseOperationException({required this.code, required super.message, super.cause});

  /// Firebase/PlatformException code, e.g. `permission-denied`.
  final String code;
}

/// Raised for network level failures (timeout, connectivity loss).
class NetworkException extends AppException {
  const NetworkException({
    super.message = 'Network connection unavailable.',
    super.cause,
  });
}

/// Raised when a local persistence (SQLite) operation fails.
class CacheException extends AppException {
  const CacheException({
    super.message = 'Could not read local data.',
    super.cause,
  });
}