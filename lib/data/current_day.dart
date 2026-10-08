/// What day it is — the account's day, which is the server's.
///
/// The server computes "today" in the account's time zone (`user.timezone`,
/// contract G1.1): Today's habits, todos due today, the week's completion,
/// the journal's ranges, month totals. The phone's own zone can differ — a
/// trip abroad, a phone set to UTC — and then its date does too, for hours
/// around midnight. So the app counts days in the account's zone, from the
/// offset `/me` reports (`utc_offset`):
///
/// * every date-relative read model refetches at the account's midnight;
/// * "Bugün / Dün / Yarın" and other relative labels count from the
///   account's today ([appToday] in core/formats.dart, kept current here);
/// * datetimes from the server are shown as the account's wall clock (see
///   `parseDateTime`), so "18:00" means what it means on the web;
/// * new records default to the account's today;
/// * a "today" write sends the date the server reported (`/home`'s `today`,
///   `habit.today.date`), never the device's.
///
/// Only the greeting follows the phone's clock: it is about the person, not
/// the records. When the two zones differ, Today and Profile say which zone
/// the app is following (see [zoneMismatchProvider]). Until `/me` has
/// answered — the first second after launch — the device's zone stands in.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formats.dart';
import '../core/session.dart';
import '../models/date_utils.dart';

/// The clock everything date-relative reads. Overridden in tests to move time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The UTC offset of the account's time zone, as the server last reported
/// it; null until the signed-in user is known (or from a server that does
/// not report it), when the device's zone is used.
final accountUtcOffsetProvider = Provider<Duration?>(
  (ref) => ref.watch(currentUserProvider.select((user) => user?.utcOffset)),
);

/// Today's date in the account's time zone, at 00:00 local.
///
/// Every date-relative read model watches it (see `fetched` in
/// `providers.dart`), so crossing the account's midnight refetches today's
/// habits, todos, events, goal deadlines, budget pace and the journal ranges —
/// visible screens at once, hidden tabs the moment they are shown — and
/// repaints the "Today/Yesterday" labels. Screens keep showing the previous
/// day's data while the new day loads.
final currentDayProvider =
    NotifierProvider<CurrentDay, DateTime>(CurrentDay.new);

class CurrentDay extends Notifier<DateTime> {
  Timer? _timer;
  Duration? _offset;

  @override
  DateTime build() {
    ref.onDispose(_dispose);
    _offset = ref.watch(accountUtcOffsetProvider);
    final now = ref.watch(clockProvider)();
    _arm(now);
    final today = dayIn(now, _offset);
    setAppToday(today);
    return today;
  }

  /// Re-reads the clock. A timer cannot fire while the OS has the app
  /// suspended, so the app calls this whenever it comes back to the
  /// foreground: the day rolls over if midnight passed in the meantime, and
  /// the timer is re-armed from the real time either way. The phone's own
  /// zone is read again too — it may have changed while away (a flight).
  void sync() {
    final now = ref.read(clockProvider)();
    final today = dayIn(now, _offset);
    setAppToday(today);
    if (today != state) state = today;
    _arm(now);
    ref.invalidate(deviceUtcOffsetProvider);
  }

  void _arm(DateTime now) {
    _timer?.cancel();
    _timer = Timer(untilNextDayIn(now, _offset), sync);
  }

  void _dispose() {
    _timer?.cancel();
    _timer = null;
    // Labels go back to the device's date once nothing keeps the day.
    setAppToday(null);
  }
}

/// This device's UTC offset now. Overridden in tests to put the phone in
/// another zone.
final deviceUtcOffsetProvider = Provider<Duration>((ref) {
  // Re-read whenever the day is re-checked (midnight, every resume).
  ref.watch(currentDayProvider);
  return ref.read(clockProvider)().timeZoneOffset;
});

/// The account's zone and this device's, when they differ: the app follows
/// the account's (see the library comment), and says so. Null when they
/// agree, or while the account's zone is not known yet.
typedef ZoneMismatch = ({String zone, Duration account, Duration device});

final zoneMismatchProvider = Provider<ZoneMismatch?>((ref) {
  final account = ref.watch(accountUtcOffsetProvider);
  if (account == null) return null;
  final device = ref.watch(deviceUtcOffsetProvider);
  if (device == account) return null;
  final zone =
      ref.watch(currentUserProvider.select((user) => user?.zoneName)) ?? 'UTC';
  return (zone: zone, account: account, device: device);
});
