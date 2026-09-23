/// A single persisted user preference (key/value pair).
class UserPreference {
  const UserPreference({
    required this.key,
    required this.value,
    required this.updatedAtUtc,
  });

  final String key;
  final String value;

  /// Last write time (always UTC).
  final DateTime updatedAtUtc;

  @override
  String toString() => 'UserPreference($key)';
}