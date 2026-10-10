import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/check_pop.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/sync_hint.dart';

/// One habit's log for one day, to set it exactly (design-analysis §7.10):
/// what a long-press on a habit opens — on Today and on Habits — and
/// `openHabitLog`.
///
/// * **The day**: chips for today, yesterday and the five days before; a
///   [date] further back gets a chip of its own (any day from the habit's
///   start on can be logged, D13). Days before the habit started are off.
/// * **A count** (a daily habit done several times a day): "Ekle" adds what
///   is typed on the keypad to the day's count, "Ayarla" sets it; "+1 · +2
///   · +5 · Hedefe tamamla" step it. Never past the target: the server
///   clamps there (D12), so the steps that would go past it are off and a
///   digit that would is refused.
/// * **Done or not** for any other habit: the check.
/// * **"Sıfırla"** clears the day; **"Kaydet"** writes the count shown —
///   explicitly, `PUT /habits/:id/logs/:date` with that count — and closes.
///   Today's log goes through `HabitActions.setToday`, so Today and Habits
///   show it at once. A refusal keeps the sheet open with the reason.
///
/// Saving a past day never celebrates; nor does this sheet (the day's
/// celebration belongs to the controls on the lists).
///
/// The sheet reads the habit as it updates: today from `/home` (or the
/// Habits list), another day from the Habits list's two weeks — or, further
/// back, from the habit's year of history.
Future<void> showHabitLogSheet(
  BuildContext context, {
  required int habitId,
  DateTime? date,
}) {
  return showNokSheet<void>(
    context,
    builder: (_) => _HabitLogSheet(habitId: habitId, date: date),
  );
}

/// How a typed count is applied.
enum _Mode { add, set }

/// One day of the habit, as the sheet shows it.
typedef _DayLog = ({
  String name,
  String color,
  int target,
  int count,
  bool counts,

  /// Writes the day's count; null: the day cannot be logged (before the
  /// habit started, or not read yet).
  Future<void> Function(int count)? save,
});

class _HabitLogSheet extends ConsumerStatefulWidget {
  final int habitId;

  /// The day asked for; null: today.
  final DateTime? date;

  const _HabitLogSheet({required this.habitId, this.date});

  @override
  ConsumerState<_HabitLogSheet> createState() => _HabitLogSheetState();
}

class _HabitLogSheetState extends ConsumerState<_HabitLogSheet> {
  /// The day chosen with a chip; null: the one asked for.
  DateTime? _picked;

  /// The count the sheet shows instead of the day's; null: the day's.
  int? _draft;

  /// Digits typed on the keypad.
  String _typed = '';

  /// The count shown when the digits in [_typed] began: in Ekle they add
  /// to it, so a "+1" tapped before them stays.
  int? _typeBase;
  _Mode _mode = _Mode.add;
  int _rejected = 0;

  /// Why the last save did not go through, shown in the sheet: a snackbar
  /// would sit under it.
  String? _error;
  bool _saving = false;

  DateTime _today() {
    final home = ref.watch(homeProvider).value?.data;
    return dateOnly(home?.today ?? ref.watch(currentDayProvider));
  }

  void _pick(DateTime day) {
    setState(() {
      _picked = day;
      _draft = null;
      _typed = '';
      _error = null;
    });
  }

  void _setDraft(int? count) => setState(() {
    _draft = count;
    _error = null;
  });

  // --- Resolving the day --------------------------------------------------------

  /// The habit on [day], or the placeholder to show while it cannot be.
  (_DayLog?, Widget?) _resolve(BuildContext context, DateTime day) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final home = ref.watch(homeProvider).value?.data;
    final today = _today();
    final list = ref.watch(habitsProvider);
    final listed = list.value?.data.habits
        .where((h) => h.id == widget.habitId)
        .firstOrNull;

