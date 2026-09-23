import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../domain/entities/weather/weather_bundle.dart';
import '../../../services/weather/weather_service_providers.dart';
import 'weather_providers.dart';
import 'weather_state.dart';

/// Owns weather loading for a single location.
///
/// Widgets never touch the weather service or cache; they watch
/// [weatherControllerProvider] and call [load] / [reset].
class WeatherController extends Notifier<WeatherState> {
  static const String _unexpectedMessage = 'Could not load weather data.';

  @override
  WeatherState build() => const WeatherState.initial();

  /// Loads weather for the location at [latitude]/[longitude].
  ///
  /// Returns the bundle on success (also stored in state), or null after
  /// setting an informative [WeatherState.errorMessage].
  Future<WeatherBundle?> load({
    required String locationKey,
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final service = ref.read(weatherServiceProvider);
    final logger = ref.read(appLoggerProvider);
    _set(state.copyWith(status: WeatherStatus.loading, clearError: true));
    try {
      final bundle = await service.load(
        locationKey: locationKey,
        latitude: latitude,
        longitude: longitude,
        forceRefresh: forceRefresh,
      );
      _set(WeatherState(status: WeatherStatus.ready, bundle: bundle));
      return bundle;
    } on AppException catch (e) {
      _set(WeatherState(status: WeatherStatus.error, errorMessage: e.message));
      return null;
    } catch (e) {
      logger.warning('WeatherController', 'load failed: ${e.runtimeType}');
      _set(const WeatherState(
        status: WeatherStatus.error,
        errorMessage: _unexpectedMessage,
      ));
      return null;
    }
  }

  /// Clears the last bundle and returns to the idle state.
  void reset() => _set(const WeatherState.initial());

  void _set(WeatherState next) {
    if (!ref.mounted) return;
    state = next;
  }
}