import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/services/firebase/auth_error_mapper.dart';

void main() {
  group('AuthErrorMapper', () {
    test('maps known codes to friendly messages', () {
      expect(
        AuthErrorMapper.map(FirebaseAuthException(code: 'wrong-password')).message,
        'Incorrect password.',
      );
      expect(
        AuthErrorMapper.map(FirebaseAuthException(code: 'user-not-found')).message,
        'No account found for this email.',
      );
      expect(
        AuthErrorMapper
            .map(FirebaseAuthException(code: 'email-already-in-use'))
            .message,
        'An account with this email already exists.',
      );
      expect(
        AuthErrorMapper
            .map(FirebaseAuthException(code: 'network-request-failed'))
            .message,
        'A network problem occurred. Check your connection.',
      );
    });

    test('keeps the provider code for programmatic branching', () {
      final mapped = AuthErrorMapper.map(
        FirebaseAuthException(code: 'weak-password'),
      );
      expect(mapped.code, 'weak-password');
    });

    test('falls back to a generic message for unknown codes', () {
      final mapped = AuthErrorMapper.map(
        FirebaseAuthException(code: 'some-unknown-code'),
      );
      expect(mapped.code, 'some-unknown-code');
      expect(mapped.message, isNot(isEmpty));
    });
  });
}