    if (day == today) {
      final row = home?.todayHabits
          .where((h) => h.id == widget.habitId)
          .firstOrNull;
      if (home != null && row != null) {
        // A count to step only for a daily habit; done or not for any
        // other, and — as on Today — while how often it repeats is not
        // known yet.
        final daily = ref.watch(habitCadenceProvider)[row.id] ?? false;
        return (
          (
            name: row.name,
            color: row.color,
            target: row.targetCount,
            count: row.todayCount,
            counts: daily && row.targetCount > 1,
            save: (int count) => _sent(
              ref
                  .read(habitActionsProvider)
                  .setToday(row.id, count, day: home.today),
            ),
          ),
          null,
        );
      }
      if (listed != null && dateOnly(listed.today.date) == day) {
        return (
          (
            name: listed.name,
            color: listed.color,
            target: listed.targetCount,
            count: listed.today.count,
            counts: listed.countsWithinDay,
            save: (int count) => _sent(
              ref
                  .read(habitActionsProvider)
                  .setToday(listed.id, count, day: listed.today.date),
            ),
          ),
          null,
        );
      }
    }

    if (listed == null) {
      final loading =
          (list.isLoading && !list.hasValue) ||
          (home == null && ref.watch(homeProvider).isLoading);
      return (
        null,
        loading
            ? const CircularProgressIndicator.adaptive()
            // Archived or deleted meanwhile: nothing left to log.
            : Text(l.errNotFound, style: text.bodyMedium),
      );
    }

