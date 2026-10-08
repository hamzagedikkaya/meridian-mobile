import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/actions.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/home.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sparkline.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/sync_hint.dart';
import '../habits/habit_log_sheet.dart';
import '../shell/app_tabs.dart';
import '../todos/todo_flows.dart';
import '../todos/todo_sheet.dart';
import 'widgets/today_common.dart';
import 'widgets/today_skeleton.dart';
import 'widgets/home_habit_row.dart';
import 'widgets/quick_capture_sheet.dart';
import 'widgets/today_agenda.dart';
import 'widgets/todo_row.dart';
import 'widgets/zone_notice.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with TabRootScroll<TodayScreen> {
  @override
  AppTab get tab => AppTab.today;

  /// Sections play their entrance only with the first data; refreshes then
  /// update them in place (see [Entrance]).
  bool _animatedOnce = false;

  /// Pull-to-refresh: Today summarises every domain, so it syncs everything.
  Future<void> _refresh() async {
    Haptics.celebrate();
    refreshTab(ref, AppTab.today);
    await settleRefresh(
      [refetchLanded(ref, homeProvider)],
      minimum: const Duration(milliseconds: 500),
    );
  }

  void _retry() => ref.read(dataSyncProvider).refresh([homeProvider]);

  /// Checks [todo] off ([done]) or reopens it, on the spot (CheckPop fires
  /// the success haptic), and sends that state. A finished todo leaves Today
  /// with the refetch that follows; the snackbar's "Geri al" reopens it and
  /// puts it back where it was.
  Future<void> _setTodoDone(Todo todo, {required bool done}) {
    final listed =
        ref.read(homeProvider).value?.data.upcomingTodos ?? const <Todo>[];
    final index = listed.indexWhere((t) => t.id == todo.id);
    return setTodoDone(
      context,
      ref,
      todo,
      done: done,
      index: index < 0 ? listed.length : index,
    );
  }

  /// Logs [habit] for today here and on the Habits tab in the same frame;
  /// the server's answer then refreshes streaks, goals and the rest. The
  /// ring is done or not; a daily habit that counts more than once a day
  /// goes up one per tap, and once it is full a tap opens its log, where it
  /// can step back. Quick taps all count: one made while the habit's
  /// previous tap is still waiting for the server shows at once and is sent
  /// after it (see [HabitActions]).
  Future<void> _tapHabit(HomeSummary home, HomeHabit habit) async {
    final actions = ref.read(habitActionsProvider);
    final counts = _counts(habit);
    if (counts && habit.todayCount >= habit.targetCount) {
      Haptics.tick();
      await showHabitLogSheet(context, habitId: habit.id);
      return;
    }
    final count = counts
        ? habit.todayCount + 1
        : (habit.completedToday ? 0 : habit.targetCount);

    // Fire the all-done celebration only on the transition (the last
    // remaining habit), judged on the rows Today shows.
    bool allDone() {
      final shown =
          ref.read(homeProvider).value?.data.todayHabits.take(6).toList() ??
              const <HomeHabit>[];
      return shown.isNotEmpty && shown.every((h) => h.completedToday);
    }

    final wasAllDone = allDone();
    // CheckPop fires Haptics.success on the completing tap — don't double-fire.
    final request = actions.setToday(habit.id, count, day: home.today);
    // The optimistic patch has landed by the time setToday returns.
    if (!wasAllDone && allDone()) Haptics.celebrate();
    try {
      await request;
    } catch (e) {
      if (!mounted) return;
      final l = context.l10n;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.todayHabitUpdateFailed),
        isError: true,
      );
    }
  }

  /// Whether [habit]'s day is a count (a daily habit with a target above
  /// one) rather than done or not. `/home` does not say how often a habit
  /// repeats; the habit payloads read so far do (see `HabitCadence`, which
  /// reads the Habits list once when `/home` lists a habit none of them
  /// named — and which the build watches, to redraw once it knows). Until
  /// then the ring is done or not, which holds for any habit: a count would
  /// misstate a weekly or monthly habit, whose target is days, not taps.
  bool _counts(HomeHabit habit) =>
      habit.targetCount > 1 &&
      (ref.read(habitActionsProvider).isDaily(habit.id) ?? false);

  void _openHabitLog(HomeHabit habit) {
    Haptics.tick();
    showHabitLogSheet(context, habitId: habit.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final async = ref.watch(homeProvider);
    // Which habits count within the day ([_counts]): redrawn once known.
    ref.watch(habitCadenceProvider);
    final fetched = async.value;

    Widget body;
    if (fetched != null) {
      body = _content(
        context,
        fetched.data,
        showOffline: async.refreshFailed,
        lastUpdated: fetched.at,
      );
    } else if (async.hasFailed) {
      body = _errorState(context);
    } else {
      body = const TodaySkeleton();
    }

    return primaryScroll(Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: SyncHint.over(active: async.isRefetching, child: body),
      ),
    ));
  }

  Widget _errorState(BuildContext context) {
    final l = context.l10n;
    return EmptyState(
      icon: Icons.cloud_off,
      title: l.errServerUnreachable,
      subtitle: l.errCheckWifi,
      actionLabel: l.actionRetry,
      onAction: _retry,
      secondaryLabel: l.errServerSettings,
      onSecondary: () => context.push('/profile/server'),
    );
  }

  Widget _content(
    BuildContext context,
    HomeSummary data, {
    required bool showOffline,
    required DateTime lastUpdated,
  }) {
    final c = context.nok;
    final animate = !_animatedOnce;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animatedOnce = true;
      });
    }

    return Column(
      children: [
        if (showOffline)
          OfflineBanner(
            lastUpdated: lastUpdated,
            onRetry: _retry,
          ),
        Expanded(
          child: RefreshIndicator.adaptive(
            color: c.gold,
            onRefresh: _refresh,
            child: CustomScrollView(
              primary: true,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _appBar(context)),
                const SliverToBoxAdapter(child: TodayZoneNotice()),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _stagger(_hero(context, data), 0, animate),
                      const SizedBox(height: 12),
                      _stagger(_statStrip(context, data), 1, animate),
                      const SizedBox(height: 32),
                      _stagger(
                        TodayAgenda(
                          home: data,
                          today: data.today ??
                              ref.watch<DateTime>(currentDayProvider),
                        ),
                        2,
                        animate,
                      ),
                      const SizedBox(height: 32),
                      _stagger(_todosSection(context, data), 3, animate),
                      const SizedBox(height: 32),
                      _stagger(_habitsSection(context, data), 4, animate),
                      const SizedBox(height: 32),
                      _stagger(_goalsSection(context, data), 5, animate),
                    ]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stagger(Widget child, int index, bool animate) =>
      Entrance.staggered(play: animate, index: index, child: child);

  // --- App bar ---------------------------------------------------------------

  Widget _appBar(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final greeting = context.l10n.greeting(DateTime.now().hour);
    final name = user?.displayName ?? '';
    final initials = user?.initials ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: text.bodyMedium!.copyWith(color: c.inkMid)),
                if (name.isNotEmpty)
                  Text(
                    name,
                    style: text.headlineLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showQuickCaptureSheet(context),
            icon: const Icon(Icons.bolt),
            color: c.gold,
            tooltip: context.l10n.todayQuickCapture,
          ),
          const SizedBox(width: 4),
          _Avatar(initials: initials, onTap: () => context.push('/profile')),
        ],
      ),
    );
  }

  // --- Hero ------------------------------------------------------------------

  Widget _hero(BuildContext context, HomeSummary data) {
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.todayMonthNet, style: text.labelMedium),
          const SizedBox(height: 8),
          MoneyText(
            data.monthNetCents,
            currency: data.currency,
            subunitToUnit: data.subunitToUnit,
            variant: MoneyVariant.hero,
            signed: true,
            positiveGreen: true,
          ),
          const SizedBox(height: 12),
          Sparkline(
            values: data.spending7d.map((p) => p.cents.toDouble()).toList(),
          ),
        ],
      ),
    );
  }

  // --- Stat strip ------------------------------------------------------------

  Widget _statStrip(BuildContext context, HomeSummary data) {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(
          child: StatChip(
            value: '🔥 ${data.activeStreaks}',
            label: l.todayStatStreak,
            onTap: () => context.go('/habits'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatChip(
            value: '${data.openTodos}',
            label: l.todayStatOpenTodos,
            onTap: () => context.push('/todos'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatChip(
            value: l.percent(data.habitCompletionPct),
            label: l.todayStatWeek,
            onTap: () => context.go('/habits'),
          ),
        ),
      ],
    );
  }

  // --- Todos section ---------------------------------------------------------

  /// The open todos due in the next seven days, overdue ones included (as
  /// `/home` lists them), a row that adds one for today, and the way to
  /// every open todo — undated ones too — on the Todos screen.
  Widget _todosSection(BuildContext context, HomeSummary data) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final hidden = ref.watch(deferredDeletesProvider);
    final todos = withoutDeleted(
      data.upcomingTodos,
      hidden,
      DataScope.todos,
      (t) => t.id,
    );
    final today = data.today ?? ref.read<DateTime>(currentDayProvider);
    // Keyed, so a row's check state follows its todo when the list shifts
    // after a refetch.
    final rows = <Widget>[
      for (final (i, t) in todos.indexed)
        TodoRow(
          key: ValueKey('todo-${t.id}'),
          todo: t,
          done: t.isDone,
          onToggle: () => _setTodoDone(t, done: !t.isDone),
          onTap: () => openTodoSheet(context, existing: t),
          onLongPress: () =>
              showTodoMenu(context, ref, t, done: t.isDone, index: i),
        ),
      if (todos.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            l.todoNoneUpcoming,
            style: text.bodyMedium!.copyWith(color: c.inkLow),
          ),
        ),
      _InlineAction(
        key: const ValueKey('todo-add'),
        icon: Icons.add,
        label: l.todoAddInline,
        onTap: () => openTodoSheet(context, due: today),
      ),
      if (data.openTodos > todos.where((t) => !t.isDone).length)
        _InlineAction(
          icon: Icons.checklist,
          label: l.todoAllOpen(data.openTodos),
          onTap: () => context.push('/todos'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.titleTodos,
          onSeeAll: () => context.push('/todos'),
        ),
        NokturnCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _withDividers(rows),
        ),
      ],
    );
  }

  // --- Habits section --------------------------------------------------------

  Widget _habitsSection(BuildContext context, HomeSummary data) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final habits = data.todayHabits.take(6).toList();
    final allDone = habits.isNotEmpty && habits.every((h) => h.completedToday);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.titleHabits,
          trailing: allDone
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.goldContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l.todayAllHabitsDone,
                    style: text.labelSmall!.copyWith(color: c.onGoldContainer),
                  ),
                )
              : null,
        ),
        if (habits.isEmpty)
          _emptyCard(
            context,
            Icons.check_circle_outline,
            l.todayNoHabitsYet,
          )
        else
          NokturnCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _withDividers([
              for (final h in habits)
                HomeHabitRow(
                  key: ValueKey('habit-${h.id}'),
                  habit: h,
                  counts: _counts(h),
                  onTap: () => _tapHabit(data, h),
                  onLongPress: () => _openHabitLog(h),
                ),
            ]),
          ),
      ],
    );
  }

  // --- Goals section ---------------------------------------------------------

  Widget _goalsSection(BuildContext context, HomeSummary data) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    // A goal being deleted leaves Today at once, as it leaves the Goals tab.
    final goals = withoutDeleted(
      data.activeGoals,
      ref.watch(deferredDeletesProvider),
      DataScope.goals,
      (g) => g.id,
    ).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l.titleGoals),
        if (goals.isEmpty)
          _emptyCard(
            context,
            Icons.flag_outlined,
            l.todayNoGoalsYet,
          )
        else
          NokturnCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _withDividers([
              for (final g in goals)
                InkWell(
                  onTap: () => context.push('/goals/${g.id}'),
                  splashColor: c.gold.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.name,
                                style: text.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              PacedProgressBar(
                                value: g.progressPercent / 100,
                                color: hexColor(g.color, fallback: c.gold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '%${g.progressPercent.round()}',
                          style: text.labelSmall!.copyWith(color: c.inkMid),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
      ],
    );
  }

  // --- Helpers ---------------------------------------------------------------

  /// Warm inline empty-section card: friendly icon over Turkish copy.
  Widget _emptyCard(BuildContext context, IconData icon, String message) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: c.inkLow),
            const SizedBox(height: 10),
            Text(
              message,
              style: text.bodyMedium!.copyWith(color: c.inkLow),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _withDividers(List<Widget> rows) {
    final c = context.nok;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(
          height: 1,
          thickness: 1,
          indent: 20,
          endIndent: 20,
          color: c.divider,
        ));
      }
      children.add(rows[i]);
    }
    return Column(children: children);
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final VoidCallback onTap;

  const _Avatar({required this.initials, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.goldContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: text.labelMedium!.copyWith(
            color: c.gold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A row of a Today card that leads somewhere: "＋ Görev ekle", every open
/// todo. A 48 dp target.
class _InlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: c.gold.withValues(alpha: 0.08),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Icon(icon, size: 20, color: c.gold),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: text.labelLarge!.copyWith(color: c.gold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
