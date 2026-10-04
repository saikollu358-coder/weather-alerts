import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/location_exception.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/place.dart';
import '../../domain/services/geocoding_service.dart';

/// [GeocodingService] backed by the Open-Meteo geocoding API.
class GeocodingApiService implements GeocodingService {
  GeocodingApiService({
    required this.config,
    required this.client,
    required this.logger,
  });

  static const Duration _timeout = Duration(seconds: 15);

  final AppConfig config;
  final http.Client client;
  final AppLogger logger;

  @override
  Future<List<Place>> searchPlaces(String query, {int limit = 10}) async {
    final results = await _getResults('/search', {
      'name': query,
      'count': '$limit',
      'language': 'en',
      'format': 'json',
    });
    return results;
  }

  /// Resolves a place name for the given coordinates.
  ///
  /// Unlike [searchPlaces] this never throws: a place label is an enrichment
  /// on top of the raw fix, so callers must be able to keep working with bare
  /// coordinates when the endpoint is unavailable, rate-limited or offline.
  /// Failures are logged and reported as null.
  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async {
    switch (config.reverseGeocodingProvider) {
      case ReverseGeocodingProvider.disabled:
        return null;
      case ReverseGeocodingProvider.openMeteo:
        return _reverseOpenMeteo(latitude, longitude);
      case ReverseGeocodingProvider.bigDataCloud:
        return _reverseBigDataCloud(latitude, longitude);
    }
  }

  // ------------------------------------------------------------------
  // Reverse providers
  // ------------------------------------------------------------------

  Future<Place?> _reverseOpenMeteo(double latitude, double longitude) async {
    try {
      final results = await _getResults('/reverse', {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'language': 'en',
        'format': 'json',
      });
      return results.isEmpty ? null : results.first;
    } on GeocodingException catch (e) {
      logger.warning('GeocodingApiService', 'open-meteo reverse failed: ${e.runtimeType}');
      return null;
    }
  }

  /// BigDataCloud's `reverse-geocode-client` returns a flat object rather than
  /// Open-Meteo's `results` array, so it is mapped separately. The endpoint is
  /// keyless and CORS-enabled, which makes it safe to call from web builds
  /// where a custom User-Agent header cannot be set.
  Future<Place?> _reverseBigDataCloud(double latitude, double longitude) async {
    final uri = Uri.parse(config.reverseGeocodingApiBaseUrl).replace(
      queryParameters: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'localityLanguage': 'en',
      },
    );
    try {
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        logger.warning('GeocodingApiService',
            'unexpected HTTP ${response.statusCode} for reverse geocode');
        return null;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        logger.warning('GeocodingApiService', 'unexpected reverse geocode payload');
        return null;
      }
      return _placeFromBigDataCloud(body, latitude, longitude);
    } on TimeoutException {
      logger.warning('GeocodingApiService', 'reverse geocode request timed out');
      return null;
    } on FormatException {
      logger.warning('GeocodingApiService', 'invalid JSON for reverse geocode');
      return null;
    } catch (e) {
      logger.warning(
          'GeocodingApiService', 'reverse geocode failed: ${e.runtimeType}');
      return null;
    }
  }

  Place? _placeFromBigDataCloud(
    Map<String, dynamic> json,
    double latitude,
    double longitude,
  ) {
    // Prefer the most specific populated name, then fall back through
    // increasingly coarse administrative levels.
    final city = _firstNonEmpty([json['city'], json['locality']]);
    final name = _firstNonEmpty([
      city,
      json['principalSubdivision'],
      json['countryName'],
      json['continent'],
    ]);
    if (name == null) return null;

    // The endpoint does not echo elevation consistently, and the returned
    // coordinates are rounded, so the caller's exact fix is preserved.
    return Place(
      name: name,
      latitude: latitude,
      longitude: longitude,
      country: _firstNonEmpty([json['countryName']]),
      countryCode: json['countryCode'] as String?,
      region: _firstNonEmpty([json['principalSubdivision']]),
      elevation: (json['elevation'] as num?)?.toDouble(),
    );
  }

  String? _firstNonEmpty(List<Object?> candidates) {
    for (final value in candidates) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  Future<List<Place>> _getResults(
    String path,
    Map<String, String> params,
  ) async {
    final uri =
        Uri.parse('${config.geocodingApiBaseUrl}$path').replace(queryParameters: params);
    try {
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        logger.warning(
            'GeocodingApiService', 'unexpected HTTP ${response.statusCode} for $path');
        throw const GeocodingException();
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? const [];
      return results
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on GeocodingException {
      rethrow;
    } on TimeoutException {
      logger.warning('GeocodingApiService', 'request timed out for $path');
      throw const GeocodingException();
    } on FormatException {
      logger.warning('GeocodingApiService', 'invalid JSON for $path');
      throw const GeocodingException();
    } catch (e) {
      logger.warning(
          'GeocodingApiService', 'request failed: ${e.runtimeType} for $path');
      throw const GeocodingException();
    }
  }
}