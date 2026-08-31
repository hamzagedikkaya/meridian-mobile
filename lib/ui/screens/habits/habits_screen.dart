import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/skeletons.dart';
import 'habit_card.dart';
import 'habit_detail_sheet.dart';
import 'habit_form.dart';
import 'widgets/confetti_burst.dart';
import 'widgets/perfect_day_dots.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() =>
      _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  HabitsBundle? _local;
  final Set<int> _inFlight = {};
  bool _showConfetti = false;
  bool _staggered = false;
  bool _staggerScheduled = false;

  // --- optimistic helpers ----------------------------------------------------

  Habit _copyToday(Habit h, HabitToday today, HabitPeriod? period) => Habit(
        id: h.id,
        name: h.name,
        description: h.description,
        frequency: h.frequency,
        targetCount: h.targetCount,
        color: h.color,
        goalId: h.goalId,
        currentStreak: h.currentStreak,
        longestStreak: h.longestStreak,
        completionRate30d: h.completionRate30d,
        today: today,
        period: period ?? h.period,
        chain: h.chain,
      );

  Habit _applyOptimistic(Habit h, int delta) {
    final HabitToday today;
    if (h.targetCount <= 1) {
      final completed = delta > 0;
      today = HabitToday(
          date: h.today.date, completed: completed, count: completed ? 1 : 0);
    } else {
      final nc = (h.today.count + delta).clamp(0, h.targetCount);
      today = HabitToday(
          date: h.today.date, completed: nc >= h.targetCount, count: nc);
    }
    HabitPeriod? period = h.period;
    if (period != null) {
      final wasDone = h.today.completed ? 1 : 0;
      final nowDone = today.completed ? 1 : 0;
      final nc =
          (period.completedCount + (nowDone - wasDone)).clamp(0, 9999);
      period = HabitPeriod(
        rangeStart: period.rangeStart,
        rangeEnd: period.rangeEnd,
        completedCount: nc,
        complete: nc >= h.targetCount,
      );
    }
    return _copyToday(h, today, period);
  }

  HabitsBundle _mergeResult(HabitsBundle cur, ToggleResult res) {
    final habits = cur.habits
        .map((h) => h.id == res.habit.id ? res.habit : h)
        .toList();
    return HabitsBundle(
      habits: habits,
      completedToday: res.completedToday,
      totalActive: res.totalActive,
      perfectDay: res.perfectDay,
    );
  }

  Future<void> _toggle(Habit habit, int delta) async {
    final base = _local;
    if (base == null || _inFlight.contains(habit.id)) return;

    final updated = _applyOptimistic(habit, delta);
    final habits =
        base.habits.map((h) => h.id == habit.id ? updated : h).toList();
    final completed = habits.where((h) => h.today.completed).length;
    final wasAllDone =
        base.totalActive > 0 && base.completedToday >= base.totalActive;
    final nowAllDone =
        base.totalActive > 0 && completed >= base.totalActive;

    setState(() {
      _local = HabitsBundle(
        habits: habits,
        completedToday: completed,
        totalActive: base.totalActive,
        perfectDay: base.perfectDay,
      );
      _inFlight.add(habit.id);
      if (nowAllDone && !wasAllDone) _showConfetti = true;
    });

    final becameComplete = updated.today.completed && !habit.today.completed;
    final becameIncomplete = !updated.today.completed && habit.today.completed;
    final isCheckRing = habit.targetCount <= 1;
    if (becameComplete) {
      Haptics.success();
    } else if (!(isCheckRing && becameIncomplete)) {
      // Counter ± ticks; a check-ring uncheck stays silent (§5).
      Haptics.tick();
    }
    if (nowAllDone && !wasAllDone) Haptics.celebrate();

    try {
      final res = await ref
          .read(repositoryProvider)
          .toggleHabitToday(habit.id, delta: delta);
      if (!mounted) return;
      setState(() => _local = _mergeResult(_local ?? base, res));
      ref.invalidate(habitsProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _local = base;
        if (nowAllDone && !wasAllDone) _showConfetti = false;
      });
      showAppSnack(context, context.l10n.habitsToggleFailed, isError: true);
    } finally {
      _inFlight.remove(habit.id);
    }
  }

  Future<void> _refresh() async {
    Haptics.celebrate();
    ref.invalidate(habitsProvider);
    try {
      await ref.read(habitsProvider.future);
    } catch (_) {/* banner surfaces the error */}
  }

  void _openHistory() {
    final bundle = _local;
    if (bundle == null) return;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.habitsPerfectHistory, style: text.titleLarge),
              const SizedBox(height: 16),
              PerfectDayDots(chain: bundle.perfectDay.chain, dot: 12),
              const SizedBox(height: 16),
              Text(
                l.habitsPerfectStreak(bundle.perfectDay.currentStreak,
                    bundle.perfectDay.longestStreak),
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final async = ref.watch(habitsProvider);

    ref.listen(habitsProvider, (_, next) {
      if (next.hasValue && _inFlight.isEmpty) {
        setState(() => _local = next.value!.data);
      }
    });
    if (_local == null) {
      final v = async.value;
      if (v != null) _local = v.data;
    }

    final l = context.l10n;
    final bundle = _local;
    final firstLoading = async.isLoading && bundle == null;
    final showOffline = async.hasError && bundle != null;
    final showErrorState = async.hasError && bundle == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.titleHabits),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: l.habitsHistory,
            onPressed: bundle == null ? null : _openHistory,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openHabitForm(context),
        child: const Icon(Icons.add),
      ),
      body: firstLoading
          ? const _HabitsSkeleton()
          : showErrorState
              ? EmptyState(
                  icon: Icons.cloud_off,
                  title: l.errServerUnreachable,
                  subtitle: l.errCheckWifi,
                  actionLabel: l.actionRetry,
                  onAction: _refresh,
                )
              : RefreshIndicator.adaptive(
                  color: c.gold,
                  onRefresh: _refresh,
                  child: _content(context, bundle!, showOffline),
                ),
    );
  }

  Widget _content(BuildContext context, HabitsBundle bundle, bool offline) {
    final l = context.l10n;
    final habits = bundle.habits;

    if (habits.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (offline)
            SliverToBoxAdapter(
              child: OfflineBanner(
                lastUpdated:
                    ref.watch(habitsProvider).value?.at ?? DateTime.now(),
                onRetry: _refresh,
              ),
            ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: l.habitsCreateFirst,
              subtitle: l.habitsStartSmall,
              actionLabel: l.habitsAdd,
              onAction: () => openHabitForm(context),
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

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (offline)
          SliverToBoxAdapter(
            child: OfflineBanner(
              lastUpdated:
                  ref.watch(habitsProvider).value?.at ?? DateTime.now(),
              onRetry: _refresh,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          sliver: SliverList.list(
            children: [
              _todayCard(context, bundle),
              const SizedBox(height: 12),
              _perfectChainCard(context, bundle),
              const SizedBox(height: 32),
              for (var i = 0; i < habits.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _habitCard(habits[i], i, stagger),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _habitCard(Habit habit, int index, bool stagger) {
    final card = HabitCard(
      habit: habit,
      onToggle: (delta) => _toggle(habit, delta),
      onOpen: () => showHabitDetailSheet(context, habit),
    );
    if (!stagger || index >= 6) return card;
    return card
        .animate()
        .fadeIn(duration: 300.ms, delay: (50 * index).ms)
        .slideY(begin: 0.06, duration: 300.ms, delay: (50 * index).ms);
  }

  Widget _todayCard(BuildContext context, HabitsBundle bundle) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final total = bundle.totalActive;
    final done = bundle.completedToday;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final allDone = total > 0 && done >= total;

    return NokturnCard(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(context.l10n.habitsDoneOfTotal(done, total),
                        style: text.titleLarge),
                  ),
                  if (allDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.goldContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(context.l10n.habitsAllDone,
                          style: text.labelSmall!
                              .copyWith(color: c.onGoldContainer)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              PacedProgressBar(value: pct, color: c.gold, height: 8),
            ],
          ),
          if (_showConfetti)
            Positioned.fill(
              child: ConfettiBurst(
                onDone: () {
                  if (mounted) setState(() => _showConfetti = false);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _perfectChainCard(BuildContext context, HabitsBundle bundle) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final pd = bundle.perfectDay;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.habitsPerfectChain, style: text.titleMedium),
          const SizedBox(height: 12),
          PerfectDayDots(chain: pd.chain),
          const SizedBox(height: 12),
          Text(
            l.habitsPerfectStreak(pd.currentStreak, pd.longestStreak),
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
      ),
    );
  }
}

/// First-load skeleton mirroring the real layout (design §4.5).
class _HabitsSkeleton extends StatelessWidget {
  const _HabitsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          NokturnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.habitsDoneOfTotal(3, 7), style: text.titleLarge),
                const SizedBox(height: 12),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NokturnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.habitsPerfectChain, style: text.titleMedium),
                const SizedBox(height: 12),
                Text(l.habitsPerfectStreak(0, 0), style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 32),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NokturnCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: c.surface2, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.habitsFormName,
                                    style: text.titleMedium),
                                const SizedBox(height: 4),
                                Text(l.habitsMeta(0, 0),
                                    style: text.bodySmall),
                              ],
                            ),
                          ),
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: c.surface2, shape: BoxShape.circle),
                          ),
                        ],
                      ),
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
