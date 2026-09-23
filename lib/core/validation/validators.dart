/// Validators + password strength estimation, shared across features.
///
/// These are pure, deterministic functions returning a user-facing error
/// message (or null when valid). They never touch services or I/O.
abstract final class Validators {
  Validators._();

  static final RegExp _emailPattern = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _usernamePattern = RegExp(r'^[A-Za-z0-9_.\-]+$');

  static const int minimumPasswordLength = 8;

  /// Basic account display name.
  static String? name(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter your name.';
    if (trimmed.length < 2) return 'Name is too short.';
    if (trimmed.length > 60) return 'Name is too long.';
    return null;
  }

  /// Account username used at registration.
  static String? username(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter a username.';
    if (trimmed.length < 3) return 'Username must be at least 3 characters.';
    if (trimmed.length > 30) return 'Username must be 30 characters or fewer.';
    if (!_usernamePattern.hasMatch(trimmed)) {
      return 'Use letters, numbers, underscores, dots or hyphens.';
    }
    return null;
  }

  /// Email address.
  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter your email address.';
    if (!_emailPattern.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Password used for logging in (must simply be present).
  static String? passwordRequired(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password.';
    return null;
  }

  /// Password strength rule for registration:
  /// minimum length, at least one letter and one number.
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password.';
    }
    if (value.length < minimumPasswordLength) {
      return 'Password must be at least $minimumPasswordLength characters.';
    }
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasNumber = value.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasNumber) {
      return 'Use at least one letter and one number.';
    }
    return null;
  }

  /// Password confirmation must match the chosen password.
  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password.';
    }
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  /// Coarse password strength used for the visual strength meter.
  /// Returns a 0..5 score so callers can render their own labels.
  static int strengthScore(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (value.contains(RegExp(r'[A-Z]'))) score++;
    if (value.contains(RegExp(r'[0-9]'))) score++;
    if (value.contains(RegExp(r'[^A-Za-z0-9]'))) score++;
    return score.clamp(0, 5);
  }
}

/// Qualitative strength bucket derived from [Validators.strengthScore].
enum PasswordStrength { weak, fair, strong }

extension PasswordStrengthX on PasswordStrength {
  String get label => switch (this) {
    PasswordStrength.weak => 'Weak',
    PasswordStrength.fair => 'Fair',
    PasswordStrength.strong => 'Strong',
  };

  static PasswordStrength fromScore(int score) {
    if (score >= 4) return PasswordStrength.strong;
    if (score >= 2) return PasswordStrength.fair;
    return PasswordStrength.weak;
  }
}
