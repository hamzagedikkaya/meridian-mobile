/// yyyy-MM-dd — the wire format for date-only fields and query params.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parse a date-only ("2026-05-25") or datetime ("…T00:00:00.000Z") string.
DateTime? parseDateTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
