import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/geo_position.dart';
import '../../../domain/entities/monitored_location_record.dart';
import '../../../domain/repositories/monitored_location_repository.dart';
import '../../../domain/services/geocoding_service.dart';
import '../../../domain/services/location_service.dart';

/// Persists the device's current position as a GPS-sourced monitored location.
class SaveCurrentLocationUseCase {
  SaveCurrentLocationUseCase({
    required this.locationService,
    required this.geocodingService,
    required this.locations,
    required this.logger,
  });

  final LocationService locationService;
  final GeocodingService geocodingService;
  final MonitoredLocationRepository locations;
  final AppLogger logger;

  /// Captures the current position and saves it locally.
  ///
  /// When [name] is empty, the reverse-geocoded display name is used; if
  /// geocoding fails/returns nothing the location falls back to "Current
  /// location". Coordinates already saved elsewhere are rejected by the
  /// repository (unique index) and surfaced to the caller.
  Future<MonitoredLocationRecord> run({String? name}) async {
    final geo = await locationService.currentPosition();
    var placeName = (name ?? '').trim();
    if (placeName.isEmpty) {
      placeName = await _reverseName(geo);
    }
    final now = DateTime.now().toUtc();
    final id = await locations.addLocation(
      MonitoredLocationRecord(
        name: placeName,
        latitude: geo.latitude,
        longitude: geo.longitude,
        accuracy: geo.accuracy,
        source: MonitoredLocationSource.gps,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    final saved = await locations.locationById(id);
    if (saved == null) {
      throw const CacheException();
    }
    logger.debug('SaveCurrentLocationUseCase', 'saved monitored location id=$id');
    return saved;
  }

  Future<String> _reverseName(GeoPosition geo) async {
    try {
      final place =
          await geocodingService.reverseGeocode(geo.latitude, geo.longitude);
      if (place != null) return place.displayName;
    } catch (e) {
      logger.warning(
          'SaveCurrentLocationUseCase', 'reverse geocode failed: ${e.runtimeType}');
    }
    return 'Current location';
  }
}