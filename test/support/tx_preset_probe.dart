/// Checks İşlemler's "Son 30 gün" around daylight-saving changes, in the time
/// zone of the Dart VM that runs it (test/screens/tx_date_presets_test.dart
/// starts it with `TZ` set to a zone that changes its clocks).
///
/// Arguments: days to stand on, as yyyy-mm-dd. Prints `ok …` or `FAIL …` per
/// day; exits with 1 when one failed.
library;

import 'dart:io';

import 'package:meridian_mobile/ui/screens/finance/date_presets.dart';

void main(List<String> days) {
  var failed = false;
  for (final day in days) {
    final date = DateTime.parse(day);
    final today = DateTime(date.year, date.month, date.day);
    final range = txDatePreset('30d', today)!;
    final from = range.from;
    final calendar = DateTime.utc(date.year, date.month, date.day - 30);
    final ok = from.year == calendar.year &&
        from.month == calendar.month &&
        from.day == calendar.day &&
        from.hour == 0;
    stdout.writeln('${ok ? 'ok' : 'FAIL'} $today -> $from');
    if (!ok) failed = true;
  }
  exitCode = failed ? 1 : 0;
}
