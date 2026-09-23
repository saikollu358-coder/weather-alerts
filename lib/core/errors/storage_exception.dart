import 'app_exception.dart';

/// Raised when the local SQLite database cannot be opened or created,
/// including the case where the platform does not provide SQLite (web).
class DatabaseOpenException extends AppException {
  const DatabaseOpenException({
    super.message = 'Local storage is not available on this device.',
    super.cause,
  });
}

/// Raised when a write/transaction against local storage fails.
class StorageWriteException extends AppException {
  const StorageWriteException({
    super.message = 'Could not save local data.',
    super.cause,
  });
}

/// Raised when reading from local storage fails.
class StorageReadException extends AppException {
  const StorageReadException({
    super.message = 'Could not read local data.',
    super.cause,
  });
}