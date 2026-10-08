/// Lenient readers for API JSON.
///
/// A strict `as bool?` or `as int` cast turns one unexpected value into a
/// TypeError that fails the whole payload, and with it the whole screen. The
/// server does send shapes that trip strict casts: a habit's chain day carries
/// `completed`/`possible` as integer counts on a partial day of a multi-count
/// habit (meridian `Habit#chain_entry_for`), where a reader expecting flags
/// crashed. So every model reads its numbers and flags through these, which
/// accept a JSON number, a boolean or a numeric string, and fall back instead
/// of throwing. Only a record's own `id` stays strict ([readId]): a row with no
/// id is not a row the app can act on.
library;

/// An integer from a number (`3`, `3.0`), a flag (`true` → 1) or a numeric
/// string; [fallback] for anything else, including null.
int readInt(Object? value, {int fallback = 0}) =>
    readIntOrNull(value) ?? fallback;

int? readIntOrNull(Object? value) => switch (value) {
      int() => value,
      double() => value.isFinite ? value.toInt() : null,
      bool() => value ? 1 : 0,
      String() =>
        int.tryParse(value.trim()) ?? _finite(double.tryParse(value.trim())),
      _ => null,
    };

/// A double from a number, a flag or a numeric string; [fallback] otherwise.
double readDouble(Object? value, {double fallback = 0}) =>
    readDoubleOrNull(value) ?? fallback;

double? readDoubleOrNull(Object? value) => switch (value) {
      num() => value.toDouble(),
      bool() => value ? 1 : 0,
      String() => double.tryParse(value.trim()),
      _ => null,
    };

/// A flag from a boolean, a count (non-zero is true) or a `"true"`/`"1"`
/// string; [fallback] for anything else, including null.
bool readBool(Object? value, {bool fallback = false}) =>
    readBoolOrNull(value) ?? fallback;

bool? readBoolOrNull(Object? value) => switch (value) {
      bool() => value,
      num() => value != 0,
      String() => switch (value.trim().toLowerCase()) {
          'true' || 't' || '1' || 'yes' => true,
          'false' || 'f' || '0' || 'no' => false,
          _ => null,
        },
      _ => null,
    };

/// A record id. Tolerates `12.0` and `"12"`, but a missing or unreadable id
/// is malformed data and throws a [FormatException].
int readId(Object? value) =>
    readIntOrNull(value) ?? (throw FormatException('Missing or invalid id', value));

int? _finite(double? value) =>
    value != null && value.isFinite ? value.toInt() : null;
