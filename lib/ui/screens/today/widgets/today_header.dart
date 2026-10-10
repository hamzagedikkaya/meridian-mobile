import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formats.dart';
import '../../../../core/session.dart';
import '../../../../data/current_day.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/event.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../widgets/money_glance.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/skeletons.dart';
import '../../events/agenda_screen.dart';
import '../../events/event_sheet.dart';
import 'start_card.dart';
import 'today_clock.dart';
import 'today_common.dart';

/// Today's header (design-analysis §7.2): the date (bodyMedium inkMid) over
/// "İyi günler, Hamza" (headlineLarge Fraunces, the first name only, up to
/// two lines), the 40 dp avatar in a 48 dp target on the right — and under
/// them the chips: this month's net ([MoneyGlance]) and what is next
/// ([TodayNextUp]).
///
/// It reads only what it shows — the user and the day — so a habit tick
/// never rebuilds it; the chips are a widget of their own.
class TodayHeader extends ConsumerWidget {
  const TodayHeader({super.key});

  /// How many times a header was built: the rebuild test's counter.
  @visibleForTesting
  static int debugBuilds = 0;

  /// How many times its chip row was built: the rebuild test's counter.
  @visibleForTesting
  static int debugChipBuilds = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kDebugMode) debugBuilds++;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final now = ref.read(clockProvider)();
    final today =
        ref.watch(homeProvider.select((a) => a.value?.data.today)) ??
        ref.watch<DateTime>(currentDayProvider);
    final name = user?.displayName.trim() ?? '';
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.sm, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.todayDateLine(today),
                      style: text.bodyMedium!.copyWith(color: c.inkMid),
                    ),
                    Text(
                      l.todayGreeting(l.greeting(now.hour), firstName),
                      style: text.headlineLarge,
                      // At large text the greeting alone fills two lines:
                      // the name keeps a third.
                      maxLines: large ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _Avatar(
                initials: user?.initials ?? '',
                onTap: () => context.push('/profile'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, 0),
          child: _HeaderChips(),
        ),
      ],
    );
  }
}

/// The chip row: the money glance and the next event. Its own widget, so
/// what it reads never rebuilds the greeting.
class _HeaderChips extends ConsumerWidget {
  const _HeaderChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kDebugMode) TodayHeader.debugChipBuilds++;
    final money = ref.watch(
      homeProvider.select((a) {
        final home = a.value?.data;
        return home == null
            ? null
            : (
                net: home.monthNetCents,
                currency: home.currency,
                subunit: home.subunitToUnit,
              );
      }),
    );
    // No account: true, false, or null while the accounts load. A failed
    // read shows the net, as an account would.
    final noAccount = ref.watch(
      accountsProvider.select(
        (a) => a.hasValue
            ? a.value!.data.every((account) => account.archived)
            : a.hasError
            ? false
            : null,
      ),
    );
    // The first-run card carries "Nakit hesabı aç": one control per action
    // (D42).
    final starting = ref.watch(todayStartProvider.select((p) => p != null));
    final decided = ref.watch(todayStartDecidedProvider);
    final Widget? glance;
    if (money == null || (starting && noAccount == true)) {
      glance = null;
    } else if (noAccount == null || (noAccount && !decided)) {
      // Not known yet whether there is an account (or whether the
      // first-run card will offer one): a bone, never a "₺0" a new
      // account would then take back.
      glance = const _ChipBone();
    } else {
      glance = MoneyGlance(
        netCents: noAccount ? null : money.net,
        currency: money.currency,
        subunitToUnit: money.subunit,
        // A chip drops ",00" (§3.7).
        decimals: MoneyDecimals.auto,
        onTap: () => context.go('/finance'),
        onStart: () => openTodayCashAccount(context, ref),
      );
    }
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final next = todayNextUpOf(context, ref);
    return LayoutBuilder(
      builder: (context, box) {
        // Past 1.3× text the chips wrap: each has the row to itself.
        if (large) {
          return Wrap(
            spacing: Gap.sm,
            children: [
              if (glance != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth),
                  child: glance,
                ),
              const TodayNextUp(),
            ],
          );
        }
        // One line, so the habits stay within the first screen. The
        // next-up chip keeps its time and minutes (and a little of its
        // title); the money takes the rest — its words shrink to fit, never
        // its 48 dp target, and an amount is never cut (§3.7). What is left
        // goes to the next-up title.
        final nextRoom = next == null
            ? 0.0
            : Gap.sm + TodayNextUp.leastWidth(context, next);
        final fitted = glance == null
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (box.maxWidth - nextRoom).clamp(0, box.maxWidth),
                ),
                child: glance,
              );
        return Row(
          children: [
            if (fitted != null) ...[fitted, const SizedBox(width: Gap.sm)],
            const Flexible(child: TodayNextUp()),
          ],
        );
      },
    );
  }
}

