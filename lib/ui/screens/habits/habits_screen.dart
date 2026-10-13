import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../flows/flows.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/celebration_layer.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/rolling_number.dart';
import '../../widgets/row_motion.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'habit_card.dart';
import 'habit_detail_sheet.dart';
import 'habit_form.dart';
import 'widgets/habit_day_cell.dart';

/// The Habits tab (design-analysis §7.10).
///
/// * **No FAB** (D5): it covered the last card's check. A new habit starts
///   from the app bar's "Yeni" or the dashed "+ Yeni alışkanlık" row that
///   ends the list; an empty list offers starter chips instead.
/// * **The hero**: one card — today's done count (rolling) and the
///   perfect-day streak, the day's bar, the last 14 perfect days. A tap
///   opens the 30-day history.
/// * **The cards**: open habits first, done ones after, each group in the
///   server's order. A habit just checked stays where it was for
///   [_linger], then moves to its group — out of its old place and into
///   its new one.
/// * **Celebrations** only from a tap here: the tap that finishes the day
///   bursts from its control (tier 2); a streak of 7, 30, 100 or 365 days,
///   or the first perfect week, as the server answers it, shows the
///   milestone card (tier 3). Never a refresh, an undo or a past day.
///
/// Renders `habitsProvider` directly — no copy of it in State. A tap patches
/// the provider itself (through [HabitActions]), so this tab and Today flip
/// together, and a background refetch can never paint an older list over it.
///
/// Rebuilds stay with what changed (§8.8): the list watches only its order
/// (each habit's id and whether it is done) and its load state, the hero
/// only its header, and each card only its own habit — a counter step
/// rebuilds that card and the hero, nothing else.
class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

/// How long a habit just checked keeps its place: the wash's 1200 ms
/// (§7.10 "1200 ms bekleme kuralı").
const _linger = Motion.highlight;

/// The streak lengths that earn a milestone card.
const _streakMilestones = {7, 30, 100, 365};

/// How long after the tap the server's answer may still celebrate it.
const _milestoneWindow = Duration(seconds: 2);

