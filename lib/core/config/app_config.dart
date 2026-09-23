import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Application configuration injected at build/run time.
///
/// No secrets are hard-coded in the repository. Values are supplied through
/// Dart compile-time defines (`--dart-define=KEY=value`) or platform
/// configuration files (e.g. `google-services.json`, `GoogleService-Info.plist`).
///
/// Supported define keys (documented in README.md / FIREBASE_SETUP.md):
///   WEATHER_ALERTS_ENV                 dev | stage | prod (default: dev)
///   WEATHER_ALERTS_WEATHER_API_BASE    Open-Meteo API base URL (default provided)
///   WEATHER_ALERTS_GEOCODING_API_BASE  Open-Meteo geocoding base URL
///   WEATHER_ALERTS_GOOGLE_MAPS_API_KEY Google Maps API key (Android/web)
///   WEATHER_ALERTS_LOGGING             true | false (default: true)
///   FIREBASE_WEB_API_KEY               Firebase web API key
///   FIREBASE_WEB_AUTH_DOMAIN           Firebase web auth domain
///   FIREBASE_WEB_PROJECT_ID            Firebase web project id
///   FIREBASE_WEB_STORAGE_BUCKET        Firebase web storage bucket
///   FIREBASE_WEB_MESSAGING_SENDER_ID   Firebase web messaging sender id
///   FIREBASE_WEB_APP_ID                Firebase web app id
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.weatherApiBaseUrl,
    required this.geocodingApiBaseUrl,
    required this.googleMapsApiKey,
    required this.loggingEnabled,
    required this.firebaseWebApiKey,
    required this.firebaseWebAuthDomain,
    required this.firebaseWebProjectId,
    required this.firebaseWebStorageBucket,
    required this.firebaseWebMessagingSenderId,
    required this.firebaseWebAppId,
  });

  /// Reads configuration from the process environment (`--dart-define`).
  ///
  /// `String.fromEnvironment` is only valid in a const context, so each value
  /// is captured in a `static const` field below and applied here at runtime.
  AppConfig.fromEnvironment()
      : environment = _kEnvironment,
        weatherApiBaseUrl = _kWeatherApiBaseUrl,
        geocodingApiBaseUrl = _kGeocodingApiBaseUrl,
        googleMapsApiKey = _kGoogleMapsApiKey,
        loggingEnabled = _kLoggingEnabled,
        firebaseWebApiKey = _kFirebaseWebApiKey,
        firebaseWebAuthDomain = _kFirebaseWebAuthDomain,
        firebaseWebProjectId = _kFirebaseWebProjectId,
        firebaseWebStorageBucket = _kFirebaseWebStorageBucket,
        firebaseWebMessagingSenderId = _kFirebaseWebMessagingSenderId,
        firebaseWebAppId = _kFirebaseWebAppId;

  static const String _kEnvironment = String.fromEnvironment(
    'WEATHER_ALERTS_ENV',
    defaultValue: 'dev',
  );

  static const String _kWeatherApiBaseUrl = String.fromEnvironment(
    'WEATHER_ALERTS_WEATHER_API_BASE',
    defaultValue: 'https://api.open-meteo.com/v1',
  );

  static const String _kGeocodingApiBaseUrl = String.fromEnvironment(
    'WEATHER_ALERTS_GEOCODING_API_BASE',
    defaultValue: 'https://geocoding-api.open-meteo.com/v1',
  );

  static const String _kGoogleMapsApiKey = String.fromEnvironment(
    'WEATHER_ALERTS_GOOGLE_MAPS_API_KEY',
  );

  static const bool _kLoggingEnabled = String.fromEnvironment(
        'WEATHER_ALERTS_LOGGING',
        defaultValue: 'true',
      ) ==
      'true';

  static const String _kFirebaseWebApiKey =
      String.fromEnvironment('FIREBASE_WEB_API_KEY');

  static const String _kFirebaseWebAuthDomain =
      String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');

  static const String _kFirebaseWebProjectId =
      String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');

  static const String _kFirebaseWebStorageBucket =
      String.fromEnvironment('FIREBASE_WEB_STORAGE_BUCKET');

  static const String _kFirebaseWebMessagingSenderId =
      String.fromEnvironment('FIREBASE_WEB_MESSAGING_SENDER_ID');

  static const String _kFirebaseWebAppId =
      String.fromEnvironment('FIREBASE_WEB_APP_ID');

  /// Runtime environment: dev | stage | prod.
  final String environment;

  /// Base URL of the weather provider (Open-Meteo by default).
  final String weatherApiBaseUrl;

  /// Base URL of the weather provider geocoding/search endpoint.
  final String geocodingApiBaseUrl;

  /// Google Maps API key, supplied at build time. Empty when not configured.
  final String googleMapsApiKey;

  /// Whether diagnostic logging is enabled. Always false in production.
  final bool loggingEnabled;

  // Web-only Firebase options (mobile uses platform config files).
  final String firebaseWebApiKey;
  final String firebaseWebAuthDomain;
  final String firebaseWebProjectId;
  final String firebaseWebStorageBucket;
  final String firebaseWebMessagingSenderId;
  final String firebaseWebAppId;

  bool get isProduction => environment == 'prod';

  /// Firebase options for web, built from dart-define values.
  /// Returns null when no web Firebase configuration was supplied.
  FirebaseOptions? get firebaseWebOptions {
    final hasAll = firebaseWebApiKey.isNotEmpty &&
        firebaseWebAppId.isNotEmpty &&
        firebaseWebMessagingSenderId.isNotEmpty &&
        firebaseWebProjectId.isNotEmpty;
    if (!hasAll) return null;
    return FirebaseOptions(
      apiKey: firebaseWebApiKey,
      appId: firebaseWebAppId,
      messagingSenderId: firebaseWebMessagingSenderId,
      projectId: firebaseWebProjectId,
      authDomain: firebaseWebAuthDomain.isEmpty
          ? '$firebaseWebProjectId.firebaseapp.com'
          : firebaseWebAuthDomain,
      storageBucket: firebaseWebStorageBucket.isEmpty
          ? '$firebaseWebProjectId.appspot.com'
          : firebaseWebStorageBucket,
    );
  }

  /// True when a full Firebase web configuration was supplied and the app is
  /// permitted to attempt Firebase initialization.
  bool get hasWebFirebaseConfig => firebaseWebOptions != null;
}

/// Provider exposing the active [AppConfig].
/// Override in tests with a custom [AppConfig] instance.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);