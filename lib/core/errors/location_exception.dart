import 'app_exception.dart';

/// Raised when the user has not granted location permission (or revoked it).
class LocationPermissionDeniedException extends AppException {
  const LocationPermissionDeniedException({super.cause})
      : super(message: 'Location permission is needed to check the weather '
            'at your position.');
}

/// Raised when the device location provider is unavailable, offline, or fails.
class LocationUnavailableException extends AppException {
  const LocationUnavailableException({super.cause})
      : super(message: 'Could not determine your location.');
}

/// Raised when the geocoding/search provider cannot be reached or responds
/// with invalid/unsuccessful data.
class GeocodingException extends AppException {
  const GeocodingException({
    super.message = 'Could not search for that place.',
    super.cause,
  });
}