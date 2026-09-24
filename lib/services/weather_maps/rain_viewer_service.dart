import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/logger.dart';

/// Latest radar state returned by the RainViewer Weather Maps API.
class RainViewerRadar {
  const RainViewerRadar({required this.host, required this.pastFrames});

  final String host;

  /// Frames in chronological order (each is one 10-minute timestamp).
  final List<RainViewerFrame> pastFrames;

  RainViewerFrame? get latestFrame =>
      pastFrames.isEmpty ? null : pastFrames.last;
}

/// A single radar frame from the RainViewer tile pyramid.
class RainViewerFrame {
  const RainViewerFrame({required this.time, required this.path});

  final int time;

  /// Relative tile path, e.g. `/v2/radar/1710000000`.
  final String path;
}

/// Fetches the RainViewer radar tile index.
///
/// The public Weather Maps API requires no API key and is free for personal
/// and educational use; attribution is required. The free tier serves the
/// universal-blue scheme at 256px up to zoom 7.
class RainViewerService {
  RainViewerService({required this.client, required this.logger});

  static const String endpoint =
      'https://api.rainviewer.com/public/weather-maps.json';

  static const Duration _timeout = Duration(seconds: 15);

  final http.Client client;
  final AppLogger logger;

  /// Returns the radar state, or null when the request fails or is malformed.
  Future<RainViewerRadar?> fetchRadarFrames() async {
    try {
      final response = await client.get(Uri.parse(endpoint)).timeout(_timeout);
      if (response.statusCode != 200) {
        logger.warning(
            'RainViewerService', 'unexpected HTTP ${response.statusCode}');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final host = body['host'] as String? ?? '';
      final past = body['radar']?['past'] as List<dynamic>? ?? const [];
      final frames = past
          .whereType<Map<String, dynamic>>()
          .map(
            (frame) => RainViewerFrame(
              time: (frame['time'] as num?)?.toInt() ?? 0,
              path: frame['path'] as String? ?? '/v2/radar/0',
            ),
          )
          .toList(growable: false);
      return RainViewerRadar(host: host, pastFrames: frames);
    } on TimeoutException {
      logger.warning('RainViewerService', 'request timed out');
      return null;
    } on FormatException {
      logger.warning('RainViewerService', 'invalid JSON received');
      return null;
    } catch (e) {
      logger.warning(
          'RainViewerService', 'request failed: ${e.runtimeType}');
      return null;
    }
  }
}