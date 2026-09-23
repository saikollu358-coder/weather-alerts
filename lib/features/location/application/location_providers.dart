import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../services/location/location_service_providers.dart';
import 'location_controller.dart';
import 'location_state.dart';
import 'locations_controller.dart';
import 'locations_state.dart';
import 'save_current_location_use_case.dart';

/// The single location state provider for the application.
final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

/// Captures the current GPS position into the monitored-locations store.
final saveCurrentLocationProvider = Provider<SaveCurrentLocationUseCase>(
  (ref) => SaveCurrentLocationUseCase(
    locationService: ref.watch(locationServiceProvider),
    geocodingService: ref.watch(geocodingServiceProvider),
    locations: ref.watch(monitoredLocationRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// The saved monitored-locations list state provider.
final locationsControllerProvider =
    NotifierProvider<LocationsController, LocationsState>(LocationsController.new);