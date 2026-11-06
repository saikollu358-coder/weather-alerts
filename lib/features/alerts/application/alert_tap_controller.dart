import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../../services/firebase/fcm_service.dart';
import '../../../services/firebase/firebase_providers.dart';
import '../../../services/notifications/notification_service_providers.dart';
import 'alert_tap_payload.dart';

/// A notification the user tapped, waiting to be opened in the app.
class AlertTapState {
  const AlertTapState({this.fingerprint});

  /// Fingerprint of the tapped alert, or null when nothing is pending.
  final String? fingerprint;

  bool get hasPendingTap => fingerprint != null;

  @override
  String toString() => 'AlertTapState($fingerprint)';
}

/// Owns "the user tapped a notification, take them there".
///
/// Three tap entrypoints exist and all of them land here:
///
/// * `NotificationService.onOpenedPayloads()` — local notifications, which is
///   how both the background check and forwarded FCM pushes are delivered.
/// * `FcmService.getInitialMessage()` — cold start from a terminated app.
/// * `FcmService.onMessageOpenedApp()` — resume from the background.
///
/// The controller only records *which* alert was tapped; it never fetches or
/// decides anything. Navigation is performed by the UI so that it can wait for
/// authentication and for the router to be mounted.
class AlertTapController extends Notifier<AlertTapState> {
  static const String _tag = 'AlertTapController';

  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  AlertTapState build() {
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscriptions.clear();
    });
    // Listening has to happen after build so the streams are attached exactly
    // once, lazily, and only while something is actually watching.
    Future<void>.microtask(_listen);
    return const AlertTapState();
  }

  /// The tapped alert to open, clearing any previously pending one.
  void consume() {
    if (state.fingerprint == null) return;
    state = const AlertTapState();
  }

  void _listen() {
    if (!ref.mounted) return;

    final notificationService = ref.read(notificationServiceProvider);
    _subscriptions.add(
      notificationService
          .onOpenedPayloads()
          .listen(_onLocalPayload, onError: _logStreamFailure),
    );

    // FcmService already degrades to empty streams / null when Firebase is
    // unavailable, so the local-only build reaches the same dead end safely.
    final fcm = ref.read(fcmServiceProvider);
    _subscriptions.add(
      fcm.onMessageOpenedApp()
          .listen((message) => _onFcmData(message.data),
              onError: _logStreamFailure),
    );
    // Cold start: the message that launched the app is not delivered on the
    // stream, it has to be fetched once.
    unawaited(_consumeInitialMessage(fcm));
  }

  Future<void> _consumeInitialMessage(FcmService fcm) async {
    try {
      final message = await fcm.getInitialMessage();
      if (message == null || !ref.mounted) return;
      _onFcmData(message.data);
    } on Exception catch (e) {
      // getInitialMessage already swallows its own failures; this is belt and
      // braces so a tap can never break app startup.
      ref
          .read(appLoggerProvider)
          .warning(_tag, 'initial message unavailable: ${e.runtimeType}');
    }
  }

  void _onLocalPayload(String raw) {
    final payload = AlertTapPayload.tryParseJson(raw);
    if (payload == null) {
      ref.read(appLoggerProvider).debug(_tag, 'ignoring unparsable payload');
      return;
    }
    _record(payload);
  }

  /// Handles an FCM data payload. Typed as a plain map rather than a
  /// [RemoteMessage] so this controller stays independent of the plugin and can
  /// be driven directly from tests.
  void _onFcmData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    _record(AlertTapPayload.fromMap(data));
  }

  void _record(AlertTapPayload payload) {
    if (!payload.hasAlert) {
      ref
          .read(appLoggerProvider)
          .debug(_tag, 'payload carried no alert id; ignoring');
      return;
    }
    if (!ref.mounted) return;
    state = AlertTapState(fingerprint: payload.fingerprint);
  }

  void _logStreamFailure(Object error) {
    // A failing tap stream must not take the dashboard down; the local
    // notification path usually still works.
    ref
        .read(appLoggerProvider)
        .warning(_tag, 'tap stream failed: ${error.runtimeType}');
  }
}

/// Tap-to-navigate state for the whole application.
final alertTapControllerProvider =
    NotifierProvider<AlertTapController, AlertTapState>(
  AlertTapController.new,
);