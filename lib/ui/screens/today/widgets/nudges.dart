import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/formats.dart';
import '../../../../core/session.dart';
import '../../../../data/current_day.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/finance_dashboard.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../flows/flows.dart';
import '../../../widgets/nokturn_card.dart';
import '../../finance/subscriptions_screen.dart';
import 'start_card.dart';
import 'today_common.dart';
import 'zone_notice.dart';

/// The device's preferences, or null where there are none (a test that does
/// not provide them): a dismissal then lasts as long as the screen.
SharedPreferences? todayPrefs(WidgetRef ref) {
  try {
    return ref.read(sharedPrefsProvider);
  } catch (_) {
    return null;
  }
}

/// `yyyy-mm-dd` of [day], for the per-day dismissal keys.
String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The kinds of nudge that are dismissed for a day:
/// `today.nudge.<kind>.<yyyy-mm-dd>` (design-analysis §7.2).
String nudgeDismissKey(String kind, DateTime day) =>
    'today.nudge.$kind.${_dayKey(day)}';

/// One card of the nudge slot (design-analysis §7.2): a 20 dp inkMid icon,
/// the [message], an optional [action] and a 48 dp close button. A tap on
/// the card ([onTap]) does what the nudge suggests.
class NudgeCard extends StatelessWidget {
  const NudgeCard({
    super.key,
    required this.icon,
    required this.message,
    required this.onDismiss,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String message;
  final Widget? action;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final action = this.action;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.xs, Gap.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.min),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.inkMid),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: Text(
                  message,
                  style: text.bodyMedium!.copyWith(color: c.inkHi),
                ),
              ),
            ),
            ?action,
            IconButton(
              tooltip: l.actionDismiss,
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 20, color: c.inkLow),
            ),
          ],
        ),
      ),
    );
    return NokturnCard(
      padding: EdgeInsets.zero,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// A daily habit whose yesterday is not complete.
typedef _Unmarked = ({int id, String name});

/// Today's nudge slot (design-analysis §7.2): no card, or one, then 12 dp.
/// In order of priority:
///
/// 1. the first-run card ([StartCard], §7.15);
/// 2. the time-zone notice ([TodayZoneNotice]);
/// 3. "Dünü işaretlemeyi unuttun mu?" — a daily habit yesterday left
///    incomplete; a tap opens yesterday's log;
/// 4. a subscription payment past due, with "Ödendi"; a tap opens the
///    subscription.
///
/// Each is closed with its X: the zone notice for its pair of zones, the
/// others for the day (`today.nudge.<kind>.<yyyy-mm-dd>`). A lower card's
/// data is only read while nothing above it shows.
class TodayNudgeSlot extends ConsumerStatefulWidget {
  const TodayNudgeSlot({super.key});

  @override
  ConsumerState<TodayNudgeSlot> createState() => _TodayNudgeSlotState();
}

class _TodayNudgeSlotState extends ConsumerState<TodayNudgeSlot> {
  /// Dismissals read from (or written to) the preferences in this run.
  final _dismissed = <String, bool>{};
  String? _zoneDismissed;
  bool _zoneRead = false;

  bool _isDismissed(String key) =>
      _dismissed.putIfAbsent(key, () => todayPrefs(ref)?.getBool(key) ?? false);

  void _dismiss(String key) {
    setState(() => _dismissed[key] = true);
    todayPrefs(ref)?.setBool(key, true);
  }

  String? _zonePair() {
    if (!_zoneRead) {
      _zoneRead = true;
      _zoneDismissed = todayPrefs(ref)?.getString(PrefKeys.zoneNoticeDismissed);
    }
    return _zoneDismissed;
  }

  void _dismissZone(String pair) {
    setState(() => _zoneDismissed = pair);
    todayPrefs(ref)?.setString(PrefKeys.zoneNoticeDismissed, pair);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    return todayResize(
      context,
      child: card == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: card,
            ),
    );
  }

  Widget? _card(BuildContext context) {
    final start = ref.watch(todayStartProvider);
    if (start != null) return StartCard(progress: start);

    final mismatch = ref.watch(zoneMismatchProvider);
    if (mismatch != null) {
      final pair = zoneNoticeKey(mismatch);
      if (_zonePair() != pair) {
        return TodayZoneNotice(
          mismatch: mismatch,
          onDismiss: () => _dismissZone(pair),
        );
      }
    }

    final today =
        ref.watch(homeProvider.select((a) => a.value?.data.today)) ??
        ref.watch<DateTime>(currentDayProvider);
    final l = context.l10n;

    final yesterdayKey = nudgeDismissKey('yesterday', today);
    if (!_isDismissed(yesterdayKey)) {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final unmarked = ref.watch(
        habitsProvider.select(
          (a) => _firstUnmarked(a.value?.data.habits, yesterday),
        ),
      );
      if (unmarked != null) {
        return NudgeCard(
          icon: Icons.history_rounded,
          message: l.todayNudgeYesterday(unmarked.name),
          onTap: () {
            // Shown once a day: answered is as good as dismissed.
            _dismiss(yesterdayKey);
            openHabitLog(context, habitId: unmarked.id, date: yesterday);
          },
          onDismiss: () => _dismiss(yesterdayKey),
        );
      }
    }

    final lateKey = nudgeDismissKey('subscription', today);
    if (!_isDismissed(lateKey)) {
      final late = ref.watch(
        financeDashboardProvider.select(
          (a) => _firstLate(a.value?.data.upcomingSubscriptions, today),
        ),
      );
      if (late != null) {
        final paying = ref
            .watch(subscriptionChargesInFlightProvider)
            .contains(late.id);
        return NudgeCard(
          icon: Icons.event_repeat_rounded,
          message: l.todayNudgeLate(
            late.name,
            formatMoney(
              late.amountCents,
              late.account.currency,
              late.account.subunitToUnit,
            ),
          ),
          action: TextButton(
            onPressed: paying
                ? null
                : () => markSubscriptionPaid(
                    context,
                    ref,
                    SubscriptionLite.ofItem(late),
                  ),
            child: Text(l.todayNudgePaid),
          ),
          onTap: () =>
              showSubscriptionSheet(context, id: late.id, name: late.name),
          onDismiss: () => _dismiss(lateKey),
        );
      }
    }
    return null;
  }
}

/// The first daily habit (in the list's order) whose [yesterday] is missed
/// or partial — never one that had not started yet, nor an archived one.
_Unmarked? _firstUnmarked(List<Habit>? habits, DateTime yesterday) {
  if (habits == null) return null;
  for (final habit in habits) {
    if (!habit.isDaily || habit.archived) continue;
    final start = habit.startDate;
    if (start != null && dateOnly(start).isAfter(yesterday)) continue;
    for (final day in habit.chain) {
      if (dateOnly(day.date) != yesterday) continue;
      if (day.status == ChainStatus.missed ||
          day.status == ChainStatus.partial) {
        return (id: habit.id, name: habit.name);
      }
    }
  }
  return null;
}

/// The subscription whose payment is the most overdue, if any is.
SubscriptionItem? _firstLate(List<SubscriptionItem>? items, DateTime today) {
  if (items == null) return null;
  SubscriptionItem? late;
  for (final s in items) {
    final due = s.nextChargeOn;
    if (due == null || !dateOnly(due).isBefore(today)) continue;
    if (late == null || due.isBefore(late.nextChargeOn!)) late = s;
  }
  return late;
}