    // The chain has every day from its first on (a day it leaves out has
    // nothing logged).
    final listCovers =
        listed.chain.isNotEmpty &&
        !day.isBefore(dateOnly(listed.chain.first.date));
    var habit = listed;
    var known = listCovers;
    if (listed.canLog(day) && !listCovers) {
      final detail = ref.watch(habitDetailProvider(widget.habitId));
      final loaded = detail.value?.data;
      if (loaded == null) {
        return (
          null,
          detail.hasFailed && !detail.isLoading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      detail.isGone
                          ? l.errNotFound
                          : failureMessage(
                              detail.error!,
                              l,
                              fallback: l.errServerUnreachable,
                            ),
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (!detail.isGone) ...[
                      const SizedBox(height: Gap.sm),
                      TextButton(
                        onPressed: () => ref.read(dataSyncProvider).refresh([
                          habitDetailProvider(widget.habitId),
                        ]),
                        child: Text(l.actionRetry),
                      ),
                    ],
                  ],
                )
              : const CircularProgressIndicator.adaptive(),
        );
      }
      habit = loaded;
      final t = dateOnly(loaded.today.date);
      known = !day.isBefore(
        DateTime(t.year, t.month, t.day - (habitHistoryDays - 1)),
      );
    }
    return (
      (
        name: habit.name,
        color: habit.color,
        target: habit.targetCount,
        count: habit.countOn(day),
        counts: habit.countsWithinDay,
        // Only a day whose count is known: a write from a guess would
        // overwrite what the day has.
        save: habit.canLog(day) && known
            ? (int count) => ref
                  .read(repositoryProvider)
                  .setHabitLog(habit.id, day, count: count)
            : null,
      ),
      null,
    );
  }

  /// A `setToday` that was taken back unsent (an earlier tap of the habit
  /// failed) did not save.
  Future<void> _sent(Future<bool> write) async {
    if (!await write) throw StateError('taken back');
  }

  // --- Saving -------------------------------------------------------------------

  Future<void> _save(_DayLog log) async {
    final save = log.save;
    if (save == null || _saving) return;
    final count = _draft ?? log.count;
    if (count == log.count) {
      Navigator.of(context).maybePop();
      return;
    }
    final l = context.l10n;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await save(count);
      Haptics.confirm();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      Haptics.reject();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is StateError
            ? l.todayHabitUpdateFailed
            : failureMessage(e, l, fallback: l.todayHabitUpdateFailed);
      });
    }
  }

  // --- Keypad -------------------------------------------------------------------

  /// What [typed] makes of [count] (the count shown before typing) in the
  /// current mode.
  int _apply(String typed, int count) {
    final value = int.tryParse(typed) ?? 0;
    return _mode == _Mode.add ? count + value : value;
  }

  void _digit(String d, _DayLog log) {
    final typed = _typed == '0' ? d : '$_typed$d';
    final base = _typed.isEmpty
        ? (_draft ?? log.count)
        : (_typeBase ?? log.count);
    final next = _apply(typed, base);
    if (next > log.target) {
      // Past the target: the server would clamp it.
      Haptics.reject();
      setState(() => _rejected++);
      return;
    }
    setState(() {
      _typed = typed;
      _typeBase = base;
      _draft = next;
      _error = null;
    });
  }

  void _backspace(_DayLog log) {
    if (_typed.isEmpty) return;
    final typed = _typed.substring(0, _typed.length - 1);
    final base = _typeBase ?? log.count;
    setState(() {
      _typed = typed;
      // Every digit gone: back to the count shown before them.
      _draft = typed.isNotEmpty
          ? _apply(typed, base)
          : base == log.count
          ? null
          : base;
    });
  }

  void _clearTyped() => setState(() {
    _typed = '';
    _draft = null;
  });

  // --- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final asked = widget.date == null ? today : dateOnly(widget.date!);
    final day = _picked ?? asked;
    final (log, placeholder) = _resolve(context, day);
    final busy =
        ref.watch(homeProvider).isRefetching ||
        ref.watch(habitsProvider).isRefetching;

    if (log == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.x3),
          child: Center(child: placeholder),
        ),
      );
    }
    // The sheet hugs its content: the hint lies over its top edge.
    return Stack(
      children: [
        _view(context, log, day: day, today: today, asked: asked),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(child: SyncHint(active: busy)),
        ),
      ],
    );
  }

  Widget _view(
    BuildContext context,
    _DayLog log, {
    required DateTime day,
    required DateTime today,
    required DateTime asked,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(log.color, c);
    final enabled = log.save != null;
    final count = _draft ?? log.count;
    final done = count >= log.target && count > 0;
    final subtitle = day == today
        ? l.habitLogToday
        : formatDate(day, withYear: day.year != today.year);

    final body = <Widget>[
      _DayChips(
        today: today,
        asked: asked,
        selected: day,
        startDate: _startDate(),
        onPick: _pick,
      ),
      const SizedBox(height: Gap.lg),
      if (log.counts)
        ..._counter(context, log, count: count, tone: tone, enabled: enabled)
      else
        Row(
          children: [
            CheckPop(
              checked: done,
              tone: tone,
              semanticLabel: l.habitLogSemantics(
                log.name,
                count: count,
                target: 1,
                done: done,
              ),
              // A day that cannot be logged: the tap changes nothing, and
              // the check plays nothing (it plays only when [checked]
              // follows the tap).
              onTap: () {
                if (enabled) _setDraft(done ? 0 : log.target);
              },
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Text(
                done
                    ? (day == today ? l.habitLogDone : l.habitsDayDone)
                    : (day == today ? l.habitLogNotDone : l.habitsDayNotDone),
                style: text.bodyLarge,
              ),
            ),
          ],
        ),
      if (!enabled) ...[
        const SizedBox(height: Gap.sm),
        Text(
          l.habitsDayCannotLog,
          style: text.bodySmall!.copyWith(color: c.inkMid),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: Gap.md),
        Text(_error!, style: text.bodySmall!.copyWith(color: c.error)),
      ],
    ];

    // Under the drag handle every sheet gets from the theme. The heading
    // and the body scroll when they do not fit — 200% text on a small
    // phone — and the buttons stay at the bottom.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetHeader(
                    title: log.name,
                    subtitle: subtitle,
                    showClose: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.sheetH,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: body,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.sheetH,
              Gap.md,
              Insets.sheetH,
              Gap.lg,
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: enabled && count > 0
                      ? () {
                          _typed = '';
                          _setDraft(0);
                        }
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: c.inkMid,
                    minimumSize: Hit.minSize,
                  ),
                  child: Text(l.habitLogReset),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: PrimaryButton(
                    label: l.actionSave,
                    loading: _saving,
                    onPressed: enabled ? () => _save(log) : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _counter(
    BuildContext context,
    _DayLog log, {
    required int count,
    required EntityTone tone,
    required bool enabled,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final target = log.target;
    final done = count >= target;
    Widget step(String label, int to, {Key? key}) => NokChip(
      key: key,
      label: label,
      enabled: enabled && to > count && count < target,
      onTap: enabled && count < target
          ? () {
              _typed = '';
              _setDraft(to.clamp(0, target));
            }
          : null,
    );
    return [
      SegmentedPill<_Mode>(
        expand: true,
        options: [(_Mode.add, l.habitLogAdd), (_Mode.set, l.habitLogSet)],
        selected: _mode,
        onChanged: (mode) => setState(() {
          _mode = mode;
          _typed = '';
          _draft = null;
        }),
      ),
      const SizedBox(height: Gap.lg),
      RejectShake(
        trigger: _rejected,
        child: Semantics(
          label: l.habitLogSemantics(
            log.name,
            count: count,
            target: target,
            done: done,
          ),
          liveRegion: true,
          excludeSemantics: true,
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                // It changes with every key: Inter's tabular figures keep
                // it still (Fraunces has none, §10.1-16).
                child: Text(
                  '$count / $target',
                  maxLines: 1,
                  style: context.nokText.numStat.copyWith(
                    fontSize: text.displayMedium!.fontSize,
                    height: text.displayMedium!.height,
                    color: done ? tone.text : c.inkHi,
                  ),
                ),
              ),
              Text(
                _mode == _Mode.add && _typed.isNotEmpty
                    ? l.habitLogNowPlus(
                        _typeBase ?? log.count,
                        int.parse(_typed),
                      )
                    : l.habitLogNow(log.count),
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: Gap.md),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: Gap.sm,
        children: [
          step(l.habitLogPlus(1), count + 1),
          step(l.habitLogPlus(2), count + 2),
          step(l.habitLogPlus(5), count + 5),
          step(
            l.habitLogToTarget,
            target,
            key: const ValueKey('habit-log-to-target'),
          ),
        ],
      ),
      const SizedBox(height: Gap.sm),
      AmountKeypad(
        showDecimal: false,
        onDigit: (d) {
          if (enabled) _digit(d, log);
        },
        onDot: () {},
        onBackspace: () => _backspace(log),
        onClear: _clearTyped,
      ),
    ];
  }

  /// When the habit started, as far as the Habits list says.
  DateTime? _startDate() => ref
      .watch(habitsProvider)
      .value
      ?.data
      .habits
      .where((h) => h.id == widget.habitId)
      .firstOrNull
      ?.startDate;
}

/// The days to log: today, yesterday, the five before — and the day asked
/// for when it is further back. Days before [startDate] are off.
class _DayChips extends StatelessWidget {
  final DateTime today;
  final DateTime asked;
  final DateTime selected;
  final DateTime? startDate;
  final ValueChanged<DateTime> onPick;

  const _DayChips({
    required this.today,
    required this.asked,
    required this.selected,
    required this.startDate,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(today.year, today.month, today.day - i),
    ];
    if (!days.contains(asked)) days.add(asked);
    String label(DateTime d) {
      if (d == today) return l.dayToday;
      if (d == DateTime(today.year, today.month, today.day - 1)) {
        return l.dayYesterday;
      }
      if (today.difference(d).inDays < 7) {
        return '${formatWeekdayShort(d)} ${d.day}';
      }
      return formatDate(d, withYear: d.year != today.year);
    }

    final start = startDate == null ? null : dateOnly(startDate!);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in days) ...[
            if (d != days.first) const SizedBox(width: Gap.sm),
            NokChip(
              key: ValueKey('habit-log-day-${isoDate(d)}'),
              label: label(d),
              selected: d == selected,
              exclusive: true,
              enabled: start == null || !d.isBefore(start),
              onTap: start != null && d.isBefore(start)
                  ? null
                  : () => onPick(d),
            ),
          ],
        ],
      ),
    );
  }
}
