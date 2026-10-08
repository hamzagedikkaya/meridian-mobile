import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/home.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../today/widgets/today_common.dart';
import 'widgets/habit_check.dart';

/// Today's log of one habit, to set it exactly: a counter steps down as well
/// as up, a done day can be undone, and "Tamamla" / "Sıfırla" jump to either
/// end. What a long-press on a Today ring opens, and a tap on a counter that
/// is already full (another +1 could do nothing).
///
/// Every change writes the count the user picked (`HabitActions.setToday`),
/// shown at once here, on Today and on Habits. The sheet reads the habit
/// from `/home` as it updates, so it always shows what the server has with
/// the taps on their way on top.
Future<void> showHabitLogSheet(BuildContext context, {required int habitId}) {
  final c = context.nok;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // However tall large text makes it, the sheet stops below the status
    // bar, and scrolls (see the build).
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    backgroundColor: c.surface3,
    builder: (_) => _HabitLogSheet(habitId: habitId),
  );
}

class _HabitLogSheet extends ConsumerStatefulWidget {
  final int habitId;

  const _HabitLogSheet({required this.habitId});

  @override
  ConsumerState<_HabitLogSheet> createState() => _HabitLogSheetState();
}

class _HabitLogSheetState extends ConsumerState<_HabitLogSheet> {
  /// Why the last change did not go through, shown in the sheet: a
  /// snackbar would sit under it.
  String? _error;

  Future<void> _set(HomeSummary home, HomeHabit habit, int count) async {
    final l = context.l10n;
    final daily = ref.read(habitActionsProvider).isDaily(habit.id) ?? false;
    final log = habit.logFor(count, daily: daily);
    if (log.completed && !habit.completedToday) {
      Haptics.success();
    } else {
      Haptics.tick();
    }
    setState(() => _error = null);
    try {
      await ref
          .read(habitActionsProvider)
          .setToday(habit.id, count, day: home.today);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      setState(() {
        _error = failureMessage(e, l, fallback: l.todayHabitUpdateFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final home = ref.watch(homeProvider).value?.data;
    final habit = home?.todayHabits
        .where((h) => h.id == widget.habitId)
        .firstOrNull;
    if (home == null || habit == null) {
      // Archived or deleted meanwhile: nothing left to log.
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.errNotFound, style: text.bodyMedium),
        ),
      );
    }
    // A count to step only for a daily habit; done or not for any other,
    // and — as on Today — while how often it repeats is not known yet.
    final daily = ref.watch(habitCadenceProvider)[habit.id] ?? false;
    final counts = daily && habit.targetCount > 1;
    final color = hexColor(habit.color, fallback: c.gold);
    final done = habit.completedToday;

    // Under the drag handle every sheet gets from the theme. Scrolls when it
    // does not fit — 200% text on a small phone — rather than overflow.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              habit.name,
              style: text.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              l.habitLogToday,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: 24),
            if (counts)
              _Stepper(
                count: habit.todayCount,
                target: habit.targetCount,
                color: color,
                semantics: l.habitLogSemantics(
                  habit.name,
                  count: habit.todayCount,
                  target: habit.targetCount,
                  done: done,
                ),
                onSet: (count) => _set(home, habit, count),
              )
            else
              Row(
                children: [
                  Semantics(
                    label: l.habitLogSemantics(
                      habit.name,
                      count: habit.todayCount,
                      target: 1,
                      done: done,
                    ),
                    button: true,
                    checked: done,
                    child: HabitCheck(
                      completed: done,
                      color: color,
                      onTap: () =>
                          _set(home, habit, done ? 0 : habit.targetCount),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      done ? l.habitLogDone : l.habitLogNotDone,
                      style: text.bodyLarge,
                    ),
                  ),
                ],
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: text.bodySmall!.copyWith(color: c.error)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: habit.todayCount > 0 || done
                        ? () => _set(home, habit, 0)
                        : null,
                    child: Text(l.habitLogReset),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: done
                        ? null
                        : () => _set(home, habit, habit.targetCount),
                    child: Text(l.habitLogComplete),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `−  n / target  +` with 48 dp buttons.
class _Stepper extends StatelessWidget {
  final int count;
  final int target;
  final Color color;
  final String semantics;
  final ValueChanged<int> onSet;

  const _Stepper({
    required this.count,
    required this.target,
    required this.color,
    required this.semantics,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    Widget step(IconData icon, bool enabled, int next, String tooltip) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          iconSize: 24,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled ? () => onSet(next) : null,
          icon: Icon(icon),
        );
    final l = context.l10n;
    return Row(
      children: [
        step(Icons.remove, count > 0, count - 1, l.habitLogDecrease),
        Expanded(
          child: Semantics(
            label: semantics,
            liveRegion: true,
            excludeSemantics: true,
            child: Text(
              '$count / $target',
              textAlign: TextAlign.center,
              style: text.displayMedium!.copyWith(
                color: count >= target ? color : c.inkHi,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ),
        step(Icons.add, count < target, count + 1, l.habitLogIncrease),
      ],
    );
  }
}
