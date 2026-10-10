import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../flows/flows.dart';
import '../../widgets/capture_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_bar_scrim.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'widgets/nudges.dart';
import 'widgets/start_card.dart';
import 'widgets/today_agenda.dart';
import 'widgets/today_goals.dart';
import 'widgets/today_habits.dart';
import 'widgets/today_header.dart';
import 'widgets/today_journal.dart';
import 'widgets/today_skeleton.dart';

/// Bugün (design-analysis §7.2): the day at a glance, habits first.
///
/// Top to bottom: the header (date, greeting, avatar) with its chips — this
/// month's net and what is next — then the nudge slot (one card at most),
/// the habits (the hero: the first ring sits within the first screen), the
/// Today card (todos and events, with an add row), goals and the journal.
/// The capture bar is pinned at the bottom, over the navigation bar.
///
/// Each section is its own widget that reads only its part of `/home`
/// (`select`), so ticking a habit rebuilds the habits — not the header,
/// not the money.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with TabRootScroll<TodayScreen> {
  @override
  AppTab get tab => AppTab.today;

  /// Pull-to-refresh: Today summarises every domain, so it syncs everything.
  Future<void> _refresh() async {
    Haptics.armed();
    refreshTab(ref, AppTab.today);
    await settleRefresh([
      refetchLanded(ref, homeProvider),
    ], minimum: Motion.refreshMinimum);
  }

  void _retry() => ref.read(dataSyncProvider).refresh([homeProvider]);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    // What the money chip and the first-run card wait on loads beside
    // `/home`, not after it: the chip's bone lasts one round trip at most.
    ref.listen(accountsProvider, (_, _) {});
    ref.listen(journalProvider(todayJournalRange), (_, _) {});
    final view = ref.watch(
      homeProvider.select(
        (a) => (
          phase: a.value != null
              ? LoadPhase.content
              : a.hasFailed
              ? LoadPhase.error
              : LoadPhase.waiting,
          offline: a.value != null && a.refreshFailed,
          at: a.value?.at,
          refetching: a.isRefetching,
        ),
      ),
    );

    return primaryScroll(
      Scaffold(
        backgroundColor: c.bg,
        body: EntranceHost(
          child: CaptureBarLayout(
            body: StatusBarScrim.over(
              child: LoadPhaseSwitcher(
                phase: view.phase,
                skeleton: (_) => const TodaySkeleton(),
                error: (_) => _errorState(context),
                content: (_) => _content(
                  context,
                  offline: view.offline,
                  lastUpdated: view.at,
                  refetching: view.refetching,
                ),
              ),
            ),
            bar: CaptureBar(
              label: l.todayCaptureLabel,
              onOpen: () => openQuickAdd(context),
              secondaryIcon: Icons.payments_outlined,
              secondaryTooltip: l.todayCaptureTransaction,
              onSecondary: () => openTransactionForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: Insets.captureBarClearance),
      child: EmptyState.error(
        onRetry: _retry,
        onServerSettings: () => context.push('/profile/server'),
      ),
    ),
  );

  Widget _content(
    BuildContext context, {
    required bool offline,
    required DateTime? lastUpdated,
    required bool refetching,
  }) {
    final c = context.nok;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    // Sections, in order; each plays the first-load entrance once (the
    // gate decides), staggered.
    const sections = <Widget>[
      TodayHeader(),
      SizedBox(height: Gap.lg),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: Insets.gutter),
        child: TodayNudgeSlot(),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: Insets.gutter),
        child: TodayHabitsSection(),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(Insets.gutter, Gap.xxl, Insets.gutter, 0),
        child: TodayAgendaSection(),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(Insets.gutter, Gap.xxl, Insets.gutter, 0),
        child: TodayGoalsSection(),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(Insets.gutter, Gap.xxl, Insets.gutter, 0),
        child: TodayJournalSection(),
      ),
    ];

    final list = RefreshIndicator.adaptive(
      color: c.gold,
      edgeOffset: offline ? 0 : top,
      onRefresh: _refresh,
      child: CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: offline ? 0 : top,
              bottom: Insets.captureBarClearance + Gap.lg + bottom,
            ),
            sliver: SliverList.list(
              children: [
                for (final (i, section) in sections.indexed)
                  Entrance.staggered(play: true, index: i, child: section),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        if (offline && lastUpdated != null)
          Padding(
            padding: EdgeInsets.only(top: top),
            child: OfflineBanner(lastUpdated: lastUpdated, onRetry: _retry),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: list),
              Positioned(
                top: offline ? 0 : top,
                left: 0,
                right: 0,
                child: IgnorePointer(child: SyncHint(active: refetching)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
