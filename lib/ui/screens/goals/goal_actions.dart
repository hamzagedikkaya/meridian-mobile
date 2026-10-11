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

/// Tier 3 (design-analysis §4.30, §5.7): the user's own write took the goal
/// past 100 %. Once per goal ever (`milestone.goal.<id>`), with the CONFIRM
/// haptic; without a celebration layer (a test host) only the haptic.
void celebrateGoalReached(BuildContext context, Goal goal) {
  final layer = CelebrationLayer.maybeOf(context);
  if (layer == null) {
    Haptics.confirm();
    return;
  }
  layer.milestone(
    key: 'goal.${goal.id}',
    text: '${context.l10n.percent(100)} · ${goal.name}',
  );
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

/// Sets a goal logged by hand to a value typed on the keypad — the card's
/// long-press "İlerleme ekle". Taking it past 100 % is celebrated (tier 3).
Future<void> enterGoalProgress(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) async {
  final l = context.l10n;
  final host = Navigator.of(context, rootNavigator: true).context;
  final value = await showGoalValueSheet(
    context,
    title: l.goalsEnterValue,
    kind: goalValueKind(goal),
    initial: goal.currentValue,
  );
  if (value == null || !context.mounted) return;
  if (goalPercentOf(goal, goal.currentValue) < 100 &&
      goalPercentOf(goal, value) >= 100) {
    celebrateGoalReached(context, goal);
  }
  try {
    await ref
        .read(repositoryProvider)
        .goalUpdateProgress(goal.id, currentValue: value);
  } catch (e) {
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
