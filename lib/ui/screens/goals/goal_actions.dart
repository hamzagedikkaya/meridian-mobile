import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/celebration_layer.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/nokturn_row.dart';
import 'goal_form.dart';
import 'goal_ui.dart';
import 'goal_value_sheet.dart';

/// How a goal's numbers are typed on the keypad: money in its currency, or
/// a count in its unit.
GoalValueKind goalValueKind(Goal g) {
  if (!goalIsFinancial(g)) return GoalValueKind.count(g.unit);
  final m = goalMoneyMeta(g);
  return GoalValueKind.money(currency: m.currency, subunit: m.subunit);
}

/// Tier 3 (design-analysis §4.30, §5.7): the user's own write takes the goal
/// past 100 % — celebrated at the tap, with the CONFIRM haptic (§5.8). Once
/// per goal ever (`milestone.goal.<id>`); without a celebration layer (a
/// test host) only the haptic.
///
/// Returns how to give the milestone back when the write that crossed it
/// is taken back before it goes, or refused — so the goal's real crossing
/// later still celebrates — or null when this call claimed nothing.
VoidCallback? celebrateGoalReached(BuildContext context, Goal goal) {
  final layer = CelebrationLayer.maybeOf(context);
  if (layer == null) {
    Haptics.confirm();
    return null;
  }
  final key = 'goal.${goal.id}';
  final claimed = layer.milestone(
    key: key,
    text: '${context.l10n.percent(100)} · ${goal.name}',
  );
  return claimed ? () => layer.forgetMilestone(key) : null;
}

/// Abandons [goal] at once, with "Geri al" (which reopens it) — the same
/// from the goal's screen and from its card's long press. The snackbar is
/// shown on the root navigator's context, so it outlives the screen. False
/// when the server refused (the snackbar says why).
Future<bool> abandonGoalWithUndo(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final host = Navigator.of(context, rootNavigator: true).context;
  try {
    await repo.abandonGoal(goal.id);
  } catch (e) {
    if (host.mounted) {
      showAppSnack(
        host,
        failureMessage(e, l, fallback: l.goalsActionFailed),
        isError: true,
      );
    }
    return false;
  }
  if (!host.mounted) return true;
  showAppSnack(
    host,
    l.goalsAbandonedSnack,
    actionLabel: l.actionUndo,
    onAction: () async {
      try {
        await repo.reopenGoal(goal.id);
      } catch (e) {
        if (host.mounted) {
          showAppSnack(
            host,
            failureMessage(e, l, fallback: l.goalsActionFailed),
            isError: true,
          );
        }
      }
    },
  );
  return true;
}

/// Adds what is typed on the keypad to a goal logged by hand — the card's
/// long-press "İlerleme ekle", which adds as it says: the keypad opens
/// empty, and the amount goes as `delta` (the server adds it to the
/// progress it has). Taking the goal past 100 % is celebrated (tier 3) as
/// the keypad closes; a write that fails gives the milestone back.
Future<void> enterGoalProgress(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) async {
  final l = context.l10n;
  final host = Navigator.of(context, rootNavigator: true).context;
  final repo = ref.read(repositoryProvider);
  final added = await showGoalValueSheet(
    context,
    title: l.goalsAddProgress,
    kind: goalValueKind(goal),
  );
  if (added == null || added == 0 || !context.mounted) return;
  final giveBack =
      goalPercentOf(goal, goal.currentValue) < 100 &&
          goalPercentOf(goal, goal.currentValue + added) >= 100
      ? celebrateGoalReached(host, goal)
      : null;
  try {
    await repo.goalUpdateProgress(goal.id, delta: added);
  } catch (e) {
    giveBack?.call();
    if (host.mounted) {
      showAppSnack(
        host,
        failureMessage(e, l, fallback: l.goalsProgressNotSaved),
        isError: true,
      );
    }
  }
}

/// A goal card's long press (design-analysis §6.4): "İlerleme ekle" (a goal
/// logged by hand) · "Düzenle" · "Bırak", in a sheet titled with the goal.
Future<void> showGoalActions(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) async {
  final l = context.l10n;
  final picked = await showNokSheet<String>(
    context,
    title: goal.name,
    entityTitle: true,
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (goal.isManual && goal.isActive)
              NokturnRow(
                leading: const Icon(Icons.dialpad_rounded),
                title: l.goalsAddProgress,
                onTap: () => Navigator.of(sheet).pop('progress'),
              ),
            NokturnRow(
              leading: const Icon(Icons.edit_outlined),
              title: l.actionEdit,
              onTap: () => Navigator.of(sheet).pop('edit'),
            ),
            if (goal.isActive)
              NokturnRow(
                leading: const Icon(Icons.flag_outlined),
                title: l.goalsAbandonAction,
                onTap: () => Navigator.of(sheet).pop('abandon'),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await _runGoalAction(context, ref, goal, picked);
}

Future<void> _runGoalAction(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
  String action,
) async {
  switch (action) {
    case 'progress':
      await enterGoalProgress(context, ref, goal);
    case 'edit':
      await openGoalForm(context, goal: goal);
    case 'abandon':
      await abandonGoalWithUndo(context, ref, goal);
  }
}

/// [showGoalActions]' choices as screen-reader actions (§6.4: every
/// long-press action is a custom semantics action too), running the same
/// handlers as the sheet.
Map<CustomSemanticsAction, VoidCallback> goalSemanticActions(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) {
  final l = context.l10n;
  void run(String action) => _runGoalAction(context, ref, goal, action);
  return {
    if (goal.isManual && goal.isActive)
      CustomSemanticsAction(label: l.goalsAddProgress): () => run('progress'),
    CustomSemanticsAction(label: l.actionEdit): () => run('edit'),
    if (goal.isActive)
      CustomSemanticsAction(label: l.goalsAbandonAction): () => run('abandon'),
  };
}