class _HabitsScreenState extends ConsumerState<HabitsScreen>
    with TabRootScroll<HabitsScreen> {
  @override
  AppTab get tab => AppTab.habits;

  /// Cards play their entrance only with the first data (see [Entrance]).
  bool _staggered = false;
  bool _staggerScheduled = false;

  /// The order last shown, by habit id.
  List<int> _order = const [];

  /// Habits checked or counted just now: the list keeps its order until
  /// [_lingerTimer] lets them move.
  final _lingering = <int>{};
  Timer? _lingerTimer;

  /// Cards that moved group: the ghost left at the old place — just before
  /// the card that followed it there ([before]; null: the list's end) — and
  /// how many times each has moved (a moved card mounts afresh and grows
  /// in).
  final _ghosts = <int, ({Habit habit, int index, int? before})>{};
  final _moves = <int, int>{};
  final _entering = <int>{};

  /// One card widget per habit, kept: a list rebuild (a habit changed
  /// group) hands each card the same widget, so only the cards whose habit
  /// changed build again.
  final _tiles = <int, Widget>{};
  late final Widget _hero = _HeroCard(onTap: _openHistory);

  /// The starter being added, and the ones added: their chips stay off, so
  /// a second tap cannot add the habit twice (`POST /habits` is not
  /// idempotent, D29).
  _Starter? _adding;
  final _added = <_Starter>{};

  @override
  void dispose() {
    _lingerTimer?.cancel();
    super.dispose();
  }

  // --- Logging ------------------------------------------------------------------

  /// Sets today's count of [habit] to [count] — what its control asked for,
  /// from [origin]. Every tap counts, also while the habit's previous tap is
  /// still waiting for the server: [HabitActions] shows it at once and
  /// sends it next. The control plays its own haptic.
  Future<void> _log(Habit habit, int count, Offset origin) async {
    final actions = ref.read(habitActionsProvider);
    final bundle = ref.read(habitsProvider).value?.data;
    if (bundle == null) return;
    final l = context.l10n;
    final celebrations = CelebrationLayer.maybeOf(context);
    final started = Stopwatch()..start();

    final log = habit.logFor(count);
    final after = bundle.withHabitToday(habit.id, log);
    final wasAllDone =
        bundle.totalActive > 0 && bundle.completedToday >= bundle.totalActive;
    final nowAllDone =
        after.totalActive > 0 && after.completedToday >= after.totalActive;
    final becameComplete = log.completed && !habit.today.completed;
    final celebratesDay = nowAllDone && !wasAllDone;

    if (log.completed != habit.today.completed) _holdPlace(habit.id);

    // Whether this tap claimed the day's celebration: only then is there a
    // key to give back.
    var claimedDay = false;
    if (celebratesDay) {
      // Tier 2, from the control that finished the day — with the tap, not
      // the answer (§4.30: the burst is the tap's). A write that is then
      // refused or taken back gives the day's key back (below), so the
      // day's real completion later still celebrates.
      if (celebrations != null) {
        claimedDay =
            celebrations.allDone(origin: origin, day: habit.today.date);
      } else {
        Haptics.confirm();
      }
    }

    try {
      final sent = await actions.setToday(
        habit.id,
        count,
        day: habit.today.date,
      );
      if (!sent && claimedDay) celebrations?.forget(habit.today.date);
      if (!sent || !becameComplete || celebrations == null || !mounted) return;
      if (started.elapsed > _milestoneWindow) return;
      // Tier 3, from the server's answer to this tap.
      final now = ref.read(habitsProvider).value?.data;
      final answered = now?.habits.where((h) => h.id == habit.id).firstOrNull;
      final streak = answered?.currentStreak ?? 0;
      if (_streakMilestones.contains(streak) && streak > habit.currentStreak) {
        celebrations.milestone(
          key: 'habit.${habit.id}.$streak',
          text: l.milestoneStreak(streak, habit.name),
        );
      } else if (now != null &&
          now.perfectDay.currentStreak >= 7 &&
          bundle.perfectDay.currentStreak < 7) {
        celebrations.milestone(
          key: 'perfect-week',
          text: l.milestonePerfectWeek,
        );
      }
    } catch (e) {
      if (claimedDay) celebrations?.forget(habit.today.date);
      if (!mounted) return;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.habitsToggleFailed),
        isError: true,
      );
    }
  }

  /// Keeps the list's order while [id] lingers: the timer starts again
  /// with every tap, and when it ends every card that changed group moves.
  void _holdPlace(int id) {
    _lingering.add(id);
    _lingerTimer?.cancel();
    _lingerTimer = Timer(_linger, () {
      if (!mounted) return;
      final moved = Set.of(_lingering);
      setState(() {
        _lingering.clear();
        _moveCards(moved);
      });
    });
  }

  /// Ghosts at the old places of [ids] that now belong elsewhere, and a
  /// fresh mount (growing in) at the new ones.
  ///
  /// A ghost is anchored to the card that followed it — not to its old
  /// index, which the card moving up in front of it would shift by one.
  void _moveCards(Set<int> ids) {
    final bundle = ref.read(habitsProvider).value?.data;
    if (bundle == null || Motion.reduced(context)) return;
    final next = [
      for (final r in _sorted(_visible(_rowsOf(bundle.habits)))) r.id,
    ];
    final byId = {for (final h in bundle.habits) h.id: h};
    final moved = <int>{};
    for (final id in ids) {
      final before = _order.indexOf(id);
      final after = next.indexOf(id);
      if (before < 0 || after < 0 || before == after || byId[id] == null) {
        continue;
      }
      moved.add(id);
    }
    final stays = next.toSet().difference(moved);
    for (final id in moved) {
      final index = _order.indexOf(id);
      _ghosts[id] = (
        habit: byId[id]!,
        index: index,
        before: _order.skip(index + 1).where(stays.contains).firstOrNull,
      );
      _moves[id] = (_moves[id] ?? 0) + 1;
      _entering.add(id);
    }
  }

  // --- Creating -----------------------------------------------------------------

  /// Adds a starter habit at once, with its defaults (`POST /habits`); the
  /// new card grows in, washed.
  Future<void> _addStarter(_Starter starter) async {
    if (_adding != null || _added.contains(starter)) return;
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final sync = ref.read(dataSyncProvider);
    setState(() => _adding = starter);
    try {
      final habit = await repo.createHabit(
        HabitInput(
          name: starter.habitName(l),
          frequency: 'daily',
          targetCount: starter.target,
          color: starter.color,
        ),
      );
      _added.add(starter);
      sync.noteChange(DataScope.habits, habit.id, ChangeKind.inserted);
      Haptics.confirm();
      if (mounted) showAppSnack(context, l.habitsAddedNamed(habit.name));
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.habitsSaveFailed),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  /// The form; the habit it creates grows in, washed (the form notes it).
  Future<void> _newHabit() => openHabitForm(context);

  Future<void> _refresh() async {
    refreshTab(ref, AppTab.habits);
    await settleRefresh([refetchLanded(ref, habitsProvider)]);
  }

  // --- History ------------------------------------------------------------------

  void _openHistory() {
    final bundle = ref.read(habitsProvider).value?.data;
    if (bundle == null) return;
    final l = context.l10n;
    final pd = bundle.perfectDay;
    showNokSheet<void>(
      context,
      title: l.habitsPerfectHistory,
      showClose: true,
      builder: (context) {
        final c = context.nok;
        final text = Theme.of(context).textTheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.sheetH,
              0,
              Insets.sheetH,
              Gap.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PerfectDayDots(
                  chain: pd.chain,
                  todayDone: _allDone(bundle),
                  semantics: true,
                ),
                const SizedBox(height: Gap.lg),
                HabitDayLegend(
                  fill: c.gold,
                  shape: HabitDayShape.circle,
                  showPending: true,
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  l.habitsPerfectStreak(pd.currentStreak, pd.longestStreak),
                  style: text.bodySmall!.copyWith(color: c.inkMid),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Build --------------------------------------------------------------------

  static bool _allDone(HabitsBundle b) =>
      b.totalActive > 0 && b.completedToday >= b.totalActive;

  /// [rows] without a habit being deleted: it leaves the list at once.
  List<_ListRow> _visible(List<_ListRow> rows) => withoutDeleted(
    rows,
    ref.read(deferredDeletesProvider),
    DataScope.habits,
    (r) => r.id,
  );

  static List<_ListRow> _rowsOf(List<Habit> habits) => [
    for (final h in habits) (id: h.id, done: h.today.completed),
  ];

  /// Open habits first, then the ones done today; the server's order
  /// within each.
  static List<_ListRow> _sorted(List<_ListRow> rows) => [
    for (final r in rows)
      if (!r.done) r,
    for (final r in rows)
      if (r.done) r,
  ];

  /// The ids of [rows] in the order to show: [_sorted], or — while a habit
  /// lingers — the order last shown, new habits at their sorted place.
  List<int> _ordered(List<_ListRow> rows) {
    final sorted = [for (final r in _sorted(rows)) r.id];
    if (_lingering.isEmpty) return sorted;
    final listed = sorted.toSet();
    final kept = [
      for (final id in _order)
        if (listed.contains(id)) id,
    ];
    final known = kept.toSet();
    for (var i = 0; i < sorted.length; i++) {
      if (known.contains(sorted[i])) continue;
      kept.insert(i.clamp(0, kept.length), sorted[i]);
    }
    return kept;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    // Only what the list itself shows: the order and the load state. A
    // count step leaves both as they were — its card and the hero rebuild
    // alone.
    final list = ref.watch(habitsProvider.select(_ListState.of));
    // A habit being deleted leaves the list at once.
    ref.watch(deferredDeletesProvider);
    final rows = list.rows == null ? null : _visible(list.rows!);
    final empty = rows != null && rows.isEmpty;

    final Widget body;
    if (list.firstLoad) {
      body = const _HabitsSkeleton();
    } else if (rows == null) {
      body = EmptyState.error(onRetry: _refresh);
    } else {
      body = RefreshIndicator.adaptive(
        color: c.gold,
        onRefresh: () {
          Haptics.armed();
          return _refresh();
        },
        child: _content(context, rows, list.refreshFailed, list.at!),
      );
    }

    return primaryScroll(
      Scaffold(
        appBar: AppBar(
          title: Text(
            l.titleHabits,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          actions: [
            // While the list is empty its starter chips are the way in: one
            // control per action.
            if (rows != null && !empty)
              TextButton.icon(
                onPressed: _newHabit,
                icon: const Icon(Icons.add_rounded),
                label: Text(l.habitsNew),
              ),
            PopupMenuButton<String>(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (path) => context.push(path),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: '/habits/archived',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(l.habitsMenuArchive),
                  ),
                ),
                // Goals left the bar; the habits they track lead there.
                PopupMenuItem(
                  value: '/goals',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(l.titleGoals),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Gap.xs),
          ],
        ),
        body: SyncHint.over(active: list.refetching, child: body),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<_ListRow> habits,
    bool offline,
    DateTime lastUpdated,
  ) {
    final l = context.l10n;
    final bottom = Gap.xxl + MediaQuery.paddingOf(context).bottom;

    if (habits.isEmpty) {
      return CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (offline)
            SliverToBoxAdapter(
              child: OfflineBanner(lastUpdated: lastUpdated, onRetry: _refresh),
            ),
          // The starter chips can be taller than the screen (large text):
          // centred when they fit, scrolling when they do not.
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.remainingPaintExtent,
                ),
                child: EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: l.habitsPickFirst,
                  subtitle: l.habitsStarterBody,
                  chips: [
                    for (final s in _Starter.values)
                      NokChip(
                        key: ValueKey('starter-${s.index}'),
                        label: s.label(l),
                        icon: s == _Starter.custom ? Icons.add_rounded : null,
                        // Off while a starter is on its way, and for good
                        // once added.
                        onTap: s == _Starter.custom
                            ? _newHabit
                            : _adding != null || _added.contains(s)
                            ? null
                            : () => _addStarter(s),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final stagger = !_staggered;
    if (stagger && !_staggerScheduled) {
      _staggerScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _staggered = true;
      });
    }

    final shown = _ordered(habits);
    _order = shown;
    _tiles.removeWhere((id, _) => !shown.contains(id));
    if (_entering.isNotEmpty) {
      // RowEnter reads it once, as the moved card mounts.
      WidgetsBinding.instance.addPostFrameCallback((_) => _entering.clear());
    }

    final rowIds = <int?>[...shown];
    final rows = <Widget>[
      for (var i = 0; i < shown.length; i++)
        KeyedSubtree(
          // Keyed by habit, so a card's control (and its animation) follows
          // its habit when the list shifts.
          key: ValueKey('habit-${shown[i]}'),
          child: KeyedSubtree(
            key: ValueKey(('move', _moves[shown[i]] ?? 0)),
            child: RowEnter(
              play: _entering.contains(shown[i]),
              // The gap under the card grows in with it: nothing below
              // jumps by it.
              child: Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: Entrance.staggered(
                  play: stagger,
                  index: i,
                  child: _tile(shown[i]),
                ),
              ),
            ),
          ),
        ),
    ];
    // Ghosts go back where their cards were: before the card that followed
    // them there, in their old order.
    final ghosts = _ghosts.entries.toList()
      ..sort((a, b) => a.value.index.compareTo(b.value.index));
    for (final MapEntry(key: id, value: ghost) in ghosts) {
      final anchor = ghost.before == null ? -1 : rowIds.indexOf(ghost.before);
      final at = anchor < 0 ? rows.length : anchor;
      rowIds.insert(at, null);
      rows.insert(
        at,
        RowExit(
          key: ValueKey('habit-ghost-$id'),
          onDone: () {
            if (mounted) setState(() => _ghosts.remove(id));
          },
          // The gap collapses with the ghost.
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: HabitCard(
              habit: ghost.habit,
              onLog: (_, _) {},
              onOpen: () {},
            ),
          ),
        ),
      );
    }

    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (offline)
          SliverToBoxAdapter(
            child: OfflineBanner(lastUpdated: lastUpdated, onRetry: _refresh),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Insets.gutter,
            Gap.md,
            Insets.gutter,
            bottom,
          ),
          sliver: SliverList.list(
            children: [
              _hero,
              const SizedBox(height: Gap.xxl),
              ...rows,
              _NewHabitRow(onTap: _newHabit),
            ],
          ),
        ),
      ],
    );
  }

  /// The card of habit [id] — the same widget every build (see [_tiles]).
  Widget _tile(int id) => _tiles[id] ??= _HabitTile(
    id: id,
    onLog: _log,
    onOpen: (habit) => showHabitDetailSheet(context, habit),
    onLongPress: (habit) => openHabitLog(context, habitId: habit.id),
  );
}

/// A habit's place in the list: its id and whether it is done today.
typedef _ListRow = ({int id, bool done});

/// What the list itself shows of `habitsProvider`: its load state and its
/// rows' order. Equal for two values that differ only inside a card (a
/// counter step) or the hero — the list then does not rebuild.
@immutable
class _ListState {
  final bool firstLoad;
  final bool refreshFailed;
  final bool refetching;
  final DateTime? at;

  /// Null without data (still loading, or failed).
  final List<_ListRow>? rows;

  const _ListState({
    required this.firstLoad,
    required this.refreshFailed,
    required this.refetching,
    required this.at,
    required this.rows,
  });

  static _ListState of(AsyncValue<Fetched<HabitsBundle>> async) {
    final fetched = async.value;
    return _ListState(
      firstLoad: async.isFirstLoad,
      refreshFailed: async.refreshFailed,
      refetching: async.isRefetching,
      at: fetched?.at,
      rows: fetched == null
          ? null
          : _HabitsScreenState._rowsOf(fetched.data.habits),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ListState &&
      other.firstLoad == firstLoad &&
      other.refreshFailed == refreshFailed &&
      other.refetching == refetching &&
      other.at == at &&
      listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    firstLoad,
    refreshFailed,
    refetching,
    at,
    rows == null ? null : Object.hashAll(rows!),
  );
}

/// One habit's card, watching that habit alone
/// (`habitsProvider.select(... id)`, §8.8): a tap on another card, or a
/// change to the header, does not build it again.
class _HabitTile extends ConsumerWidget {
  final int id;
  final void Function(Habit habit, int count, Offset origin) onLog;
  final void Function(Habit habit) onOpen;
  final void Function(Habit habit) onLongPress;

  const _HabitTile({
    required this.id,
    required this.onLog,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habit = ref.watch(
      habitsProvider.select(
        (a) => a.value?.data.habits.where((h) => h.id == id).firstOrNull,
      ),
    );
    if (habit == null) return const SizedBox.shrink();
    return RowMotion(
      record: (scope: DataScope.habits, id: id),
      child: HabitCard(
        habit: habit,
        onLog: (count, origin) => onLog(habit, count, origin),
        onOpen: () => onOpen(habit),
        onLongPress: () => onLongPress(habit),
      ),
    );
  }
}

/// The hero (§7.10, ≈ 106 dp): "2 / 5 tamamlandı" with the done count
/// rolling, the perfect-day streak on the right (a flame while it runs),
/// the day's gold bar and the last 14 perfect days. "Hepsi tamam" joins
/// the heading once the day is done. A tap opens the 30-day history.
class _HeroCard extends ConsumerWidget {
  final VoidCallback onTap;

  const _HeroCard({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The header alone (§8.8): a step that changes no count leaves it.
    final header = ref.watch(
      habitsProvider.select((a) {
        final b = a.value?.data;
        return b == null
            ? null
            : (
                done: b.completedToday,
                total: b.totalActive,
                perfectDay: b.perfectDay,
              );
      }),
    );
    if (header == null) return const SizedBox.shrink();
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final total = header.total;
    final done = header.done;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final allDone = total > 0 && done >= total;
    final pd = header.perfectDay;
    final heading = text.titleLarge!;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    // One paragraph, so "2 / 5 tamamlandı" wraps as words do. The span
    // scales the number with the text: it is laid out unscaled.
    final count = Semantics(
      label: l.habitsDoneOfTotal(done, total),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MediaQuery.withNoTextScaling(
                child: RollingNumber(
                  text: '$done',
                  style: heading,
                  cause: DataSync.userWroteRecently
                      ? NumberCause.user
                      : NumberCause.background,
                ),
              ),
            ),
            TextSpan(text: l.habitsDoneOfTotalRest(total)),
          ],
        ),
        style: heading,
      ),
    );

    final Widget? streak = pd.currentStreak > 0
        // The flame stays with the words when they wrap.
        ? Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: Gap.xxs),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      size: 14,
                      color: c.goldBright,
                    ),
                  ),
                ),
                TextSpan(
                  text: l.habitsPerfectMeta(pd.currentStreak, pd.longestStreak),
                ),
              ],
            ),
            textAlign: large ? TextAlign.start : TextAlign.end,
            style: text.labelSmall!.copyWith(color: c.inkMid),
          )
        : pd.longestStreak > 0
        ? Text(
            l.streakNewRecord(pd.longestStreak),
            textAlign: large ? TextAlign.start : TextAlign.end,
            style: text.labelSmall!.copyWith(color: c.inkMid),
          )
        : null;

    return NokturnCard(
      variant: NokCardVariant.hero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (large)
            // Large text: the count, then the pill and the streak under it,
            // each with the card's whole width.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                count,
                if (allDone) ...[
                  const SizedBox(height: Gap.xs),
                  const _AllDonePill(),
                ],
                if (streak != null) ...[
                  const SizedBox(height: Gap.xs),
                  streak,
                ],
              ],
            )
          else if (allDone)
            // Once the day is done its pill joins the perfect-day streak —
            // the day just done is what the streak counts. Neither is ever
            // cut: at their own width on the right, or under the count when
            // they do not fit on one line.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              children: [
                count,
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  children: [const _AllDonePill(), ?streak],
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The count comes first; the streak takes what is left.
                Flexible(flex: 3, fit: FlexFit.tight, child: count),
                if (streak != null) ...[
                  const SizedBox(width: Gap.sm),
                  Flexible(flex: 2, child: streak),
                ],
              ],
            ),
          const SizedBox(height: Gap.md),
          PacedProgressBar(value: pct, color: c.gold, height: 8),
          const SizedBox(height: Gap.md),
          PerfectDayDots(chain: pd.chain, count: 14, todayDone: allDone),
        ],
      ),
    );
  }
}

