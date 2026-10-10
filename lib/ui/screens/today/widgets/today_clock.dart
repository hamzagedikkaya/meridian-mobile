import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/current_day.dart';

/// The account's wall clock at [now]: the date and time the account's zone
/// (`utcOffset` from UTC) shows, as a local [DateTime] — the same footing
/// as the event and todo times `parseDateTime` reads, which are the
/// account's wall clock too. Null [utcOffset] (not known yet) is this
/// device's own clock.
DateTime accountWallClock(DateTime now, Duration? utcOffset) {
  if (utcOffset == null) return now;
  final wall = now.toUtc().add(utcOffset);
  return DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
}

/// The minute it is now on the account's wall clock ([accountWallClock]),
/// kept current: what Today's time-relative parts read — the next-up chip
/// ("09:30 · … · 25 dk", "Şimdi · …") and the Today card's fold of the
/// events already over ("+1 geçti").
///
/// One timer, armed to the next minute; it runs only while something
/// watches — and [watchTodayNow] watches only while Today's tab is shown.
final todayNowProvider = NotifierProvider.autoDispose<TodayNow, DateTime>(
  TodayNow.new,
);

class TodayNow extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    ref.watch(clockProvider);
    ref.watch(accountUtcOffsetProvider);
    return _read();
  }

  /// The minute now, re-arming the timer for the next one.
  DateTime _read() {
    final clock = ref.read(clockProvider);
    final now = accountWallClock(clock(), ref.read(accountUtcOffsetProvider));
    final minute = _minuteOf(now);
    // A hair past the minute, so the timer never wakes a moment before it.
    var wait =
        minute.add(const Duration(minutes: 1)).difference(now) +
        const Duration(milliseconds: 50);
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer?.cancel();
    _timer = Timer(wait, () => state = _read());
    return minute;
  }

  @override
  bool updateShouldNotify(DateTime previous, DateTime next) => previous != next;
}

/// [todayNowProvider] for a Today section: watched (so it moves with the
/// minutes) while its tab is shown; read once while it is not
/// ([TickerMode] off), so a hidden Today keeps no timer — showing it again
/// rebuilds it with the time then.
DateTime watchTodayNow(BuildContext context, WidgetRef ref) {
  if (TickerMode.valuesOf(context).enabled) return ref.watch(todayNowProvider);
  return _minuteOf(
    accountWallClock(
      ref.read(clockProvider)(),
      ref.read(accountUtcOffsetProvider),
    ),
  );
}

DateTime _minuteOf(DateTime t) =>
    DateTime(t.year, t.month, t.day, t.hour, t.minute);
