import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import 'locations_state.dart';

/// Owns the saved monitored-locations list.
///
/// Widgets never touch the location repository directly; they watch
/// [locationsControllerProvider] and call [refresh], [setPrimary] or [remove].
class LocationsController extends Notifier<LocationsState> {
  final String _unexpectedMessage = 'Could not load locations.';

  @override
  LocationsState build() {
    refresh();
    return const LocationsState.loading();
  }

  /// Reloads the saved locations from the repository.
  Future<void> refresh() async {
    final repository = ref.read(monitoredLocationRepositoryProvider);
    final logger = ref.read(appLoggerProvider);
    try {
      final locations = await repository.allLocations();
      _set(LocationsState(status: LocationsStatus.ready, locations: locations));
    } on AppException catch (e) {
      _set(LocationsState(status: LocationsStatus.error, errorMessage: e.message));
    } catch (e) {
      logger.warning('LocationsController', 'refresh failed: ${e.runtimeType}');
      _set(LocationsState(status: LocationsStatus.error, errorMessage: _unexpectedMessage));
    }
  }

  /// Makes [id] the single primary location.
  Future<void> setPrimary(int id) async {
    try {
      await ref.read(monitoredLocationRepositoryProvider).setPrimary(id);
      await refresh();
    } catch (e) {
      _set(LocationsState(
        status: LocationsStatus.error,
        errorMessage: 'Could not update the primary location.',
      ));
    }
  }

  /// Removes a saved location.
  Future<void> remove(int id) async {
    try {
      await ref.read(monitoredLocationRepositoryProvider).removeLocation(id);
      await refresh();
    } catch (e) {
      _set(LocationsState(
        status: LocationsStatus.error,
        errorMessage: 'Could not remove the location.',
      ));
    }
  }

  void _set(LocationsState next) {
    if (!ref.mounted) return;
    state = next;
  }
}