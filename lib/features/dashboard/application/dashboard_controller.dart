import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/current_location.dart';
import '../../../services/firebase/device_token_providers.dart';
import '../../../services/weather_analysis/weather_analysis.dart';
import '../../alerts/application/alerts_providers.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../weather/application/weather_providers.dart';
import '../../weather/application/weather_state.dart';
import 'dashboard_providers.dart';
import 'dashboard_state.dart';

/// Distance in meters the device must move before the weather pipeline reloads.
///
/// Below this the change is inside GPS noise, so re-fetching would burn API
/// calls without telling the user anything new.
const double kReloadOnMoveMeters = 500;

/// Orchestrates the dashboard pipeline for the device's current position:
///
///   position -> weather (WeatherController) -> analysis (weatherAnalysisProvider)
///            -> alerts (AlertIngestUseCase) -> DashboardState
///
/// There is no location selection: the only location is wherever the device is.
/// Widgets watch [dashboardControllerProvider] and call [refresh], [retry],
/// [requestPermission] or [openSettings].
class DashboardController extends Notifier<DashboardState> {
  DateTime? _lastIngestedAnalysisAt;

  /// Position the current bundle was fetched for, used by the move threshold.
  CurrentLocation? _loadedLocation;

  @override
  DashboardState build() {
    // Keep the dashboard in sync whenever the weather controller moves. This
    // also triggers alert ingestion on every new ready analysis.
    ref.listen(weatherControllerProvider, (previous, next) {
      _syncFromWeather(next);
    });
    // Follow the device: every new fix updates the displayed position and, if
    // the user has moved far enough, re-runs the weather pipeline.
    ref.listen(locationControllerProvider, (previous, next) {
      if (next.status == LocationStatus.ready) {
        _applyLatestFix();
      }
    });
    _bootstrap();
    return const DashboardState.bootstrapping();
  }

  // ------------------------------------------------------------------
  // Public actions
  // ------------------------------------------------------------------

  /// Asks for location permission, resolving the position when granted.
  ///
  /// Called automatically right after sign-in so the first screen the user
  /// sees is the location prompt rather than an empty dashboard.
  Future<void> requestPermission() async {
    final granted = await ref.read(locationControllerProvider.notifier).requestPermission();
    if (!granted || !ref.mounted) return;
    await _captureAndLoad();
  }

  /// Re-reads GPS and refreshes weather, bypassing every cache.
  Future<void> refresh() async {
    await _captureAndLoad(forceRefresh: true);
  }

  /// Retries after an error.
  Future<void> retry() async {
    await _captureAndLoad(forceRefresh: true);
  }

  /// Opens OS settings from the permanently-denied state.
  Future<void> openSettings() =>
      ref.read(locationControllerProvider.notifier).openSettings();

  // ------------------------------------------------------------------

  Future<void> _bootstrap() async {
    // Show the last known position immediately so a returning user never sees
    // an empty screen while the GPS radio warms up.
    final cached = await ref.read(resolveCurrentLocationProvider).lastKnown();
    if (!ref.mounted) return;
    if (cached != null) {
      _loadedLocation = cached;
      _set(state.copyWith(
        status: DashboardStatus.loading,
        location: cached,
      ));
      await _loadWeather(cached);
    }

    await ref.read(locationControllerProvider.notifier).start();
    if (!ref.mounted) return;

    final locationState = ref.read(locationControllerProvider);
    if (locationState.position != null ||
        locationState.status == LocationStatus.ready) {
      // Either a fix already arrived, or permission is granted and the first
      // one is still on its way. Read GPS directly in both cases rather than
      // asking a user who already granted access to grant it again.
      await _captureAndLoad();
    } else if (cached == null) {
      _set(const DashboardState(status: DashboardStatus.needsLocation));
    }
  }

  /// Applies the newest streamed fix to state, reloading weather only when the
  /// device has actually moved. Wired to [locationControllerProvider] so the
  /// dashboard follows the user without any polling.
  Future<void> _applyLatestFix() async {
    try {
      final fix = ref.read(locationControllerProvider).position;
      if (fix == null) return;
      await _captureAndLoad();
    } on AppException catch (e) {
      _set(state.copyWith(
        status: state.hasLocation ? state.status : DashboardStatus.error,
        errorMessage: e.message,
      ));
    }
  }

  Future<void> _captureAndLoad({bool forceRefresh = false}) async {
    final resolver = ref.read(resolveCurrentLocationProvider);
    final CurrentLocation location;
    try {
      location = await resolver.run();
    } on AppException catch (e) {
      _set(state.copyWith(
        status: state.hasLocation ? state.status : DashboardStatus.error,
        errorMessage: e.message,
      ));
      return;
    } catch (e) {
      ref.read(appLoggerProvider).warning(
          'DashboardController', 'position capture failed: ${e.runtimeType}');
      _set(state.copyWith(
        status: state.hasLocation ? state.status : DashboardStatus.error,
        errorMessage: 'Could not determine your current location.',
      ));
      return;
    }
    if (!ref.mounted) return;

    // Always surface the freshest position, even when the weather is reused.
    _set(state.copyWith(
      location: location,
      clearError: true,
    ));

    // Keep FCM routing pointed at the current position so background pushes
    // reach the device. Best-effort: push registration is unavailable in
    // local-only mode and must never break the foreground weather pipeline.
    _syncPushRouting();

    if (!forceRefresh && !_movedFarEnough(location)) return;
    await _loadWeather(location, forceRefresh: forceRefresh);
  }

  /// Republishes the device's FCM routing key for the captured position.
  void _syncPushRouting() {
    try {
      ref.read(deviceTokenServiceProvider).syncCurrentLocation().ignore();
    } catch (e) {
      ref.read(appLoggerProvider).debug(
        'DashboardController',
        'push routing sync skipped: ${e.runtimeType}',
      );
    }
  }

  bool _movedFarEnough(CurrentLocation next) {
    final previous = _loadedLocation;
    if (previous == null) return true;
    return _distanceMeters(previous, next) >= kReloadOnMoveMeters;
  }

  static double _distanceMeters(CurrentLocation a, CurrentLocation b) {
    // Equirectangular approximation: accurate well beyond the few-hundred-meter
    // threshold it is used for, and avoids a spherical trigonometry dependency.
    const earthRadiusMeters = 6371000.0;
    final meanLatRad = (a.latitude + b.latitude) / 2 * math.pi / 180;
    final dx = (b.longitude - a.longitude) * math.pi / 180 * math.cos(meanLatRad);
    final dy = (b.latitude - a.latitude) * math.pi / 180;
    return math.sqrt(dx * dx + dy * dy) * earthRadiusMeters;
  }

  Future<void> _loadWeather(
    CurrentLocation location, {
    bool forceRefresh = false,
  }) async {
    await ref.read(weatherControllerProvider.notifier).load(
          locationKey: location.locationKey,
          latitude: location.latitude,
          longitude: location.longitude,
          forceRefresh: forceRefresh,
        );
    if (ref.mounted) _loadedLocation = location;
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