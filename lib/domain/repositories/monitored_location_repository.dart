import '../entities/monitored_location_record.dart';

/// Repository boundary for user-monitored locations persisted locally.
abstract interface class MonitoredLocationRepository {
  /// All saved locations, most recently used first.
  Future<List<MonitoredLocationRecord>> allLocations();

  /// A single location by its database id, or null.
  Future<MonitoredLocationRecord?> locationById(int id);

  /// A location at (within rounding tolerance) of the given coordinates.
  Future<MonitoredLocationRecord?> byCoordinates(double latitude, double longitude);

  /// Persists a new location and returns its database id.
  Future<int> addLocation(MonitoredLocationRecord record);

  /// Updates an existing location's mutable fields.
  Future<void> updateLocation(MonitoredLocationRecord record);

  /// Removes a saved location.
  Future<void> removeLocation(int id);

  /// Enables/disables monitoring for a location.
  Future<void> setMonitored(int id, {required bool monitored});

  /// Makes [id] the single primary location (atomically unsets others).
  Future<void> setPrimary(int id);

  /// The current primary location, or null.
  Future<MonitoredLocationRecord?> primaryLocation();

  /// The location currently being monitored, or null.
  Future<MonitoredLocationRecord?> monitoredLocation();

  /// Bumps the last-used timestamp (e.g. after a refresh).
  Future<void> touchLastUsed(int id, {DateTime? at});

  /// Removes all saved locations.
  Future<void> clear();
}