/// "Hepsi tamam" in the hero's heading: the sparkle and the words in gold
/// on goldContainer, at their own width.
class _AllDonePill extends StatelessWidget {
  const _AllDonePill();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.goldContainer,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: c.onGoldContainer,
            ),
            const SizedBox(width: Gap.xs),
            // Never ellipsized (§10.1-18): it wraps only when even the
            // card's whole width is too narrow.
            Flexible(
              child: Text(
                context.l10n.habitsAllDone,
                style: text.labelSmall!.copyWith(color: c.onGoldContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list's last row: 56 dp, a dashed edge, "+ Yeni alışkanlık" — the
/// form, without a FAB over the cards.
class _NewHabitRow extends StatelessWidget {
  final VoidCallback onTap;

  const _NewHabitRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.lgAll,
          child: CustomPaint(
            painter: _DashedEdge(color: c.inkFaint),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.card,
                  vertical: Gap.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 20, color: c.inkMid),
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: Text(
                        context.l10n.habitsFormNewTitle,
                        style: text.titleSmall!.copyWith(color: c.inkMid),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 dp dashed rounded edge (6 on, 4 off), as `GhostCard` draws it.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(Radii.lg)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.color != color;
}

/// The starter habits an empty list offers (§7.10): each is added at once
/// with its defaults — daily, its count — and "Özel…" opens the form.
enum _Starter {
  water(8, '#6B8FA0'),
  walk(1, '#6B8E5A'),
  read(10, '#C98F6B'),
  sleep(1, '#7A5C9E'),
  meditate(1, '#5A9E8B'),
  custom(1, '#D4A853');

  const _Starter(this.target, this.color);

  final int target;
  final String color;

  /// The chip's words ("Su · günde 8").
  String label(AppL10n l) => switch (this) {
    water => l.habitsStarterWaterChip,
    walk => l.habitsStarterWalk,
    read => l.habitsStarterReadChip,
    sleep => l.habitsStarterSleep,
    meditate => l.habitsStarterMeditate,
    custom => l.habitsStarterCustom,
  };

  /// The habit's name ("Su").
  String habitName(AppL10n l) => switch (this) {
    water => l.habitsStarterWater,
    walk => l.habitsStarterWalk,
    read => l.habitsStarterRead,
    sleep => l.habitsStarterSleep,
    meditate => l.habitsStarterMeditate,
    custom => l.habitsStarterCustom,
  };
}

/// First-load skeleton mirroring the real layout: the hero, then cards.
class _HabitsSkeleton extends StatelessWidget {
  const _HabitsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    Widget bone(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: c.surface2, borderRadius: Radii.xsAll),
    );
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.md,
          Insets.gutter,
          Gap.xxl,
        ),
        children: [
          NokturnCard(
            variant: NokCardVariant.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.habitsDoneOfTotal(3, 7), style: text.titleLarge),
                const SizedBox(height: Gap.md),
                bone(double.infinity, 8),
                const SizedBox(height: Gap.md),
                bone(218, 10),
              ],
            ),
          ),
          const SizedBox(height: Gap.xxl),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: NokturnCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.card,
                  vertical: Gap.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Hit.min),
                      child: Row(
                        children: [
                          bone(12, 12),
                          const SizedBox(width: Gap.md),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.habitsFormName, style: text.titleMedium),
                                const SizedBox(height: Gap.xxs),
                                bone(96, 10),
                              ],
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.surface2,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 24),
                      child: bone(220, 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
