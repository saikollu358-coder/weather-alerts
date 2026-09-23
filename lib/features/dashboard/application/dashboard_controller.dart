import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repositories/local_repository_providers.dart';
import '../../../domain/entities/monitored_location_record.dart';
import '../../../services/weather_analysis/weather_analysis.dart';
import '../../alerts/application/alerts_providers.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../weather/application/weather_providers.dart';
import '../../weather/application/weather_state.dart';
import 'dashboard_providers.dart';
import 'dashboard_state.dart';

/// Orchestrates the Phase 7 dashboard pipeline for the active location:
///
///   location -> weather (WeatherController) -> analysis (weatherAnalysisProvider)
///            -> alerts (AlertIngestUseCase) -> DashboardState
///
/// Widgets never compose this manually; they watch [dashboardControllerProvider]
/// and call [selectLocation] / [useCurrentGps] / [refresh] etc.
class DashboardController extends Notifier<DashboardState> {
  DateTime? _lastIngestedAnalysisAt;

  @override
  DashboardState build() {
    // Keep the dashboard in sync whenever the weather controller moves. This
    // also triggers alert ingestion on every new ready analysis.
    ref.listen(weatherControllerProvider, (previous, next) {
      _syncFromWeather(next);
    });
    _bootstrap();
    return const DashboardState.bootstrapping();
  }

  /// Selects a saved location to monitor and loads its weather.
  Future<void> selectLocation(MonitoredLocationRecord record) async {
    final repository = ref.read(monitoredLocationRepositoryProvider);
    try {
      if (record.id != null) {
        final at = DateTime.now().toUtc();
        await repository.touchLastUsed(record.id!, at: at);
        await repository.setPrimary(record.id!);
      }
      _set(DashboardState(
        status: DashboardStatus.loading,
        location: record,
        bundle: state.bundle,
        analysis: state.analysis,
        activeAlerts: state.activeAlerts,
      ));
      await _loadWeather(record);
    } on AppException catch (e) {
      _set(DashboardState(
        status: DashboardStatus.error,
        location: record,
        errorMessage: e.message,
      ));
    }
  }

  /// Starts the GPS permission flow and, when a fix is available, saves and
  /// selects the current position. Returns the saved location, or null when
  /// the user still needs to grant permission (watch `locationController`).
  Future<MonitoredLocationRecord?> useCurrentGps({String? name}) async {
    final location = ref.read(locationControllerProvider.notifier);
    await location.start();
    final status = ref.read(locationControllerProvider).status;
    if (status != LocationStatus.ready) return null;
    return _saveAndSelectCurrent(name: name);
  }

  /// Requests location permission (after a prior denial) and, when granted,
  /// runs the current-location flow.
  Future<MonitoredLocationRecord?> requestPermissionAndUseGps() async {
    final location = ref.read(locationControllerProvider.notifier);
    final granted = await location.requestPermission();
    if (!granted) return null;
    return _saveAndSelectCurrent();
  }

  /// Opens OS settings from the permanently-denied state.
  Future<void> openSettings() =>
      ref.read(locationControllerProvider.notifier).openSettings();

  /// Force-refreshes the current location's weather.
  Future<void> refresh() async {
    final location = state.location;
    if (location == null) return;
    await _loadWeather(location, forceRefresh: true);
  }

  /// Retries after an error (weather load or location selection).
  Future<void> retry() async {
    final location = state.location;
    if (location != null) {
      await selectLocation(location);
    } else {
      await _bootstrap();
    }
  }

  // ------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final repository = ref.read(monitoredLocationRepositoryProvider);
    try {
      final primary = await repository.primaryLocation();
      if (primary != null) {
        await selectLocation(primary);
        return;
      }
      final all = await repository.allLocations();
      if (all.isNotEmpty) {
        await selectLocation(all.first);
        return;
      }
      _set(const DashboardState(status: DashboardStatus.needsLocation));
    } on AppException catch (e) {
      _set(DashboardState(status: DashboardStatus.error, errorMessage: e.message));
    } catch (e) {
      ref.read(appLoggerProvider).warning(
          'DashboardController', 'bootstrap failed: ${e.runtimeType}');
      _set(DashboardState(
        status: DashboardStatus.error,
        errorMessage: 'Could not initialize the weather dashboard.',
      ));
    }
  }

  Future<MonitoredLocationRecord?> _saveAndSelectCurrent({String? name}) async {
    try {
      final saved = await ref
          .read(saveCurrentLocationProvider)
          .run(name: name);
      if (saved.id != null) {
        await ref.read(monitoredLocationRepositoryProvider).setPrimary(saved.id!);
      }
      await selectLocation(saved);
      return saved;
    } on AppException catch (e) {
      _set(DashboardState(
        status: DashboardStatus.error,
        location: state.location,
        bundle: state.bundle,
        analysis: state.analysis,
        errorMessage: e.message,
      ));
      return null;
    } catch (e) {
      ref.read(appLoggerProvider).warning(
          'DashboardController', 'save current location failed: ${e.runtimeType}');
      _set(DashboardState(
        status: DashboardStatus.error,
        location: state.location,
        errorMessage: 'Could not add the current location.',
      ));
      return null;
    }
  }

  Future<void> _loadWeather(
    MonitoredLocationRecord record, {
    bool forceRefresh = false,
  }) async {
    await ref.read(weatherControllerProvider.notifier).load(
          locationKey: record.locationKey,
          latitude: record.latitude,
          longitude: record.longitude,
          forceRefresh: forceRefresh,
        );
  }

  void _syncFromWeather(WeatherState weather) {
    if (!ref.mounted) return;
    final current = state;
    switch (weather.status) {
      case WeatherStatus.idle:
        return;
      case WeatherStatus.loading:
        _set(current.copyWith(
          status: DashboardStatus.loading,
          bundle: weather.bundle,
        ));
      case WeatherStatus.ready:
        final analysis = ref.read(weatherAnalysisProvider);
        _set(DashboardState(
          status: DashboardStatus.ready,
          location: current.location,
          bundle: weather.bundle,
          analysis: analysis ?? current.analysis,
          activeAlerts: current.activeAlerts,
        ));
        if (analysis != null) {
          _maybeIngest(analysis);
        }
      case WeatherStatus.error:
        _set(current.copyWith(
          status: DashboardStatus.error,
          bundle: weather.bundle,
          errorMessage: weather.errorMessage,
          clearError: false,
        ));
    }
  }

  void _maybeIngest(WeatherAnalysis analysis) {
    final anchor = analysis.analyzedAtUtc;
    if (_lastIngestedAnalysisAt == anchor) return;
    _lastIngestedAnalysisAt = anchor;
    _ingest(analysis);
  }

  Future<void> _ingest(WeatherAnalysis analysis) async {
    final location = state.location;
    if (location == null) return;
    try {
      final active = await ref
          .read(alertIngestUseCaseProvider)
          .ingest(analysis, locationKey: location.locationKey);
      if (!ref.mounted) return;
      await ref.read(alertsControllerProvider.notifier).refresh();
      if (!ref.mounted) return;
      _set(state.copyWith(activeAlerts: active));
    } catch (e) {
      ref.read(appLoggerProvider).warning(
          'DashboardController', 'alert ingest failed: ${e.runtimeType}');
    }
  }

  void _set(DashboardState next) {
    if (!ref.mounted) return;
    state = next;
  }
}