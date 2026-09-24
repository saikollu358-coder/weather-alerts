import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:weather_alerts/core/utils/logger.dart';
import 'package:weather_alerts/services/weather_maps/rain_viewer_service.dart';

final _logger = AppLogger(enabled: false);

String _body({
  String host = 'https://tilecache.rainviewer.example',
  List<Map<String, dynamic>>? past,
}) =>
    jsonEncode({
      'version': '2.0',
      'generated': 1710000005,
      'host': host,
      'radar': {'past': past ?? _twoFrames(), 'nowcast': [], 'forecast': []},
    });

List<Map<String, dynamic>> _twoFrames() => [
      {'time': 1710000000, 'path': '/v2/radar/1710000000'},
      {'time': 1710000060, 'path': '/v2/radar/1710000060'},
    ];

void main() {
  group('RainViewerService', () {
    test('parses host and past frames in order', () async {
      final client = MockClient(
        (_) async => http.Response(_body(), 200),
      );
      final radar = await RainViewerService(client: client, logger: _logger)
          .fetchRadarFrames();

      expect(radar, isNotNull);
      expect(radar!.host, 'https://tilecache.rainviewer.example');
      expect(radar.pastFrames, hasLength(2));
      expect(radar.pastFrames.first.time, 1710000000);
      expect(radar.latestFrame!.time, 1710000060);
      expect(radar.latestFrame!.path, '/v2/radar/1710000060');
    });

    test('returns null on empty past list with latest frame unresolved',
        () async {
      final client = MockClient(
        (_) async => http.Response(_body(past: []), 200),
      );
      final radar = await RainViewerService(client: client, logger: _logger)
          .fetchRadarFrames();

      expect(radar, isNotNull);
      expect(radar!.latestFrame, isNull);
      expect(radar.host, isNotEmpty);
    });

    test('returns null on non-200 response', () async {
      final client = MockClient((_) async => http.Response('oops', 503));
      final radar = await RainViewerService(client: client, logger: _logger)
          .fetchRadarFrames();

      expect(radar, isNull);
    });

    test('returns null on malformed JSON', () async {
      final client =
          MockClient((_) async => http.Response('not json at all', 200));
      final radar = await RainViewerService(client: client, logger: _logger)
          .fetchRadarFrames();

      expect(radar, isNull);
    });

    test('returns null when the client throws', () async {
      final client = MockClient((_) async => throw http.ClientException('boom'));
      final radar = await RainViewerService(client: client, logger: _logger)
          .fetchRadarFrames();

      expect(radar, isNull);
    });
  });
}