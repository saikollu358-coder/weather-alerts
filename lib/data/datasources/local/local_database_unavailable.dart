import 'package:sqflite_common/sqlite_api.dart';

import 'local_database.dart';

/// Browser-safe fallback for platforms without native SQLite support.
///
/// Instead of failing the entire app, the web build keeps a lightweight
/// in-memory table store so the dashboard, preferences, and cached records can
/// still initialize and render normally while running in the browser.
class UnavailableLocalDatabase implements LocalDatabase {
  const UnavailableLocalDatabase();

  static final Map<String, List<Map<String, Object?>>> _tables = {};

  @override
  bool get isAvailable => true;

  @override
  String get databasePath => 'memory://weather_alerts';

  @override
  Future<void> ensureOpen() async {
    _tables.putIfAbsent('cached_weather', () => <Map<String, Object?>>[]);
    _tables.putIfAbsent('cached_forecast', () => <Map<String, Object?>>[]);
    _tables.putIfAbsent('alert_history', () => <Map<String, Object?>>[]);
    _tables.putIfAbsent('user_preferences', () => <Map<String, Object?>>[]);
    _tables.putIfAbsent('notification_state', () => <Map<String, Object?>>[]);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(DatabaseOperations ops) action,
  ) async {
    await ensureOpen();
    return action(_MemoryOperations(this));
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    String? groupBy,
    String? having,
    int? limit,
    int? offset,
  }) async {
    await ensureOpen();
    final rows = List<Map<String, Object?>>.from(_tables[table] ?? const []);
    final filtered = _applyWhere(rows, where, whereArgs);
    final ordered = _applyOrder(filtered, orderBy);
    final from = offset ?? 0;
    final to = limit == null
        ? ordered.length
        : (from + limit).clamp(0, ordered.length);
    final slice = ordered.skip(from).take(to - from).toList(growable: false);
    return slice
        .map((row) {
          if (columns == null || columns.isEmpty) return row;
          final selected = <String, Object?>{};
          for (final column in columns) {
            selected[column] = row[column];
          }
          return selected;
        })
        .toList(growable: false);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) async {
    await ensureOpen();
    final rows = _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);
    final row = Map<String, Object?>.from(values);

    final idKey = values.containsKey('id') ? 'id' : null;
    if (idKey != null && row[idKey] != null) {
      final idx = rows.indexWhere(
        (candidate) => candidate[idKey] == row[idKey],
      );
      if (idx >= 0) {
        if (conflictAlgorithm == ConflictAlgorithm.replace) {
          rows[idx] = row;
          return (row[idKey] as num).toInt();
        }
        if (conflictAlgorithm == ConflictAlgorithm.abort) {
          throw StateError('Duplicate row for $table on $idKey=${row[idKey]}');
        }
      }
    }

    final candidateId = values['id'];
    if (candidateId is int && candidateId > 0) {
      rows.add(row);
      return candidateId;
    }

    final generatedId = _nextId();
    rows.add({...row, 'id': generatedId});
    return generatedId;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await ensureOpen();
    final rows = _tables[table] ?? const <Map<String, Object?>>[];
    final toUpdate = _applyWhere(
      rows.toList(growable: false),
      where,
      whereArgs,
    );
    for (final row in toUpdate) {
      final index = rows.indexOf(row);
      if (index >= 0) {
        rows[index] = {...row, ...values};
      }
    }
    return toUpdate.length;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    await ensureOpen();
    final rows = _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);
    final toDelete = _applyWhere(
      rows.toList(growable: false),
      where,
      whereArgs,
    );
    for (final row in toDelete) {
      rows.remove(row);
    }
    return toDelete.length;
  }

  @override
  Future<bool> tableExists(String table) async {
    await ensureOpen();
    return _tables.containsKey(table);
  }

  @override
  Future<void> close() async {
    _tables.clear();
    await ensureOpen();
  }

  @override
  Future<void> deleteDatabase() async {
    _tables.clear();
    await ensureOpen();
  }

  int _nextId() => _tables.values
      .expand((rows) => rows)
      .map((row) => row['id'])
      .whereType<int>()
      .fold<int>(1, (maxId, value) => value >= maxId ? value + 1 : maxId);

  List<Map<String, Object?>> _applyWhere(
    List<Map<String, Object?>> rows,
    String? where,
    List<Object?>? whereArgs,
  ) {
    if (where == null || where.isEmpty) return rows;

    final args = whereArgs ?? const <Object?>[];
    final tokens = where.split(RegExp(r'\s+AND\s+|\s+OR\s+'));
    return rows
        .where((row) {
          var matched = true;
          for (final token in tokens) {
            final normalized = token.trim();
            if (normalized.isEmpty) continue;
            final condition = _parseCondition(normalized, args);
            matched = matched && condition(row);
          }
          return matched;
        })
        .toList(growable: false);
  }

  bool Function(Map<String, Object?> row) _parseCondition(
    String expression,
    List<Object?> args,
  ) {
    final regex = RegExp(
      r'^(.*?)(=|!=|>=|<=|>|<|LIKE|IS\s+NULL|IS\s+NOT\s+NULL)\s*(\?|.*)$',
      caseSensitive: false,
    );
    final match = regex.firstMatch(expression);
    if (match == null) {
      return (_) => true;
    }

    final left = match.group(1)!.trim();
    final op = match.group(2)!.toUpperCase();
    final rightText = match.group(3)!.trim();

    final rightValue = rightText == '?'
        ? _consumeArg(args)
        : _parseValue(rightText);
    final leftValue = _resolveFieldValue(left);

    switch (op) {
      case '=':
        return (row) => _coerce(row[leftValue]) == _coerce(rightValue);
      case '!=':
        return (row) => _coerce(row[leftValue]) != _coerce(rightValue);
      case '>':
        return (row) => _compare(row[leftValue], rightValue) > 0;
      case '<':
        return (row) => _compare(row[leftValue], rightValue) < 0;
      case '>=':
        return (row) => _compare(row[leftValue], rightValue) >= 0;
      case '<=':
        return (row) => _compare(row[leftValue], rightValue) <= 0;
      case 'LIKE':
        return (row) => (_toString(
          row[leftValue],
        )).contains(_toString(rightValue).replaceAll('%', ''));
      case 'IS NULL':
        return (row) => row[leftValue] == null;
      case 'IS NOT NULL':
        return (row) => row[leftValue] != null;
      default:
        return (_) => true;
    }
  }

  Object? _consumeArg(List<Object?> args) {
    if (args.isEmpty) return null;
    return args.removeAt(0);
  }

  dynamic _resolveFieldValue(String raw) => raw.replaceAll('`', '').trim();

  dynamic _parseValue(String raw) {
    final value = raw.trim();
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    if (value == 'NULL') return null;
    return int.tryParse(value) ?? double.tryParse(value) ?? value;
  }

  List<Map<String, Object?>> _applyOrder(
    List<Map<String, Object?>> rows,
    String? orderBy,
  ) {
    if (orderBy == null || orderBy.isEmpty) return rows;
    final column = orderBy.split(' ').first.replaceAll('`', '').trim();
    final descending = orderBy.toUpperCase().contains(' DESC');
    final data = List<Map<String, Object?>>.from(rows);
    data.sort((a, b) {
      final av = a[column];
      final bv = b[column];
      final comparison = _compare(av, bv);
      return descending ? -comparison : comparison;
    });
    return data;
  }

  int _compare(Object? a, Object? b) {
    final left = _coerce(a);
    final right = _coerce(b);
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is DateTime && right is DateTime) {
      return left.compareTo(right);
    }
    return _toString(left).compareTo(_toString(right));
  }

  Object? _coerce(Object? value) =>
      value is int || value is double || value is String || value == null
      ? value
      : value.toString();

  String _toString(Object? value) => value == null ? '' : value.toString();
}

class _MemoryOperations implements DatabaseOperations {
  _MemoryOperations(this._database);

  final UnavailableLocalDatabase _database;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    String? groupBy,
    String? having,
    int? limit,
    int? offset,
  }) => _database.query(
    table,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    orderBy: orderBy,
    groupBy: groupBy,
    having: having,
    limit: limit,
    offset: offset,
  );

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) => _database.insert(table, values, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) => _database.update(table, values, where: where, whereArgs: whereArgs);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _database.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    // Not used by the app; kept for API compatibility.
    await _database.ensureOpen();
    if (sql.toUpperCase().contains('CREATE TABLE')) {
      final tableName = _extractTableName(sql);
      if (tableName.isNotEmpty) {
        UnavailableLocalDatabase._tables.putIfAbsent(
          tableName,
          () => <Map<String, Object?>>[],
        );
      }
    }
  }

  String _extractTableName(String sql) {
    final match = RegExp(
      r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_]+)',
      caseSensitive: false,
    ).firstMatch(sql);
    return match?.group(1) ?? '';
  }
}

/// Creates the platform-local [LocalDatabase] (web: memory-backed fallback).
LocalDatabase createLocalDatabase({String? databasePath}) =>
    const UnavailableLocalDatabase();
