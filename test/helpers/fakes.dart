import 'dart:async';

import 'package:weather_alerts/core/errors/app_exception.dart';
import 'package:weather_alerts/domain/entities/auth_user.dart';
import 'package:weather_alerts/domain/repositories/auth_repository.dart';
import 'package:weather_alerts/domain/services/auth_service.dart';
import 'package:weather_alerts/services/firebase/cloud_data_store.dart';

/// Deterministic [AuthRepository] fake for tests.
///
/// Drives [watchAuthState] from an in-memory broadcast controller and can be
/// configured to fail login/registration/reset requests.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AuthUser? user,
    this.loginError,
    this.registerError,
    this.resetError,
  }) : _current = user;

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  // Deliberately Object? so tests can simulate arbitrary failure types.
  Object? loginError;
  Object? registerError;
  Object? resetError;
  Object? updateProfileError;

  AuthUser? _current;

  /// Emits a new auth state to listeners.
  void emit(AuthUser? user) {
    _current = user;
    _controller.add(user);
  }

  /// Closes the stream (call in tearDown).
  Future<void> dispose() => _controller.close();

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> watchAuthState() => _controller.stream;

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final error = loginError;
    if (error != null) throw error;
    emit(_current);
    return _current!;
  }

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final error = registerError;
    if (error != null) throw error;
    emit(_current);
    return _current!;
  }

  @override
  Future<void> logout() async => emit(null);

  @override
  Future<AuthUser> updateProfile({required String name}) async {
    final error = updateProfileError;
    if (error != null) throw error;
    final current = _current;
    if (current == null) throw StateError('no signed-in user');
    final updated = AuthUser(
      uid: current.uid,
      name: name.trim(),
      email: current.email,
      createdAt: current.createdAt,
      isLocalGuest: current.isLocalGuest,
    );
    _current = updated;
    _controller.add(updated);
    return updated;
  }

  @override
  Future<void> resetPassword({required String email}) async {
    final error = resetError;
    if (error != null) throw error;
  }
}

/// Deterministic [AuthService] fake for repository-level tests.
class FakeAuthService implements AuthService {
  FakeAuthService({this.available = true, this.user});

  bool available;
  AuthUser? user;
  Object? updateError;
  int updateCalls = 0;
  String? lastUpdatedName;

  @override
  bool get isAvailable => available;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> watchAuthState() => Stream.value(user);

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async => user!;

  @override
  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
  }) async => user!;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> updateProfile({required String name}) async {
    updateCalls++;
    lastUpdatedName = name.trim();
    final error = updateError;
    if (error != null) throw error;
    final current = user!;
    final updated = AuthUser(
      uid: current.uid,
      name: name.trim(),
      email: current.email,
      createdAt: current.createdAt,
      isLocalGuest: current.isLocalGuest,
    );
    user = updated;
    return updated;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {}
}

/// In-memory [CloudDataStore] for tests exercising cloud read/write paths.
class InMemoryCloudDataStore implements CloudDataStore {
  final Map<String, Map<String, Map<String, dynamic>>> _data = {};
  bool available = true;
  bool failNextWrite = false;

  Map<String, dynamic> _docs(String ownerId, String collection) =>
      _data.putIfAbsent(ownerId, () => {}).putIfAbsent(collection, () => {});

  /// The raw document map for [ownerId]/[collection] (for assertions).
  Map<String, dynamic> docs(String ownerId, String collection) =>
      _docs(ownerId, collection);

  @override
  bool get isAvailable => available;

  @override
  Future<void> deleteDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  }) async {
    _docs(ownerId, collection).remove(documentId);
  }

  @override
  Future<Map<String, dynamic>?> getDocument({
    required String ownerId,
    required String collection,
    required String documentId,
  }) async => Map<String, dynamic>.from(
    _docs(ownerId, collection)[documentId] ?? const {},
  );

  @override
  Future<List<CloudDoc>> queryData({
    required String ownerId,
    required String collection,
  }) async {
    return [
      for (final e in _docs(ownerId, collection).entries)
        CloudDoc(id: e.key, data: Map<String, dynamic>.from(e.value)),
    ];
  }

  @override
  Future<void> setDocument({
    required String ownerId,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FirebaseOperationException(
        code: 'test',
        message: 'forced sync write failure',
      );
    }
    final bucket = _docs(ownerId, collection);
    final merged = merge
        ? {...bucket[documentId] ?? const <String, dynamic>{}, ...data}
        : data;
    bucket[documentId] = merged;
  }
}