/// The money chip's place while it is not known what it will say: a 36 dp
/// bone in the 48 dp row.
class _ChipBone extends StatelessWidget {
  const _ChipBone();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: Hit.min,
    child: Center(
      widthFactor: 1,
      child: Bone(width: 128, height: 36, shape: BoneShape.block),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.onTap});

  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: context.l10n.semProfileAndSettings,
      // excludeSemantics drops the InkResponse's own tap: say it here.
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: Hit.min,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.goldContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                maxLines: 1,
                style: text.labelMedium!.copyWith(
                  color: c.onGoldContainer,
                  fontWeight: FontWeight.w600,
                ),
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is next today (design-analysis §7.2): an event under way ("Şimdi ·
/// Takım toplantısı") or the first one starting within two hours ("09:30 ·
/// Takım toplantısı · 25 dk"), as a 36 dp chip at most 240 dp wide whose
/// title gives way first — the time and the minutes stay. A tap opens the
/// event. Nothing to show: no chip. It moves with the minutes
/// ([todayNowProvider]).
class TodayNextUp extends ConsumerWidget {
  const TodayNextUp({super.key});

  /// How far ahead an event counts as next.
  static const horizon = Duration(minutes: 120);

  /// How many times a next-up chip was built: the rebuild test's counter.
  @visibleForTesting
  static int debugBuilds = 0;

  /// The title's room the header keeps beside the money.
  static const _keptTitle = 32.0;

  /// The least room the title needs to be shown on its own, between the
  /// time and the minutes; with less the label is one line, cut at its end.
  static const _minTitle = 16.0;

  /// The pill's padding (its edge included), the icon and its gap.
  static const _chrome = 2 * Gap.md + 16 + 6;

  /// The least width [TodayNextUp] needs to show [next]'s time and minutes
  /// whole beside a little of its title: what the header keeps for it.
  static double leastWidth(BuildContext context, TodayNextUpInfo next) {
    final parts = _partsOf(context.l10n, next);
    return _chrome +
        _measure(context, parts.prefix + parts.suffix) +
        (parts.title.isEmpty ? 0 : _keptTitle);
  }

  static TextStyle _style(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(color: context.nok.inkHi);

  static double _measure(BuildContext context, String text) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// [next]'s label, split around its title: what stays (the time, the
  /// minutes) and what gives way (the title).
  static ({String label, String prefix, String title, String suffix})
  _partsOf(AppL10n l, TodayNextUpInfo next) {
    final (next: o, :now, :current) = next;
    final start = o.event.occurrenceStart(o.day);
    final eventTitle = o.event.title;
    final label = current
        ? l.todayNextUpNow(eventTitle)
        : l.todayNextUpSoon(
            formatTime(start),
            eventTitle,
            // Round up: an event 24.5 minutes away starts "in 25".
            (start.difference(now).inSeconds / 60).ceil(),
          );
    final at = eventTitle.isEmpty ? -1 : label.indexOf(eventTitle);
    if (at < 0) return (label: label, prefix: '', title: '', suffix: label);
    return (
      label: label,
      prefix: label.substring(0, at),
      title: eventTitle,
      suffix: label.substring(at + eventTitle.length),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kDebugMode) debugBuilds++;
    final c = context.nok;
    final found = todayNextUpOf(context, ref);
    if (found == null) return const SizedBox.shrink();
    final next = found.next;
    final parts = _partsOf(context.l10n, found);
    final style = _style(context);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    void open() => showEventSheet(context, next.event, day: next.day);
    return Semantics(
      button: true,
      label: parts.label,
      onTap: open,
      excludeSemantics: true,
      child: PressableScale.small(
        onTap: open,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              // Large text has the row to itself (the chips wrap).
              constraints: BoxConstraints(
                minHeight: 36,
                maxWidth: large ? double.infinity : 240,
              ),
              padding: const EdgeInsets.symmetric(horizontal: Gap.md - 1),
              decoration: ShapeDecoration(
                color: c.surface1,
                shape: StadiumBorder(side: BorderSide(color: c.hairline)),
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  // The title gives way first; the time and the minutes
                  // stay. Squeezed past even that, the label is one line
                  // cut at its end — it still starts with when.
                  final fixed = _measure(context, parts.prefix + parts.suffix);
                  final split =
                      parts.title.isNotEmpty &&
                      16 + 6 + fixed + _minTitle <= box.maxWidth;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: c.inkMid),
                      const SizedBox(width: 6),
                      if (split) ...[
                        if (parts.prefix.isNotEmpty)
                          Text(parts.prefix, maxLines: 1, style: style),
                        Flexible(
                          child: Text(
                            parts.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                        ),
                        if (parts.suffix.isNotEmpty)
                          Text(parts.suffix, maxLines: 1, style: style),
                      ] else
                        Flexible(
                          child: Text(
                            parts.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What [TodayNextUp] shows: the occurrence, the time it was worked out at,
/// and whether that event is under way.
typedef TodayNextUpInfo = ({Occurrence next, DateTime now, bool current});

/// What [TodayNextUp] shows — an event under way ([current]), else the first
/// one starting within [TodayNextUp.horizon] — or null when there is none.
/// "Now" is the account's wall clock, as the event times are, and moves
/// with the minutes while Today is shown ([watchTodayNow]).
TodayNextUpInfo? todayNextUpOf(BuildContext context, WidgetRef ref) {
  final today =
      ref.watch(homeProvider.select((a) => a.value?.data.today)) ??
      ref.watch<DateTime>(currentDayProvider);
  final day = DateTime(today.year, today.month, today.day);
  final window = EventWindow(day, day);
  final listed = ref.watch(eventsProvider(window).select((a) => a.value?.data));
  final fromHome = ref.watch(
    homeProvider.select((a) => a.value?.data.todayEvents),
  );
  final events = listed ?? fromHome ?? const <Event>[];
  final now = watchTodayNow(context, ref);

  Occurrence? current;
  Occurrence? soon;
  for (final o in occurrencesIn(
    events,
    window,
    fallbackDay: listed == null ? day : null,
  )) {
    final e = o.event;
    if (e.allDay || e.startAt == null) continue;
    final start = e.occurrenceStart(o.day);
    final end = occurrenceEndOf(e, o.day);
    if (!start.isAfter(now) && end.isAfter(now)) {
      if (current == null ||
          start.isBefore(current.event.occurrenceStart(current.day))) {
        current = o;
      }
    } else if (start.isAfter(now) &&
        start.difference(now) <= TodayNextUp.horizon) {
      if (soon == null ||
          start.isBefore(soon.event.occurrenceStart(soon.day))) {
        soon = o;
      }
    }
  }
  final next = current ?? soon;
  if (next == null) return null;
  return (next: next, now: now, current: current != null);
}
