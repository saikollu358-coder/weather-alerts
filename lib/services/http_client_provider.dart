import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Shared HTTP client; closed when the provider scope is disposed.
final httpClientProvider = Provider<http.Client>(
  (ref) {
    final client = http.Client();
    ref.onDispose(client.close);
    return client;
  },
);