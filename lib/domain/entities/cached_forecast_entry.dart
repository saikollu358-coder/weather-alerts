/// A forecast snapshot cached locally for offline use.
class CachedForecastEntry {
  const CachedForecastEntry({
    required this.locationKey,
    required this.type,
    required this.payload,
    required this.fetchedAtUtc,
    this.expiresAtUtc,
    required this.dataSource,
    this.dataVersion = 1,
  });

  /// Stable key identifying the monitored location (e.g. `lat,lng`).
  final String locationKey;

  /// Which kind of forecast this entry holds.
  final ForecastType type;

  /// Serialized forecast payload (opaque to the storage layer).
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
  String toString() => 'CachedForecastEntry($locationKey/${type.name}, '
      'fetched: ${fetchedAtUtc.toIso8601String()}, source: $dataSource)';
}

/// Kinds of cached forecast supported by the local store.
enum ForecastType { hourly, daily }