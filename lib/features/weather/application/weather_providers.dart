import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'weather_controller.dart';
import 'weather_state.dart';

/// State controller for the active location's weather data set.
final weatherControllerProvider =
    NotifierProvider<WeatherController, WeatherState>(WeatherController.new);