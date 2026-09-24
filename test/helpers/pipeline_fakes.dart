import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weather_alerts/data/repositories/local_repository_providers.dart';
import 'package:weather_alerts/domain/entities/alert_record.dart';
import 'package:weather_alerts/domain/entities/alert_status.dart';
import 'package:weather_alerts/domain/entities/geo_position.dart';
import 'package:weather_alerts/domain/entities/monitored_location_record.dart';
import 'package:weather_alerts/domain/entities/notification_state_record.dart';
import 'package:weather_alerts/domain/entities/place.dart';
import 'package:weather_alerts/domain/entities/user_preference.dart';
import 'package:weather_alerts/domain/entities/weather/daily_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/hourly_forecast.dart';
import 'package:weather_alerts/domain/entities/weather/weather_bundle.dart';
import 'package:weather_alerts/domain/entities/weather/weather_snapshot.dart';
import 'package:weather_alerts/domain/enums/location_permission.dart';
import 'package:weather_alerts/domain/enums/notification_permission.dart';
import 'package:weather_alerts/domain/repositories/alert_history_repository.dart';
import 'package:weather_alerts/domain/repositories/monitored_location_repository.dart';
import 'package:weather_alerts/domain/repositories/notification_state_repository.dart';
import 'package:weather_alerts/domain/repositories/preference_repository.dart';
import 'package:weather_alerts/domain/services/geocoding_service.dart';
import 'package:weather_alerts/domain/services/location_service.dart';
import 'package:weather_alerts/domain/services/notification_service.dart';
import 'package:weather_alerts/domain/services/weather_service.dart';
import 'package:weather_alerts/services/location/location_service_providers.dart';
import 'package:weather_alerts/services/weather/weather_service_providers.dart';

/// Deterministic [WeatherService] fake for pipeline tests.
class FakeWeatherService implements WeatherService {
  FakeWeatherService({this.bundle, this.error});

  WeatherBundle? bundle;
  Exception? error;
  int calls = 0;
  String? lastLocationKey;
  bool? lastForceRefresh;

  @override
  Future<WeatherBundle> load({
    required String locationKey,
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    calls++;
    lastLocationKey = locationKey;
    lastForceRefresh = forceRefresh;
    final e = error;
    if (e != null) throw e;
    return bundle!;
  }
}

/// [LocationService] fake with configurable permission + position behavior.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.fix,
    this.permission = LocationPermissionStatus.granted,
    this.serviceEnabled = true,
  });

  GeoPosition? fix;
  LocationPermissionStatus permission;
  bool serviceEnabled;
  bool openAppSettingsResult = true;
  int startLikeCalls = 0;

  /// When true, [requestPermission] flips [permission] to granted, letting
  /// tests simulate the OS prompt being accepted on the first attempt.
  bool grantOnRequest = false;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> permissionStatus() async => permission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    if (grantOnRequest) permission = LocationPermissionStatus.granted;
    return permission;
  }

  @override
  Future<bool> openAppSettings() async => openAppSettingsResult;

  @override
  Future<GeoPosition> currentPosition({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    startLikeCalls++;
    if (permission != LocationPermissionStatus.granted) {
      throw StateError('permission not granted');
    }
    return fix ??
        GeoPosition(
          latitude: 42.0,
          longitude: -71.0,
          timestamp: _kFixedTimestamp,
        );
  }

  @override
  Future<GeoPosition?> lastKnownPosition() async => fix;

  @override
  Stream<GeoPosition> positionStream({
    Duration? timeLimit,
    double distanceFilter = 0,
  }) =>
      const Stream.empty();
}

final DateTime _kFixedTimestamp = DateTime.utc(2026, 1, 1, 12);

GeoPosition geoPosition(double latitude, double longitude) => GeoPosition(
      latitude: latitude,
      longitude: longitude,
      timestamp: _kFixedTimestamp,
    );

/// [GeocodingService] fake.
class FakeGeocodingService implements GeocodingService {
  FakeGeocodingService({this.place, this.error});

  final Place? place;
  final Object? error;

  @override
  Future<List<Place>> searchPlaces(String query, {int limit = 10}) async =>
      const [];

  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async {
    final err = error;
    if (err != null) throw err;
    return place;
  }
}

/// In-memory [MonitoredLocationRepository] with duplicate + primary handling.
class InMemoryMonitoredLocations implements MonitoredLocationRepository {
  InMemoryMonitoredLocations({List<MonitoredLocationRecord> seed = const []}) {
    for (final record in seed) {
      _records.add(record.copyWith(id: record.id ?? _nextId++));
    }
  }

