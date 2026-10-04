import 'dart:convert';

import '../../core/utils/logger.dart';
import '../../domain/entities/current_location.dart';
import '../../domain/repositories/current_location_repository.dart';
import '../../domain/repositories/preference_repository.dart';

/// [CurrentLocationRepository] backed by the local preference key/value store.
///
/// The last known position is a single small record, so it is stored as one
/// JSON preference rather than a dedicated table: this keeps it device-local
/// and out of every cloud sync domain.
class CurrentLocationRepositoryImpl implements CurrentLocationRepository {
  CurrentLocationRepositoryImpl({
    required this.preferences,
    this.logger,
  });

  static const String storageKey = 'last_known_location';

  final PreferenceRepository preferences;
  final AppLogger? logger;

  @override
  Future<CurrentLocation?> read() async {
    try {
      final raw = await preferences.read(storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CurrentLocation.fromJson(decoded);
    } catch (e) {
      // A corrupt entry must not break startup or a background task.
      logger?.warning('CurrentLocationRepo', 'read failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> save(CurrentLocation location) async {
    try {
      await preferences.write(storageKey, jsonEncode(location.toJson()));
    } catch (e) {
      logger?.warning('CurrentLocationRepo', 'save failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await preferences.delete(storageKey);
    } catch (e) {
      logger?.warning('CurrentLocationRepo', 'clear failed: ${e.runtimeType}');
    }
  }
}