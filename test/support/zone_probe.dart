/// Checks that the app's dates and times follow the account's time zone
/// whatever zone the Dart VM — the phone — is in.
///
/// test/data/current_day_test.dart starts it in a second VM with `TZ` set to
/// zones far from the account's (Istanbul, +03:00): the test VM keeps the
/// machine's own zone, which may be the account's, and then these checks
/// would prove nothing.
///
/// Prints a line per check, `ok …` or `FAIL …`. Exits with 1 when a check
/// failed.
library;

import 'dart:io';

import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/models/date_utils.dart';

void main() {
  var failed = false;
  void check(String what, bool ok) {
    stdout.writeln(
      '${ok ? 'ok' : 'FAIL'} $what '
      '(device ${DateTime.now().timeZoneName})',
    );
    if (!ok) failed = true;
  }

  const istanbul = Duration(hours: 3);

  // A todo due 01:00 on the 5th, Istanbul time, is due on the 5th at 01:00.
  final due = parseDateTime('2026-10-05T01:00:00.000+03:00')!;
  check('wall clock day', due.day == 5);
  check('wall clock time', formatTime(due) == '01:00');

  // 22:30 UTC on the 4th is the 5th in Istanbul.
  final now = DateTime.utc(2026, 10, 4, 22, 30);
  final today = dayIn(now, istanbul);
  check('account day', today == DateTime(2026, 10, 5));

  // With the app's today set to the account's, the todo is due "today".
  setAppToday(today);
  check('relative day', dayDelta(due) == 0);
  check('yesterday', dayDelta(DateTime(2026, 10, 4)) == -1);

  // It is 01:30 on the 5th in Istanbul: the timer waits for Istanbul's
  // next midnight, 22 h 30 min away (+1 s).
  check(
    'midnight timer',
    untilNextDayIn(now, istanbul) ==
        const Duration(hours: 22, minutes: 30, seconds: 1),
  );

  exitCode = failed ? 1 : 0;
}
