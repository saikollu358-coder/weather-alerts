import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../services/location/location_service_providers.dart';
import 'location_controller.dart';
import 'location_state.dart';
import 'resolve_current_location_use_case.dart';

/// The single location state provider for the application.
final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

/// Resolves the device's GPS fix into a labelled current location.
final resolveCurrentLocationProvider = Provider<ResolveCurrentLocationUseCase>(
  (ref) => ResolveCurrentLocationUseCase(
    locationService: ref.watch(locationServiceProvider),
    geocodingService: ref.watch(geocodingServiceProvider),
    currentLocation: ref.watch(currentLocationRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);