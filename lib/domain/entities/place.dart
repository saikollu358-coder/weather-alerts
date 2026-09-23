/// A place returned by the geocoding/search provider (Open-Meteo).
class Place {
  const Place({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.country,
    this.countryCode,
    this.region,
    this.population,
    this.timezone,
  });

  /// Provider place id (handy for future deduplication).
  final int? id;

  final String name;
  final double latitude;
  final double longitude;

  /// Elevation in meters, when reported.
  final double? elevation;

  final String? country;
  final String? countryCode;

  /// First administrative region (e.g. state/province).
  final String? region;

  final int? population;
  final String? timezone;

  /// Human-readable label: "Name, Region, Country".
  String get displayName {
    final parts = <String>[name];
    if (region != null && region!.isNotEmpty) {
      parts.add(region!);
    }
    if (country != null && country!.isNotEmpty) {
      parts.add(country!);
    }
    return parts.join(', ');
  }

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: (json['id'] as num?)?.toInt(),
        name: json['name'] as String? ?? 'Unknown place',
        latitude: ((json['latitude'] as num?) ?? 0).toDouble(),
        longitude: ((json['longitude'] as num?) ?? 0).toDouble(),
        elevation: (json['elevation'] as num?)?.toDouble(),
        country: json['country'] as String?,
        countryCode: json['country_code'] as String?,
        region: json['admin1'] as String?,
        population: (json['population'] as num?)?.toInt(),
        timezone: json['timezone'] as String?,
      );

  @override
  String toString() => 'Place($displayName)';
}