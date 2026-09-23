import 'app_exception.dart';

/// Raised when an authentication operation fails.
///
/// [code] mirrors the underlying provider code (e.g. `wrong-password`,
/// `email-already-in-use`) so callers can branch programmatically, while
/// [message] is always user-safe and localization-ready.
class AuthException extends AppException {
  const AuthException({required this.code, required super.message, super.cause});

  final String code;
}