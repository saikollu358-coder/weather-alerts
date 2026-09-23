/// Helpers for parsing Open-Meteo JSON payloads into typed weather models.
library;

/// [value] coerced to a double, or null when absent / not a number.
double? asDouble(Object? value) => value is num ? value.toDouble() : null;

/// [value] coerced to an int, or null when absent / not a number.
int? asInt(Object? value) => value is num ? value.toInt() : null;

/// [value] coerced to a string, or null when absent.
String? asString(Object? value) => value is String ? value : null;

/// [value] coerced to a bool; numbers and flags (e.g. `is_day`) also work.
bool asBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : (value is num ? value != 0 : fallback);

/// [value] as a list, or an empty list when absent.
List<dynamic> jsonList(Object? value) => value is List ? value : const [];

/// Element at [index] of [list] as an int?, or null when out of range/absent.
int? intAt(List<dynamic> list, int index) =>
    index < list.length ? (list[index] as num?)?.toInt() : null;

/// Element at [index] of [list] as a double?, or null when out of range/absent.
double? doubleAt(List<dynamic> list, int index) =>
    index < list.length ? (list[index] as num?)?.toDouble() : null;

/// Element at [index] of [list] as a String?, or null when out of range/absent.
String? stringAt(List<dynamic> list, int index) =>
    index < list.length ? (list[index] as String?) : null;

/// Parses an ISO-8601 instant, treating offset-less values as UTC.
///
/// [dateOnly] values (e.g. `2026-09-06`) become UTC midnight of that day.
/// Throws [FormatException] when the value cannot be parsed.
DateTime parseUtcInstant(String raw, {bool dateOnly = false}) {
  if (dateOnly) {
    final date = DateTime.tryParse(raw);
    if (date == null) throw FormatException('Invalid date: $raw');
    return DateTime.utc(date.year, date.month, date.day);
  }
  final value = raw.endsWith('Z') ? raw : '${raw}Z';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid instant: $raw');
  return parsed.toUtc();
}