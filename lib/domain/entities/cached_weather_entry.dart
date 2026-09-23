/// A weather-observation snapshot cached locally for offline use.
///
/// Payloads are the serialized weather response from the provider (stored as
/// JSON). Consumers must treat a cached entry as *stale* once it has passed
/// its freshness window and never present it as live data.
class CachedWeatherEntry {
  const CachedWeatherEntry({
    required this.locationKey,
    required this.payload,
    required this.fetchedAtUtc,
    this.expiresAtUtc,
    required this.dataSource,
    this.dataVersion = 1,
  });

  /// Stable key identifying the monitored location (e.g. `lat,lng`).
  final String locationKey;

  /// Serialized weather payload (opaque to the storage layer).
  final Map<String, dynamic> payload;

  /// When the data was captured (always UTC).
  final DateTime fetchedAtUtc;

  /// When the entry is considered stale; null means client-defined TTL.
  final DateTime? expiresAtUtc;

  /// Provider/source of the data, e.g. `'open-meteo'`.
  final String dataSource;

  /// Cache payload format version for forward-compatible migrations.
  final int dataVersion;

  /// True once the cached value has passed its freshness window.
  bool isStale({DateTime? now}) {
    final expires = expiresAtUtc;
    if (expires == null) return false;
    return (now ?? DateTime.now()).toUtc().isAfter(expires.toUtc());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedWeatherEntry &&
          other.locationKey == locationKey &&
          other.dataSource == dataSource &&
          other.fetchedAtUtc == fetchedAtUtc &&
          other.expiresAtUtc == expiresAtUtc &&
          other.dataVersion == dataVersion;

  @override
  int get hashCode => Object.hash(
        locationKey,
        dataSource,
        fetchedAtUtc,
        expiresAtUtc,
        dataVersion,
      );

  @override
  String toString() => 'CachedWeatherEntry($locationKey, '
      'fetched: ${fetchedAtUtc.toIso8601String()}, '
      'stale: ${isStale()}, source: $dataSource)';
}