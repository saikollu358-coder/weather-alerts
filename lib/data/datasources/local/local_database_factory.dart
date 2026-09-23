import 'local_database.dart';
import 'local_database_unavailable.dart'
    if (dart.library.io) 'local_database_io.dart';

/// Creates the platform-appropriate [LocalDatabase].
///
/// - iOS/Android/desktop (`dart.library.io` available): sqflite-backed.
/// - Web: a graceful unavailable implementation (SQLite needs a native
///   backend; web storage is accepted as a documented limitation).
///
/// Pass [databasePath] to pin the database file (used by tests/FFI).
LocalDatabase createPlatformLocalDatabase({String? databasePath}) =>
    createLocalDatabase(databasePath: databasePath);