import '../entities/current_location.dart';

/// Stores the device's most recent position.
///
/// The app has no user-managed locations, but background work (scheduled
/// weather checks and push routing) cannot resolve GPS from a background
/// isolate. This repository keeps the last fix captured while the app was in
/// the foreground so those paths still have a position to act on.
abstract interface class CurrentLocationRepository {
  /// The last captured location, or null when none has been stored yet.
  Future<CurrentLocation?> read();

  /// Stores [location] as the newest known position.
  Future<void> save(CurrentLocation location);

  /// Forgets the stored position (used on sign-out).
  Future<void> clear();
}