/// An authenticated identity used across the application.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.name,
    this.email,
    this.createdAt,
    this.isLocalGuest = false,
  });

  /// Firebase UID (or the deterministic local session id).
  final String uid;

  /// Display name, when known.
  final String? name;

  /// Primary email address, when known.
  final String? email;

  /// Account creation time, when known.
  final DateTime? createdAt;

  /// True for the offline/local session used when Firebase is not configured.
  /// Local guests have no cloud account and no server-side data.
  final bool isLocalGuest;

  String get displayName => name ?? (email ?? 'Local profile');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          other.uid == uid &&
          other.name == name &&
          other.email == email &&
          other.isLocalGuest == isLocalGuest;

  @override
  int get hashCode => Object.hash(uid, name, email, isLocalGuest);

  @override
  String toString() => 'AuthUser(uid: $uid, email: $email)';
}