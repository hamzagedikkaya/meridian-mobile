import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/progress_ring.dart';
import 'deadline_badge.dart';
import 'goal_ui.dart';

/// Grid card for an active goal (design §4.6).
class GoalCard extends StatelessWidget {
  final Goal goal;

  const GoalCard({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = goalColor(goal.color);
    final pct = goal.progressPercent.clamp(0, 100).round();

    return NokturnCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('/goals/${goal.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dot + type overline and the deadline badge share a row when they
          // fit; a wide badge drops to its own line so the type label always
          // reads in full (never "ALIŞ…").
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    goalTypeOverline(context.l10n, goal.targetType),
                    style: text.labelMedium,
                  ),
                ],
              ),
              DeadlineBadgeChip(
                badge: goal.deadlineBadge,
                deadline: goal.deadline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: Text(
              goal.name,
              style: text.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Hero(
              tag: 'goal-ring-${goal.id}',
              flightShuttleBuilder: goalRingFlightShuttle,
              child: ProgressRing(
                value: pct / 100,
                color: color,
                center: Text(
                  context.l10n.percent(pct),
                  style:
                      text.titleSmall!.copyWith(fontFeatures: tabularFigures),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              goalProgressLabel(goal),
              style: text.bodySmall!
                  .copyWith(color: c.inkMid, fontFeatures: tabularFigures),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
