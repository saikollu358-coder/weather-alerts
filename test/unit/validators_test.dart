import 'package:flutter_test/flutter_test.dart';

import 'package:weather_alerts/core/validation/validators.dart';

void main() {
  group('Validators.name', () {
    test('accepts a normal name', () {
      expect(Validators.name('Alex Smith'), isNull);
    });

    test('rejects empty and whitespace-only names', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('   '), isNotNull);
    });

    test('rejects too-short names', () {
      expect(Validators.name('A'), isNotNull);
    });
  });

  group('Validators.username', () {
    test('accepts a normal username', () {
      expect(Validators.username('jane.doe'), isNull);
      expect(Validators.username('alex_2026'), isNull);
    });

    test('rejects empty and whitespace-only usernames', () {
      expect(Validators.username(''), isNotNull);
      expect(Validators.username('   '), isNotNull);
    });

    test('rejects too-short and too-long usernames', () {
      expect(Validators.username('ab'), isNotNull);
      expect(Validators.username('a' * 31), isNotNull);
    });

    test('rejects spaces and other invalid characters', () {
      expect(Validators.username('Jane Doe'), isNotNull);
      expect(Validators.username('jane@doe'), isNotNull);
      expect(Validators.username('jane!doe'), isNotNull);
    });
  });

  group('Validators.email', () {
    test('accepts a valid address', () {
      expect(Validators.email('user@example.com'), isNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a b@c.com'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('accepts a compliant password', () {
      expect(Validators.password('Secret123'), isNull);
    });

    test('rejects short passwords', () {
      expect(Validators.password('Ab1'), isNotNull);
    });

    test('rejects letter-only and number-only passwords', () {
      expect(Validators.password('abcdefgh'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('accepts matching passwords', () {
      expect(Validators.confirmPassword('Secret123', 'Secret123'), isNull);
    });

    test('rejects mismatches', () {
      expect(Validators.confirmPassword('Secret124', 'Secret123'), isNotNull);
    });
  });

  group('password strength', () {
    test('weak for short simple passwords', () {
      expect(Validators.strengthScore('abcd1234'), lessThan(4));
    });

    test('strong for complex passwords', () {
      expect(
        Validators.strengthScore('Str0ng!Passw0rd'),
        greaterThanOrEqualTo(4),
      );
    });

    test('score clamps between 0 and 5', () {
      expect(Validators.strengthScore(''), 0);
      expect(Validators.strengthScore('Str0ng!P@ss1Word+More!'), 5);
    });
  });
}
