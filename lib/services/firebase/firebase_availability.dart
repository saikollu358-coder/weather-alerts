/// Thinnest possible contract that decides whether Firebase services may be
/// used in the current runtime.
///
/// Kept as a separate interface so FirestoreService / FcmService (and the Cloud
/// Functions bridge) can be unit tested against a fake availability without a
/// real Firebase app, and so the whole Firebase dependency can be swapped or
/// disabled at build time.
abstract interface class FirebaseAvailability {
  /// True once Firebase initialized successfully in this session.
  bool get isAvailable;
}

/// Marker mixin for services that depend on Firebase at runtime.
mixin FirebaseDependent {
  /// The availability flag driving whether this service may operate.
  FirebaseAvailability get firebase;
}