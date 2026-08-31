import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/slide_up_route.dart';
import 'goal_card.dart';
import 'goal_form.dart';
import 'goal_ui.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  bool _firstLoad = true;

  Future<void> _refresh() async {
    Haptics.celebrate();
    ref.invalidate(goalsProvider);
    await ref.read(goalsProvider.future);
  }

  void _openForm() {
    Navigator.of(context, rootNavigator: true).push(
      slideUpModalRoute((_) => const GoalFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(goalsProvider);
    final bundle = async.value?.data;

    if (bundle != null && _firstLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _firstLoad) setState(() => _firstLoad = false);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.titleGoals, style: text.headlineLarge)),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator.adaptive(
        color: c.gold,
        onRefresh: _refresh,
        child: _body(async, bundle),
      ),
    );
  }

  Widget _body(AsyncValue<Fetched<GoalsBundle>> async, GoalsBundle? bundle) {
    final l = context.l10n;
    if (bundle == null) {
      if (async.isLoading) return const _GoalsSkeleton();
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: EmptyState(
              icon: Icons.cloud_off,
              title: l.errServerUnreachable,
              subtitle: l.errCheckWifi,
              actionLabel: l.actionRetry,
              onAction: () => ref.invalidate(goalsProvider),
            ),
          ),
        ],
      );
    }

    final empty =
        bundle.active.isEmpty &&
        bundle.achieved.isEmpty &&
        bundle.abandoned.isEmpty;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (async.hasError)
          SliverToBoxAdapter(
            child: OfflineBanner(
              lastUpdated: async.value?.at ?? DateTime.now(),
              onRetry: () => ref.invalidate(goalsProvider),
            ),
          ),
        if (empty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.flag_outlined,
              title: l.goalsSetFirst,
              subtitle: l.goalsSetFirstBody,
              actionLabel: l.goalsAdd,
              onAction: _openForm,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (bundle.active.isNotEmpty) ...[
                  SectionHeader(l.goalsSectionActive),
                  ..._activeGrid(bundle.active),
                  const SizedBox(height: 32),
                ],
                if (bundle.achieved.isNotEmpty) ...[
                  _CollapsedGoals(
                    title: l.goalsSectionAchieved,
                    goals: bundle.achieved,
                    achieved: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (bundle.abandoned.isNotEmpty)
                  _CollapsedGoals(
                    title: l.goalsSectionAbandoned,
                    goals: bundle.abandoned,
                    achieved: false,
                  ),
              ]),
            ),
          ),
      ],
    );
  }

  List<Widget> _activeGrid(List<Goal> active) {
    final rows = <Widget>[];
    for (var i = 0; i < active.length; i += 2) {
      final left = active[i];
      final right = (i + 1 < active.length) ? active[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _staggered(i, GoalCard(goal: left))),
              const SizedBox(width: 12),
              Expanded(
                child: right == null
                    ? const SizedBox()
                    : _staggered(i + 1, GoalCard(goal: right)),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < active.length) rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  Widget _staggered(int index, Widget child) {
    if (!_firstLoad || index >= 6) return child;
    return child
        .animate(delay: (50 * index).ms)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.06, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

/// Collapsed achieved / abandoned section — flat rows.
class _CollapsedGoals extends StatelessWidget {
  final String title;
  final List<Goal> goals;
  final bool achieved;

  const _CollapsedGoals({
    required this.title,
    required this.goals,
    required this.achieved,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('$title (${goals.length})', style: text.titleMedium),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final g in goals)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      achieved ? Icons.check_circle : Icons.flag_outlined,
                      size: 20,
                      color: achieved ? c.income : c.inkLow,
                    ),
                    title: Text(
                      g.name,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      goalTargetLabel(g),
                      style: text.bodySmall!.copyWith(
                        color: achieved ? c.income : c.inkMid,
                        fontFeatures: tabularFigures,
                      ),
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

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Goal bone(int i) => Goal(
      id: i,
      name: '',
      description: '',
      targetType: 'custom',
      status: 'active',
      color: '#D4A853',
      unit: 'birim',
      daysRemaining: 30,
      deadlineBadge: const DeadlineBadge(state: 'far', days: 30),
      targetValue: 100,
      currentValue: 40,
      progressPercent: 40,
    );

    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          SectionHeader(l.goalsSectionActive),
          for (var r = 0; r < 2; r++)...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: GoalCard(goal: bone(r * 2))),
                  const SizedBox(width: 12),
                  Expanded(child: GoalCard(goal: bone(r * 2 + 1))),
                ],
              ),
            ),
            if (r == 0) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