  final List<MonitoredLocationRecord> _records = [];
  int _nextId = 1;

  /// When set, listing operations throw so controllers can exercise their
  /// error paths deterministically.
  bool failLoads = false;

  @override
  Future<List<MonitoredLocationRecord>> allLocations() async {
    if (failLoads) throw StateError('boom');
    final sorted = List.of(_records)
      ..sort((a, b) {
        final usedA = a.lastUsedAtUtc ?? a.createdAtUtc;
        final usedB = b.lastUsedAtUtc ?? b.createdAtUtc;
        return usedB.compareTo(usedA);
      });
    return sorted;
  }

  @override
  Future<MonitoredLocationRecord?> locationById(int id) async {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<MonitoredLocationRecord?> byCoordinates(
      double latitude, double longitude) async {
    final tolerance = 0.0005;
    for (final record in _records) {
      if ((record.latitude - latitude).abs() <= tolerance &&
          (record.longitude - longitude).abs() <= tolerance) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<int> addLocation(MonitoredLocationRecord record) async {
    final existing = await byCoordinates(record.latitude, record.longitude);
    if (existing != null) {
      throw StateError('duplicate location');
    }
    final id = _nextId++;
    _records.add(record.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateLocation(MonitoredLocationRecord record) async {
    final index = _records.indexWhere((r) => r.id == record.id);
    if (index < 0) return;
    _records[index] = record;
  }

  @override
  Future<void> removeLocation(int id) async {
    _records.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> setMonitored(int id, {required bool monitored}) async {
    final index = _records.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(isMonitored: monitored);
  }

  @override
  Future<void> setPrimary(int id) async {
    for (var i = 0; i < _records.length; i++) {
      _records[i] = _records[i].copyWith(isPrimary: _records[i].id == id);
    }
  }

  @override
  Future<MonitoredLocationRecord?> primaryLocation() async {
    for (final record in _records) {
      if (record.isPrimary) return record;
    }
    return null;
  }

  @override
  Future<MonitoredLocationRecord?> monitoredLocation() async {
    for (final record in _records) {
      if (record.isMonitored) return record;
    }
    return null;
  }

  @override
  Future<void> touchLastUsed(int id, {DateTime? at}) async {
    final index = _records.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(
      lastUsedAtUtc: at ?? _kFixedTimestamp,
      updatedAtUtc: at ?? _kFixedTimestamp,
    );
  }

  @override
  Future<void> clear() async => _records.clear();
}

/// In-memory [AlertHistoryRepository] with fingerprint-based deduplication.
class InMemoryAlertHistory implements AlertHistoryRepository {
  InMemoryAlertHistory({List<AlertRecord> seed = const []}) {
    _records.addAll(seed);
  }

  final List<AlertRecord> _records = [];

  /// Total persisted records (useful for deduplication assertions).
  int get recordCount => _records.length;

  /// When set, listing operations throw so controllers can exercise their
  /// error paths deterministically.
  bool failLoads = false;

  @override
  Future<void> upsertAlert(AlertRecord alert) async {
    final index =
        _records.indexWhere((r) => r.fingerprint == alert.fingerprint);
    if (index < 0) {
      _records.add(alert);
      return;
    }
    _records[index] = alert;
  }

  @override
  Future<AlertRecord?> alertByFingerprint(String fingerprint) async {
    for (final record in _records) {
      if (record.fingerprint == fingerprint) return record;
    }
    return null;
  }

  @override
  Future<List<AlertRecord>> alerts({
    AlertStatus? status,
    String? hazard,
    DateTime? since,
    int? limit,
  }) async {
    if (failLoads) throw StateError('boom');
    final result = <AlertRecord>[];
    for (final record in _records) {
      if (status != null && record.status != status) continue;
      if (hazard != null && record.hazard != hazard) continue;
      if (since != null && record.detectedAtUtc.isBefore(since)) continue;
      result.add(record);
    }
    result.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    if (limit != null && result.length > limit) {
      return result.sublist(0, limit);
    }
    return result;
  }

  @override
  Future<List<AlertRecord>> activeAlerts({int? limit}) async {
    final active = _records.where((r) => r.isActive).toList()
      ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    if (limit != null && active.length > limit) {
      return active.sublist(0, limit);
    }
    return active;
  }

  @override
  Future<void> updateStatus(String fingerprint, AlertStatus status) async {
    final index = _records.indexWhere((r) => r.fingerprint == fingerprint);
    if (index < 0) return;
    _records[index] =
        _records[index].copyWith(status: status, updatedAtUtc: _kFixedTimestamp);
  }

  @override
  Future<void> markResolved(String fingerprint, {DateTime? at}) async {
    final index = _records.indexWhere((r) => r.fingerprint == fingerprint);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(
      status: AlertStatus.resolved,
      updatedAtUtc: at ?? _kFixedTimestamp,
      resolvedAtUtc: at ?? _kFixedTimestamp,
    );
  }

  @override
  Future<void> markAcknowledged(String fingerprint) async {
    final index = _records.indexWhere((r) => r.fingerprint == fingerprint);
    if (index < 0) return;
    _records[index] = _records[index].copyWith(acknowledged: true);
  }

  @override
  Future<int> purgeOlderThan(DateTime cutoff) async {
    final before = _records.length;
    _records.removeWhere((r) => r.detectedAtUtc.isBefore(cutoff));
    return before - _records.length;
  }

  @override
  Future<void> clear() async => _records.clear();
}

/// A monitored-location record with deterministic timestamps and ids.
MonitoredLocationRecord sampleLocation({
  int? id,
  String name = 'Testville',
  double latitude = 1.0,
  double longitude = 2.0,
  bool isPrimary = false,
}) {
  return MonitoredLocationRecord(
    id: id,
    name: name,
    latitude: latitude,
    longitude: longitude,
    isPrimary: isPrimary,
    createdAtUtc: _kFixedTimestamp,
    updatedAtUtc: _kFixedTimestamp,
  );
}

/// A deterministic [WeatherBundle] for pipeline tests.
///
/// Defaults to benign conditions; add [hourly] thunderstorm/rain points or a
/// gust to trigger specific hazards via the real analysis engine.
WeatherBundle sampleBundle({
  String locationKey = '1.0,2.0',
  DateTime? atUtc,
  double temperatureC = 18,
  int weatherCode = 2,
  double gustKmh = 0,
  List<HourlyForecastPoint> hourly = const [],
}) {
  final at = atUtc ?? _kFixedTimestamp;
  return WeatherBundle(
    locationKey: locationKey,
    current: CurrentWeather(
      observedAtUtc: at,
      temperatureC: temperatureC,
      apparentTemperatureC: temperatureC,
      weatherCode: weatherCode,
      windGustsKmh: gustKmh > 0 ? gustKmh : null,
      windSpeedKmh: gustKmh,
    ),
    hourly: [...hourly],
    daily: [
      DailyForecastPoint(
        dateUtc: at,
        weatherCode: weatherCode,
        temperatureMaxC: temperatureC + 2,
        temperatureMinC: temperatureC - 2,
        precipitationSumMm: 0,
      ),
    ],
    fetchedAtUtc: at,
    expiresAtUtc: at.add(const Duration(minutes: 30)),
  );
}

/// An hourly forecast point that triggers the thunderstorm hazard (WMO 95).
HourlyForecastPoint thunderHourlyPoint(DateTime atUtc, {double windKmh = 10}) =>
    HourlyForecastPoint(
      timeUtc: atUtc.add(const Duration(hours: 1)),
      temperatureC: 22,
      weatherCode: 95,
      windSpeedKmh: windKmh,
    );

/// An hourly forecast point that triggers the high-wind hazard (WMO 3).
HourlyForecastPoint windyHourlyPoint(DateTime atUtc) => HourlyForecastPoint(
      timeUtc: atUtc.add(const Duration(hours: 2)),
      temperatureC: 16,
      weatherCode: 3,
      windSpeedKmh: 85,
    );

/// A [ProviderContainer] wired with in-memory fakes so the full dashboard
/// pipeline can run on host without a database or network.
ProviderContainer makePipelineContainer({
  FakeWeatherService? weather,
  FakeLocationService? location,
  FakeGeocodingService? geocoding,
  InMemoryMonitoredLocations? locations,
  InMemoryAlertHistory? alerts,
}) {
  return ProviderContainer(
    overrides: [
      weatherServiceProvider.overrideWithValue(
        weather ?? FakeWeatherService(),
      ),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      geocodingServiceProvider.overrideWithValue(
        geocoding ?? FakeGeocodingService(),
      ),
      monitoredLocationRepositoryProvider.overrideWithValue(
        locations ?? InMemoryMonitoredLocations(),
      ),
      alertHistoryRepositoryProvider.overrideWithValue(
        alerts ?? InMemoryAlertHistory(),
      ),
    ],
  );
}

/// Deterministic [NotificationService] fake for pipeline tests.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({
    NotificationPermissionStatus? permission,
    bool? permissionGranted,
  }) : permission = permission ??
            ((permissionGranted ?? true)
                ? NotificationPermissionStatus.granted
                : NotificationPermissionStatus.denied) {
    this.permissionGranted =
        this.permission == NotificationPermissionStatus.granted;
  }

  /// Backward-compatible granted/denied knob for existing pipeline tests.
  late bool permissionGranted;

  /// Resolved OS permission surfaced via [permissionStatus] to the settings
  /// UI and the dashboard permission prompt.
  NotificationPermissionStatus permission;

  bool requestPermissionCalled = false;
  bool openSystemSettingsCalled = false;

  /// Every alert delivered, in order.
  final List<({String title, String body, String payload})> shown = [];

  int get showCount => shown.length;

  /// When true, the next [requestPermission] grants and flips [permission].
  bool grantOnRequest = false;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalled = true;
    if (grantOnRequest) {
      permission = NotificationPermissionStatus.granted;
      permissionGranted = true;
      return true;
    }
    final granted = permission == NotificationPermissionStatus.granted;
    permissionGranted = granted;
    return granted;
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => permission;

  @override
  Future<void> openSystemSettings() async {
    openSystemSettingsCalled = true;
  }

  @override
  Future<void> showAlert({
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add((title: title, body: body, payload: payload));
  }

  @override
  Stream<String> onOpenedPayloads() => const Stream.empty();
}

/// In-memory [NotificationStateRepository] honoring cooldown semantics.
class InMemoryNotificationState implements NotificationStateRepository {
  InMemoryNotificationState({
    Map<String, NotificationStateRecord> seed = const {},
  }) : _records = {...seed};

  final Map<String, NotificationStateRecord> _records;

  int get recordCount => _records.length;

  /// When set, reads throw so implementations can exercise error paths.
  bool failLoads = false;

  @override
  Future<NotificationStateRecord?> recordFor(String fingerprint) async {
    if (failLoads) throw StateError('boom');
    return _records[fingerprint];
  }

  @override
  Future<void> recordNotification(
    String fingerprint, {
    DateTime? at,
    String status = 'sent',
  }) async {
    if (failLoads) throw StateError('boom');
    final now = (at ?? DateTime.now().toUtc()).toUtc();
    final existing = _records[fingerprint];
    _records[fingerprint] = NotificationStateRecord(
      fingerprint: fingerprint,
      lastNotifiedAtUtc: now,
      notificationCount: (existing?.notificationCount ?? 0) + 1,
      status: status,
      updatedAtUtc: now,
    );
  }

  @override
  Future<bool> shouldNotify(
    String fingerprint,
    Duration cooldown, {
    DateTime? now,
  }) async {
    if (failLoads) throw StateError('boom');
    final existing = _records[fingerprint];
    if (existing == null) return true;
    final reference = (now ?? DateTime.now().toUtc()).toUtc();
    return existing.lastNotifiedAtUtc.isBefore(reference.subtract(cooldown));
  }

  @override
  Future<List<NotificationStateRecord>> recent(DateTime since) async {
    final result = _records.values
        .where((record) {
          final updated = record.updatedAtUtc ?? record.lastNotifiedAtUtc;
          return updated.isAfter(since);
        })
        .toList()
      ..sort((a, b) {
        final at = a.updatedAtUtc ?? a.lastNotifiedAtUtc;
        final bt = b.updatedAtUtc ?? b.lastNotifiedAtUtc;
        return bt.compareTo(at);
      });
    return result;
  }

  @override
  Future<int> purgeOlderThan(DateTime cutoff) async {
    final before = _records.length;
    _records.removeWhere((_, record) {
      final updated = record.updatedAtUtc ?? record.lastNotifiedAtUtc;
      return updated.isBefore(cutoff);
    });
    return before - _records.length;
  }
}

/// In-memory [PreferenceRepository] fake.
class InMemoryPreferences implements PreferenceRepository {
  final Map<String, String> _values = {};

  /// When set, reads throw so implementations can exercise error paths.
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('boom');
    return _values[key];
  }

  @override
  Future<UserPreference?> get(String key) async {
    final value = _values[key];
    if (value == null) return null;
    return UserPreference(
      key: key,
      value: value,
      updatedAtUtc: _kFixedTimestamp,
    );
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<List<UserPreference>> all() async => [
        for (final entry in _values.entries)
          UserPreference(
            key: entry.key,
            value: entry.value,
            updatedAtUtc: _kFixedTimestamp,
          ),
      ];
}

/// Waits (with a bounded retry loop) until [predicate] becomes true.
Future<void> pumpUntil(
  bool Function() predicate, {
  int attempts = 100,
  Duration delay = const Duration(milliseconds: 5),
}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return;
    await Future<void>.delayed(delay);
  }
  throw StateError('condition was never met within $attempts attempts');
}