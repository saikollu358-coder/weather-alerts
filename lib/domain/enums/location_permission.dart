/// Application-level location permission state, mapping the platform's
/// fine-grained states (while-in-use/always/unable-to-determine) to the
/// three cases the UI needs to branch on.
enum LocationPermissionStatus {
  /// The user has not granted location access (denied or undetermined).
  denied,

  /// The user denied access permanently; only system settings can re-grant it.
  deniedForever,

  /// Location access is granted.
  granted,
}