import '../entities/place.dart';

/// Geocoding boundary (Open-Meteo search + reverse).
abstract interface class GeocodingService {
  /// Searches for places matching [query], best results first.
  Future<List<Place>> searchPlaces(String query, {int limit = 10});

  /// Human-readable place nearest to [latitude], [longitude], or null.
  Future<Place?> reverseGeocode(double latitude, double longitude);
}