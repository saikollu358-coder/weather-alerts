import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/current_location.dart';
import '../../../domain/entities/geo_position.dart';
import '../../../domain/entities/place.dart';
import '../../../domain/repositories/current_location_repository.dart';
import '../../../domain/services/geocoding_service.dart';
import '../../../domain/services/location_service.dart';

/// Resolves the device's position into a labelled [CurrentLocation].
///
/// This replaces the old "save a location" flow: nothing is added to a list
/// and the user never picks a place. Capturing a fix also records it as the
/// last known position, which is what background weather checks and push
/// routing fall back to.
class ResolveCurrentLocationUseCase {
  ResolveCurrentLocationUseCase({
    required this.locationService,
    required this.geocodingService,
    required this.currentLocation,
    required this.logger,
  });

  final LocationService locationService;
  final GeocodingService geocodingService;
  final CurrentLocationRepository currentLocation;
  final AppLogger logger;

  /// Place names already resolved this session, keyed by snapped coordinates.
  ///
  /// GPS emits a new fix every few seconds; reverse geocoding each one would
  /// hammer a free endpoint for a label that has not changed.
  final Map<String, String> _labelCache = {};

  /// The last captured position without touching the GPS radio, or null when
  /// the app has never held a fix.
  Future<CurrentLocation?> lastKnown() => currentLocation.read();

  /// Captures a fresh fix, resolves its place name and records it.
  ///
  /// Throws [AppException] when no fix can be obtained; the caller surfaces
  /// that as a location error state.
  Future<CurrentLocation> run() async {
    final fix = await locationService.currentPosition();
    return _labelAndRecord(fix);
  }

  /// Labels and records an already-obtained [position] without re-reading GPS.
  Future<CurrentLocation> fromPosition(GeoPosition position) =>
      _labelAndRecord(position);

  Future<CurrentLocation> _labelAndRecord(GeoPosition fix) async {
    // Snap first so the cache key matches what will actually be stored.
    final snapped = CurrentLocation.fromPosition(fix);
    final label = await _resolveLabel(snapped);
    final location = CurrentLocation.fromPosition(
      snapped.position,
      label: label,
      capturedAtUtc: DateTime.now().toUtc(),
    );
    await currentLocation.save(location);
    return location;
  }

  Future<String?> _resolveLabel(CurrentLocation snapped) async {
    final key = snapped.locationKey;
    final cached = _labelCache[key];
    if (cached != null) return cached;

    final Place? place;
    try {
      place = await geocodingService.reverseGeocode(
        snapped.latitude,
        snapped.longitude,
      );
    } catch (e) {
      // Reverse geocoding is decoration: a failure must never cost the user
      // their weather. Fall back to the coordinate label and retry on move.
      logger.debug('ResolveCurrentLocation', 'reverse geocode failed: $e');
      return null;
    }
    if (place == null) return null;
    final label = place.displayName;
    _labelCache[key] = label;
    return label;
  }
}