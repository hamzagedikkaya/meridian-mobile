/// Checks `untilNextDay` around daylight-saving changes, in the time zone of
/// the Dart VM that runs it.
///
/// test/data/current_day_test.dart starts it in a second VM with `TZ` set to
/// a zone that changes its clocks: the test VM keeps the machine's own zone,
/// which may never change (Türkiye's has not since 2016), so checks run there
/// would not cover daylight saving at all.
///
/// Arguments: days on which the zone changes its clocks, as yyyy-mm-dd.
/// Prints a line per check, `ok …` or `FAIL …`, and `nodst <day>` when the
/// zone does not change on that day (an unknown zone name means UTC). Exits
/// with 1 when a check failed.
library;

import 'dart:io';

import 'package:meridian_mobile/models/date_utils.dart';

void main(List<String> days) {
  var failed = false;
  for (final day in days) {
    final date = DateTime.parse(day);
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day + 1);
    if (start.timeZoneOffset == end.timeZoneOffset) {
      stdout.writeln('nodst $day');
      failed = true;
      continue;
    }
    for (final (hour, minute, second) in const [
      (0, 0, 0),
      (0, 30, 0),
      (1, 30, 0),
      (2, 30, 0),
      (3, 30, 0),
      (12, 0, 0),
      (23, 0, 0),
      (23, 30, 0),
      (23, 59, 59),
    ]) {
      final now =
          DateTime(date.year, date.month, date.day, hour, minute, second);
      final wait = untilNextDay(now);
      final at = now.add(wait);
      final nextDay = DateTime(now.year, now.month, now.day + 1);
      final ok = dateOnly(at) == dateOnly(nextDay) &&
          at.isAfter(nextDay) &&
          at.difference(nextDay) <= const Duration(seconds: 1);
      stdout.writeln('${ok ? 'ok' : 'FAIL'} $now ${now.timeZoneName} '
          '+$wait -> $at ${at.timeZoneName}');
      if (!ok) failed = true;
    }
  }
  exitCode = failed ? 1 : 0;
}
