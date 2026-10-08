import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
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

/// Renders `habitsProvider` directly — no copy of it in State. A tick patches
/// the provider itself (through [HabitActions]), so this tab and Today flip
/// together, and a background refetch can never paint an older list over it.
class _HabitsScreenState extends ConsumerState<HabitsScreen>
    with TabRootScroll<HabitsScreen> {
  @override
  AppTab get tab => AppTab.habits;

  bool _showConfetti = false;

  /// Cards play their entrance only with the first data (see [Entrance]).
  bool _staggered = false;
  bool _staggerScheduled = false;

  /// Sets today's count of [habit] to [count] — what the card's tap asked
  /// for. Every tap counts, also while the habit's previous tap is still
  /// waiting for the server: [HabitActions] shows it at once and sends it
  /// next.
  Future<void> _log(Habit habit, int count) async {
    final actions = ref.read(habitActionsProvider);
    final bundle = ref.read(habitsProvider).value?.data;
    if (bundle == null) return;

    // What the tap will do, for the haptics and the all-done confetti.
    final log = habit.logFor(count);
    final after = bundle.withHabitToday(habit.id, log);
    final wasAllDone =
        bundle.totalActive > 0 && bundle.completedToday >= bundle.totalActive;
    final nowAllDone =
        after.totalActive > 0 && after.completedToday >= after.totalActive;
    final celebrate = nowAllDone && !wasAllDone;

    final becameComplete = log.completed && !habit.today.completed;
    final becameIncomplete = !log.completed && habit.today.completed;
    final isCheckRing = !habit.countsWithinDay;
    if (becameComplete) {
      Haptics.success();
    } else if (!(isCheckRing && becameIncomplete)) {
      // Counter ± ticks; a check-ring uncheck stays silent (§5).
      Haptics.tick();
    }
    if (celebrate) {
      Haptics.celebrate();
      setState(() => _showConfetti = true);
    }

    try {
      final sent =
          await actions.setToday(habit.id, count, day: habit.today.date);
      // Taken back unsent, with an earlier tap that failed (and said so).
      if (!sent && celebrate && mounted) {
        setState(() => _showConfetti = false);
      }
    } catch (e) {
      if (!mounted) return;
      if (celebrate) setState(() => _showConfetti = false);
      final l = context.l10n;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.habitsToggleFailed),
        isError: true,
      );
    }
  }

  Future<void> _refresh() async {
    Haptics.celebrate();
    refreshTab(ref, AppTab.habits);
    await settleRefresh([refetchLanded(ref, habitsProvider)]);
  }

  void _openHistory() {
    final bundle = ref.read(habitsProvider).value?.data;
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
    final fetched = async.value;

    final l = context.l10n;
    final bundle = fetched?.data;
    final firstLoading = async.isFirstLoad;
    final showOffline = async.refreshFailed;
    final showErrorState = async.hasFailed;

    return primaryScroll(Scaffold(
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
      body: SyncHint.over(
        active: async.isRefetching,
        child: firstLoading
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
                    child: _content(context, bundle!, showOffline, fetched!.at),
                  ),
      ),
    ));
  }

  Widget _content(
    BuildContext context,
    HabitsBundle bundle,
    bool offline,
    DateTime lastUpdated,
  ) {
    final l = context.l10n;
    final habits = bundle.habits;

    if (habits.isEmpty) {
      return CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (offline)
            SliverToBoxAdapter(
              child: OfflineBanner(
                lastUpdated: lastUpdated,
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
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (offline)
          SliverToBoxAdapter(
            child: OfflineBanner(
              lastUpdated: lastUpdated,
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
                // Keyed by habit, so a card's check state (and its fill
                // animation) follows its habit when the list shifts.
                Padding(
                  key: ValueKey('habit-${habits[i].id}'),
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
    return Entrance.staggered(
      play: stagger,
      index: index,
      child: HabitCard(
        habit: habit,
        onLog: (count) => _log(habit, count),
        onOpen: () => showHabitDetailSheet(context, habit),
      ),
    );
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
