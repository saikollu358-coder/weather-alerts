import '../entities/user_preference.dart';

/// Repository boundary for user preferences persisted locally (and
/// optionally synchronized with Firestore in later phases).
abstract interface class PreferenceRepository {
  /// Raw string value for [key], or null when unset.
  Future<String?> read(String key);

  /// Full preference record for [key], or null.
  Future<UserPreference?> get(String key);

  /// Stores (or overwrites) a preference value, stamping the write time.
  Future<void> write(String key, String value);

  /// Removes a preference.
  Future<void> delete(String key);

  /// All stored preferences.
  Future<List<UserPreference>> all();
}