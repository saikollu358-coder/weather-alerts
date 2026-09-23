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

  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async {
    final results = await _getResults('/reverse', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'language': 'en',
      'format': 'json',
    });
    return results.isEmpty ? null : results.first;
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