import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/auth_exception.dart';

/// Maps provider error codes to safe, user-facing messages.
///
/// Unknown codes fall back to a generic message so the app never leaks raw
/// Firebase internals to the user.
abstract final class AuthErrorMapper {
  AuthErrorMapper._();

  static AuthException map(FirebaseAuthException e) {
    return AuthException(code: e.code, message: _messageFor(e.code), cause: e);
  }

  static String _messageFor(String code) => switch (code) {
        'email-already-in-use' => 'An account with this email already exists.',
        'invalid-email' => 'Enter a valid email address.',
        'invalid-credential' => 'Invalid email or password.',
        'weak-password' => 'That password is too weak to use.',
        'wrong-password' => 'Incorrect password.',
        'user-not-found' => 'No account found for this email.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' => 'A network problem occurred. Check your connection.',
        'operation-not-allowed' => 'Sign-in is not allowed for this provider.',
        'invalid-action-code' => 'That reset link is invalid or has expired. Request a new one.',
        'expired-action-code' => 'That link has expired. Request a new one.',
        _ => 'Sign-in failed. Please try again.',
      };
}