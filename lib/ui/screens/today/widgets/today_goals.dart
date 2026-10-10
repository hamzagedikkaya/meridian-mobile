import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/data_scope.dart';
import '../../../../data/deferred_deletes.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/entity_color.dart';
import '../../../widgets/nokturn_card.dart';
import '../../../widgets/paced_progress_bar.dart';
import '../../../widgets/section_header.dart';
import '../../goals/goal_form.dart';

/// Today's goals (design-analysis §7.2): at most three, the furthest along
/// first — `/home` carries no deadline to sort by — each a 60 dp row with
/// its name over a 6 dp bar and its percentage on the right. A row opens
/// the goal; "Tümü" the Goals page. With no goal, a ghost row "Bir hedef
/// koy" opens the goal form.
class TodayGoalsSection extends ConsumerWidget {
  const TodayGoalsSection({super.key});

  static const maxGoals = 3;

  /// How many times the goals were built: the rebuild test's counter.
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kDebugMode) debugBuilds++;
    final c = context.nok;
    final l = context.l10n;
    final all =
        ref.watch(homeProvider.select((a) => a.value?.data.activeGoals)) ??
        const <HomeGoal>[];
    // A goal being deleted leaves Today at once, as it leaves Goals.
    final goals =
        withoutDeleted(
          all,
          ref.watch(deferredDeletesProvider),
          DataScope.goals,
          (g) => g.id,
        ).indexed.toList()..sort((a, b) {
          final byProgress = b.$2.progressPercent.compareTo(
            a.$2.progressPercent,
          );
          return byProgress != 0 ? byProgress : a.$1.compareTo(b.$1);
        });
    final shown = [for (final (_, g) in goals.take(maxGoals)) g];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Goals is a page, not a tab: this is the way there (§6.1).
        SectionHeader(l.titleGoals, onSeeAll: () => context.push('/goals')),
        if (shown.isEmpty)
          GhostCard(
            icon: Icons.flag_outlined,
            message: l.todayNoGoalsYet,
            actionLabel: l.todaySetGoal,
            onAction: () => openGoalForm(context),
          )
        else
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, g) in shown.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: Insets.rowH,
                      endIndent: Insets.rowH,
                      color: c.divider,
                    ),
                  _GoalRow(goal: g),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final HomeGoal goal;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(goal.color, c);
    final percent = goal.progressPercent;
    return MergeSemantics(
      child: InkWell(
        onTap: () => context.push('/goals/${goal.id}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.rowH,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        goal.name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      PacedProgressBar(
                        value: (percent / 100).clamp(0.0, 1.0),
                        color: tone.fill,
                      ),
                    ],
                  ),
                ),
                // Never "%0": a goal not yet begun shows its empty bar alone.
                if (percent.round() > 0) ...[
                  const SizedBox(width: Gap.md),
                  Text(
                    l.percent(percent),
                    style: text.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
