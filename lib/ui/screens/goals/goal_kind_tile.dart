import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';

/// The three kinds of goal, in the order the empty page and the form offer
/// them (design-analysis §7.11): savings, habit, custom — `target_type`
/// `financial`, `habit`, `custom`.
const goalKinds = ['financial', 'habit', 'custom'];

IconData goalKindIcon(String type) => switch (type) {
  'financial' => Icons.savings_outlined,
  'habit' => Icons.repeat_rounded,
  _ => Icons.flag_outlined,
};

String goalKindTitle(AppL10n l, String type) => switch (type) {
  'financial' => l.goalsKindSavings,
  'habit' => l.goalsKindHabit,
  _ => l.goalsKindCustom,
};

String goalKindBody(AppL10n l, String type) => switch (type) {
  'financial' => l.goalsKindSavingsBody,
  'habit' => l.goalsKindHabitBody,
  _ => l.goalsKindCustomBody,
};

/// One kind of goal as a 56 dp card: its icon, name and what it counts.
///
/// On the empty Goals page ([selected] null) it opens the form with that
/// kind chosen, a chevron at its end. In the form it is one of three
/// mutually exclusive choices: the chosen one has a gold edge and check.
class GoalKindTile extends StatelessWidget {
  final String type;
  final VoidCallback? onTap;

  /// Null on the empty page; in the form, whether this kind is chosen.
  final bool? selected;

  const GoalKindTile({
    super.key,
    required this.type,
    required this.onTap,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final chosen = selected ?? false;
    final duration = Motion.orInstant(context, Motion.quick);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: selected != null,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          borderRadius: Radii.mdAll,
          border: Border.all(
            color: chosen ? c.gold : c.hairline,
            width: chosen ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: chosen ? c.goldContainer : c.surface1,
          borderRadius: Radii.mdAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      goalKindIcon(type),
                      size: 24,
                      color: chosen ? c.onGoldContainer : c.gold,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            goalKindTitle(l, type),
                            style: text.titleSmall!.copyWith(
                              color: chosen ? c.onGoldContainer : c.inkHi,
                            ),
                          ),
                          Text(
                            goalKindBody(l, type),
                            style: text.bodySmall!.copyWith(
                              color: chosen ? c.onGoldContainer : c.inkMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    if (selected == null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.inkLow,
                      )
                    else
                      AnimatedOpacity(
                        duration: duration,
                        opacity: chosen ? 1 : 0,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: c.onGoldContainer,
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
