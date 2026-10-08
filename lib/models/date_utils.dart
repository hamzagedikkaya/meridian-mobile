/// yyyy-MM-dd — the wire format for date-only fields and query params.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `2026-10-04`, `2026-10-04T18:00`, `2026-10-04T18:00:00.000+03:00`, … —
/// the date and clock time as written, then whatever offset follows.
final _wallClock = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d{1,9}))?)?)?'
  r'(?:Z|[+-]\d{2}(?::?\d{2})?)?$',
  caseSensitive: false,
);

/// A date or datetime from the API, as the account's wall clock.
///
/// The server writes every datetime with the account's UTC offset
/// (`"2026-10-04T18:00:00.000+03:00"`, contract G1.1), so the date and time
/// written there *are* the account's local date and time — on the right side
/// of a daylight-saving change too, since each value carries its own offset.
/// They are read as written into a local [DateTime], and the offset is
/// dropped: "18:00", "Bugün" and the day a todo is due read the same as on
/// the web, whatever zone this phone is in. (Converting with `toLocal()`
/// would show the device's zone instead, which disagrees with the server's
/// "today" whenever the two zones differ.) A date-only value is that day at
/// 00:00. A server from before G1 wrote wall-clock times with a `Z`; read as
/// written, they show right as well.
///
/// The result is meant for showing and for sending back as wall-clock time
/// (the server reads a datetime without an offset in the account's zone). It
/// is an instant only while the phone is in the account's zone. Null for null
/// and for a value that is not a date.
DateTime? parseDateTime(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  final m = _wallClock.firstMatch(text);
  if (m == null) return DateTime.tryParse(text)?.toLocal();
  int part(int group) => int.parse(m.group(group) ?? '0');
  final fraction = (m.group(7) ?? '').padRight(6, '0');
  return DateTime(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
    int.parse(fraction.substring(0, 3)),
    int.parse(fraction.substring(3, 6)),
  );
}

/// [time]'s local calendar date at 00:00.
DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

/// `"+03:00"`, `"-05:30"`, `"+0300"` or `"Z"` → the offset; null otherwise.
Duration? parseUtcOffset(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text == 'Z' || text == 'z') return Duration.zero;
  final m = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(text);
  if (m == null) return null;
  final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  if (minutes > 18 * 60) return null;
  return Duration(minutes: m.group(1) == '-' ? -minutes : minutes);
}

/// `+03:00`, `-05:30`, `+00:00`.
String formatUtcOffset(Duration offset) {
  final minutes = offset.inMinutes.abs();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  return '${offset.isNegative ? '-' : '+'}$hh:$mm';
}

/// The wall clock at [now] in a zone [offset] from UTC, as a UTC [DateTime]
/// whose fields are that wall clock (so no daylight-saving rule of this
/// device can bend it).
DateTime _wallAt(DateTime now, Duration offset) => now.toUtc().add(offset);

/// The calendar date at [now] in the zone [offset] from UTC — the account's
/// "today" — at 00:00 local. Null [offset] means this device's own zone.
DateTime dayIn(DateTime now, Duration? offset) {
  if (offset == null) return dateOnly(now);
  final wall = _wallAt(now, offset);
  return DateTime(wall.year, wall.month, wall.day);
}

/// How long from [now] until the next local midnight, plus one second so the
/// timer never fires a hair before the date has changed (if it ever does,
/// `CurrentDay.sync` simply re-arms).
///
/// Measured between real instants, so a 23- or 25-hour daylight-saving day
/// comes out right, and so does a zone whose clocks change at midnight
/// itself (the day then starts at 01:00). Clamped to 1 s … 26 h so a clock
/// that jumps around can neither spin the timer nor park it for days.
///
/// Kept free of Flutter: test/data/current_day_test.dart runs it in a plain
/// Dart VM under time zones that have daylight saving.
Duration untilNextDay(DateTime now) {
  final next = DateTime(now.year, now.month, now.day + 1);
  return _clamped(next.difference(now) + const Duration(seconds: 1));
}

/// [untilNextDay] for the zone [offset] from UTC: until the next midnight
/// there. Null [offset] means this device's own zone.
///
/// The offset is the one in effect now, so if the account's zone changes
/// its clocks before that midnight the timer is an hour early or late. An
/// early one finds the same date and re-arms; a late one rolls the day over
/// an hour late, and the app's resume check (or the next `/me`, which
/// brings the new offset) catches up sooner.
Duration untilNextDayIn(DateTime now, Duration? offset) {
  if (offset == null) return untilNextDay(now);
  final wall = _wallAt(now, offset);
  final next = DateTime.utc(wall.year, wall.month, wall.day + 1);
  return _clamped(next.difference(wall) + const Duration(seconds: 1));
}

Duration _clamped(Duration wait) {
  if (wait < const Duration(seconds: 1)) return const Duration(seconds: 1);
  if (wait > const Duration(hours: 26)) return const Duration(hours: 26);
  return wait;
}
