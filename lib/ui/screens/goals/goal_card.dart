import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/progress_ring.dart';
import 'deadline_badge.dart';
import 'goal_actions.dart';
import 'goal_ui.dart';

/// Grid card for an active goal (design-analysis §7.11) — one fixed
/// anatomy, so in a row of two the overline, the name's top, the ring and
/// the badge line up:
///
/// 1. a 20 dp top line: an 8 dp dot in the goal's colour, 6 dp, the type
///    overline (labelSmall w600, inkMid, one line) — the badge never here;
/// 2. 8 dp, the name (titleMedium, up to two lines);
/// 3. a spacer of at least 12 dp, which takes up what the taller card of
///    the row adds (the grid stretches both to one height);
/// 4. the 72 dp ring, centred, its percentage inside (labelLarge w600);
/// 5. 8 dp, the value line (numMeta inkMid) in a slot one line tall at
///    the current text scale: a long value shrinks its glyphs rather than
///    being cut, and never the slot, so the ring above it stays put;
/// 6. 8 dp, a badge slot ([badgeSlotHeight], 24 dp at 1.0×, growing with
///    the text): the deadline pill centred, or empty.
///
/// A tap opens the goal, carrying it along so the ring's Hero lands in the
/// detail's first frame; a long press offers its quick actions.
class GoalCard extends ConsumerWidget {
  final Goal goal;

  const GoalCard({super.key, required this.goal});

  /// The 24 dp slot at the card's foot that holds the deadline pill (or
  /// nothing): at the same height in every card of a row.
  static const badgeSlotKey = ValueKey('goal-card-badge-slot');

  /// The value line's slot under the ring.
  static const valueSlotKey = ValueKey('goal-card-value-slot');

  /// The badge slot's height at [scaler]: 24 dp, or the pill's own height
  /// (a labelSmall line, 3/3 dp inside, its 1 dp hairline) once larger
  /// text needs more, so the pill's text grows to 200 % too (§8.3). Every
  /// card of a row shares the scale, so the slots stay level.
  static double badgeSlotHeight(TextScaler scaler) =>
      math.max(24.0, scaler.scale(14) + 8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final tone = goalTone(goal, c);
    final pct = goal.progressPercent.clamp(0, 100).round();
    final scaler = MediaQuery.textScalerOf(context);
    final valueStyle = context.nokText.numMeta.copyWith(color: c.inkMid);

    return NokturnCard(
      variant: NokCardVariant.grid,
      onTap: () => context.push('/goals/${goal.id}', extra: goal),
      onLongPress: () => showGoalActions(context, ref, goal),
      // The long press's actions, reachable by TalkBack (§6.4); merged into
      // the card's one button.
      child: Semantics(
        customSemanticsActions: goalSemanticActions(context, ref, goal),
        child: _anatomy(context, tone, pct, scaler, valueStyle),
      ),
    );
  }

  Widget _anatomy(
    BuildContext context,
    EntityTone tone,
    int pct,
    TextScaler scaler,
    TextStyle valueStyle,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tone.fill,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  goalTypeOverline(l, goal.targetType),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: text.labelSmall!.copyWith(
                    color: c.inkMid,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          goal.name,
          style: text.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Gap.md),
        const Spacer(),
        Center(
          child: HeroMode(
            enabled: !Motion.reduced(context),
            child: Hero(
              tag: goalRingTag(goal.id),
              flightShuttleBuilder: goalRingFlightShuttle,
              transitionOnUserGestures: true,
              child: ProgressRing(
                value: pct / 100,
                color: tone.fill,
                center: goalRingCenter(
                  72,
                  Text(
                    l.percent(pct),
                    maxLines: 1,
                    style: text.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        // One line tall whatever the value's length: shrinking a long
        // value must not shorten the line, or this card's ring would sit
        // lower than its neighbour's.
        SizedBox(
          key: GoalCard.valueSlotKey,
          width: double.infinity,
          height: scaler.scale(valueStyle.fontSize!) * valueStyle.height!,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(goalValueLabel(goal), maxLines: 1, style: valueStyle),
          ),
        ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          key: GoalCard.badgeSlotKey,
          height: badgeSlotHeight(scaler),
          width: double.infinity,
          // Empty without a deadline: a FittedBox around nothing would
          // scale by 0 / 0.
          child: DeadlineBadgeChip.shows(goal.deadlineBadge, goal.deadline)
              ? Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: DeadlineBadgeChip(
                      badge: goal.deadlineBadge,
                      deadline: goal.deadline,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
