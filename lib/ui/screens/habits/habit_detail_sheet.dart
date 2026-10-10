import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/habit.dart';
import '../../../data/recent_changes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/sync_hint.dart';
import '../goals/goal_form.dart';
import 'habit_card.dart';
import 'habit_form.dart';
import 'widgets/habit_calendar.dart';
import 'widgets/habit_day_cell.dart';

/// A habit's detail sheet (design-analysis §7.10), opened by a tap on its
/// card: it opens at 60 % and drags to 92 %.
///
/// * **Top**: the habit's dot and name, with a pencil (edit) and an X.
/// * **What it is**: "Günlük · 8/gün", "Başlangıç 20 Eylül".
/// * **How it goes**: streak (the flame), record and 30-day rate.
/// * **The month calendar**: every day from the habit's start through
///   today can be set — in this sheet, never a sheet over it; a past day's
///   log is never celebrated.
/// * **The last 84 days** as a heatmap.
/// * **The goals that count it** (`tracked_by_goals`), each opening its
///   goal; without any, a way to set one.
/// * **Archive** at the bottom, quiet (inkMid, not red: it can be undone).
///   It asks first only when goals count the habit. An archived habit is
///   restored here, and only then can it be deleted.
///
/// Watches `habitDetailProvider(id)`, so a check-in made elsewhere while it
/// is open refreshes it too.
Future<void> showHabitDetailSheet(BuildContext context, Habit initial) {
  return showNokSheet<void>(
    context,
    draggable: true,
    builder: (_) => _HabitDetailSheet(initial: initial),
  );
}

class _HabitDetailSheet extends ConsumerStatefulWidget {
  final Habit initial;
  const _HabitDetailSheet({required this.initial});

  @override
  ConsumerState<_HabitDetailSheet> createState() => _HabitDetailSheetState();
}

class _HabitDetailSheetState extends ConsumerState<_HabitDetailSheet> {
  /// An archive, restore or delete on its way.
  bool _busy = false;

  /// The month the calendar shows.
  late DateTime _month = monthOf(widget.initial.today.date);

  /// The calendar day being edited.
  late DateTime? _selected = widget.initial.canLog(widget.initial.today.date)
      ? dateOnly(widget.initial.today.date)
      : null;

  /// Counts set from the calendar that the habit shown does not have yet:
  /// shown at once, until a fetch that has them lands.
  final _wanted = <DateTime, int>{};

  /// Days whose count is being sent.
  final _sending = <DateTime>{};

  /// Why the last day change did not go through.
  String? _dayError;

  int get _id => widget.initial.id;

  /// A context that outlives the sheet, for the snackbar after it closes.
  BuildContext get _host => Navigator.of(context, rootNavigator: true).context;

  // --- Logging a day ---------------------------------------------------------

  /// Sets [day]'s count to [count]: shown at once, then sent. Today goes
  /// through [HabitActions] (Today and the Habits list flip with it); an
  /// earlier day is set with `PUT /habits/:id/logs/:date`, each change sent
  /// after the one before it, so the server ends on the last one.
  Future<void> _setDay(Habit habit, DateTime day, int count) async {
    final l = context.l10n;
    final d = dateOnly(day);
    setState(() {
      _wanted[d] = count;
      _dayError = null;
    });
    void failed(Object error) {
      Haptics.reject();
      if (!mounted) return;
      setState(() {
        _wanted.remove(d);
        _dayError = failureMessage(error, l, fallback: l.habitsToggleFailed);
      });
    }

    if (d == dateOnly(habit.today.date)) {
      try {
        final sent = await ref
            .read(habitActionsProvider)
            .setToday(habit.id, count, day: habit.today.date);
        if (!sent && mounted) setState(() => _wanted.remove(d));
      } catch (e) {
        failed(e);
      }
      return;
    }

    // A change already on its way picks this one up when it is answered.
    if (!_sending.add(d)) return;
    final repo = ref.read(repositoryProvider);
    int? sent;
    try {
      while (true) {
        final want = _wanted[d];
        if (want == null || want == sent) break;
        await repo.setHabitLog(habit.id, d, count: want);
        sent = want;
      }
    } catch (e) {
      failed(e);
    } finally {
      _sending.remove(d);
    }
  }

  /// [habit] with the counts set here that it does not have yet.
  Habit _withWanted(Habit habit) {
    var shown = habit;
    for (final MapEntry(key: day, value: count) in _wanted.entries) {
      shown = shown.withDayCount(day, count);
    }
    return shown;
  }

  // --- Actions ---------------------------------------------------------------

  Future<void> _edit(Habit habit) async {
    await openHabitForm(context, habit: habit);
  }

  /// Archives at once, with "Geri al". When goals count the habit, a
  /// dialog first says they freeze.
  Future<void> _archive(Habit habit) async {
    final l = context.l10n;
    final goals = habit.trackedByGoals ?? const <TrackingGoal>[];
    if (goals.isNotEmpty) {
      final ok = await showConfirmDialog(
        context,
        title: l.habitsArchiveTitle,
        message:
            '${l.habitsArchiveBody(habit.name)}\n\n'
            '${l.habitsArchiveFreezes(goals.map((g) => g.name).join(', '))}',
        confirmLabel: l.habitsArchive,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final host = _host;
    final repo = ref.read(repositoryProvider);
    final sync = ref.read(dataSyncProvider);
    try {
      // Silent, like every archive (§5.8): the snackbar says it went.
      await repo.archiveHabit(habit.id);
      if (mounted) Navigator.of(context).pop();
      if (!host.mounted) return;
      showAppSnack(
        host,
        l.habitsArchivedNamed(habit.name),
        actionLabel: l.actionUndo,
        onAction: () =>
            _restoreHabit(repo, host, habit, quiet: true, sync: sync),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.habitsArchiveFailed),
        isError: true,
      );
    }
  }

  Future<void> _unarchive(Habit habit) async {
    setState(() => _busy = true);
    final host = _host;
    final ok = await _restoreHabit(
      ref.read(repositoryProvider),
      host,
      habit,
      sync: ref.read(dataSyncProvider),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  /// Deletes for good, after the dialog [confirmDeleteHabit] shows.
  Future<void> _delete(Habit habit) async {
    if (!await confirmDeleteHabit(context, habit) || !mounted) return;
    final host = _host;
    final deletes = ref.read(deferredDeletesProvider.notifier);
    final repo = ref.read(repositoryProvider);
    Navigator.of(context).pop();
    if (!host.mounted) return;
    deleteHabitNow(host, deletes, repo, habit);
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(habitDetailProvider(_id));
    // A fetch that has the counts set here lands: they are the habit's now.
    ref.listen(habitDetailProvider(_id), (_, next) {
      if (next.isLoading || !next.hasValue || _wanted.isEmpty) return;
      setState(() => _wanted.removeWhere((day, _) => !_sending.contains(day)));
    });
    // The list's copy stands in until the detail arrives — or when it could
    // not be loaded, which the calendar's heading then says.
    final loaded = async.value?.data;
    final habit = _withWanted(loaded ?? widget.initial);
    return SyncHint.over(
      active: async.isRefetching,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, habit),
          Expanded(
            child: _content(
              context,
              habit,
              detailed: loaded != null,
              loading: async.isLoading,
              failed: async.hasFailed,
              gone: async.isGone,
            ),
          ),
        ],
      ),
    );
  }

  void _retry() =>
      ref.read(dataSyncProvider).refresh([habitDetailProvider(_id)]);

  /// The habit's dot and name (Fraunces), the pencil and the X.
  Widget _header(BuildContext context, Habit habit) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.sheetH, 0, Gap.sm, Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: tone.fill,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Semantics(
                header: true,
                child: Text(habit.name, style: text.headlineMedium),
              ),
            ),
          ),
          IconButton(
            tooltip: l.actionEdit,
            onPressed: _busy ? null : () => _edit(habit),
            icon: Icon(Icons.edit_outlined, color: c.inkMid),
          ),
          IconButton(
            tooltip: l.actionClose,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, size: 24, color: c.inkMid),
          ),
        ],
      ),
    );
  }

  /// [gone]: the server no longer has the habit (a 404) — deleted on the web
  /// or another device — which a retry cannot change, so none is offered.
  Widget _content(
    BuildContext context,
    Habit habit, {
    required bool detailed,
    required bool loading,
    required bool failed,
    required bool gone,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(habit.color, c);
    final goals = habit.trackedByGoals ?? const <TrackingGoal>[];

    // The calendar goes back as far as the chain read, never before the
    // habit started.
    final firstDay = [
      if (habit.chain.isNotEmpty) dateOnly(habit.chain.first.date),
      if (habit.startDate != null) dateOnly(habit.startDate!),
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final lastMonth = monthOf(habit.today.date);
    final firstMonth = firstDay == null ? lastMonth : monthOf(firstDay);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Semantics(
        header: true,
        child: Text(title, style: text.titleSmall),
      ),
    );

    // One column, built whole (a detail is short): the sheet's drag follows
    // its scroll.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        primary: true,
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          0,
          Insets.sheetH,
          Gap.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (habit.description.isNotEmpty) ...[
              Text(
                habit.description,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
              const SizedBox(height: Gap.md),
            ],
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                _pill(context, _cadence(l, habit)),
                if (habit.startDate case final start?)
                  _pill(
                    context,
                    l.habitsStartedOn(
                      formatDate(
                        start,
                        withYear: start.year != habit.today.date.year,
                      ),
                    ),
                  ),
              ],
            ),
            if (habit.archived) ...[
              const SizedBox(height: Gap.md),
              _note(context, Icons.archive_outlined, l.habitsArchivedNote),
            ],
            const SizedBox(height: Gap.xl),
            StatTileRow(
              tiles: [
                StatTile(
                  leading: habit.currentStreak > 0
                      ? Icon(
                          Icons.local_fire_department_rounded,
                          size: 16,
                          color: c.goldBright,
                        )
                      : null,
                  // Never "0": a broken streak is a new one.
                  value: habit.currentStreak > 0
                      ? '${habit.currentStreak}'
                      : '–',
                  label: l.habitsStatStreak,
                  semanticLabel: habit.currentStreak > 0
                      ? l.streakDays(habit.currentStreak)
                      : l.streakNewRecord(habit.longestStreak),
                ),
                StatTile(
                  value: '${habit.longestStreak}',
                  label: l.habitsStatRecord,
                ),
                StatTile(
                  value: l.percent(HabitCard.rateOf(habit)),
                  label: l.habitsStatRate30d,
                ),
              ],
            ),
            const SizedBox(height: Gap.xxl),
            Row(
              children: [
                Expanded(child: section(l.habitsCalendar)),
                if (loading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.gold,
                    ),
                  )
                else if (gone)
                  Text(
                    l.errNotFound,
                    style: text.bodySmall!.copyWith(color: c.inkMid),
                  )
                else if (failed) ...[
                  Icon(Icons.cloud_off_rounded, size: 14, color: c.inkMid),
                  const SizedBox(width: Gap.sm),
                  TextButton(onPressed: _retry, child: Text(l.actionRetry)),
                ],
              ],
            ),
            if (!habit.archived)
              Text(
                l.habitsCalendarHint,
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            const SizedBox(height: Gap.sm),
            HabitMonthCalendar(
              habit: habit,
              month: _month,
              selected: _selected,
              onSelect: (day) => setState(() {
                _selected = day;
                _dayError = null;
              }),
              onPrevious: _month.isAfter(firstMonth)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
              onNext: _month.isBefore(lastMonth)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
            ),
            if (_selected case final day?) ...[
              const SizedBox(height: Gap.md),
              HabitDayEditor(
                habit: habit,
                day: day,
                error: _dayError,
                onSet: (count) => _setDay(habit, day, count),
              ),
            ],
            const SizedBox(height: Gap.xxl),
            section(l.habitsLast84Days),
            const SizedBox(height: Gap.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: MiniHeatmap(
                chain: habit.chain,
                fill: tone.fill,
                today: habit.today.date,
                startDate: habit.startDate,
              ),
            ),
            const SizedBox(height: Gap.md),
            HabitDayLegend(fill: tone.fill),
            const SizedBox(height: Gap.xxl),
            section(l.habitsTrackingGoals),
            if (goals.isEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => openGoalForm(context),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(l.habitsSetGoal),
                ),
              )
            else
              Wrap(
                spacing: Gap.sm,
                runSpacing: 0,
                children: [
                  for (final g in goals)
                    NokChip(
                      key: ValueKey('tracking-goal-${g.id}'),
                      label: g.name,
                      icon: Icons.flag_outlined,
                      onTap: () {
                        final router = GoRouter.maybeOf(context);
                        Navigator.of(context).maybePop();
                        router?.push('/goals/${g.id}');
                      },
                    ),
                ],
              ),
            const SizedBox(height: Gap.xxl),
            if (!gone) ..._actions(context, habit, detailed: detailed),
          ],
        ),
      ),
    );
  }

  /// "Günlük · 8/gün", "Haftalık · 3 gün".
  static String _cadence(AppL10n l, Habit habit) => switch (habit.frequency) {
    'weekly' => l.habitsCadenceWeekly(habit.targetCount),
    'monthly' => l.habitsCadenceMonthly(habit.targetCount),
    _ => l.habitsCadenceDaily(habit.targetCount),
  };

  /// For an active habit, "Arşivle" — quiet, it can be undone. For an
  /// archived one, "Arşivden çıkar" first, and the delete 24 dp below it.
  List<Widget> _actions(
    BuildContext context,
    Habit habit, {
    required bool detailed,
  }) {
    final c = context.nok;
    final l = context.l10n;
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: c.gold),
    );
    if (!habit.archived) {
      return [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            // What it freezes is known once the detail is in.
            onPressed: _busy || !detailed ? null : () => _archive(habit),
            style: TextButton.styleFrom(
              foregroundColor: c.inkMid,
              minimumSize: Hit.minSize,
            ),
            icon: _busy
                ? spinner
                : const Icon(Icons.archive_outlined, size: 18),
            label: Text(l.habitsArchive),
          ),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: _busy ? null : () => _unarchive(habit),
        icon: _busy ? spinner : const Icon(Icons.unarchive_outlined, size: 18),
        label: Text(l.habitsUnarchive),
      ),
      // Deleted only from the archive: archiving is the safer way out of
      // the list, and comes first.
      const SizedBox(height: Gap.xxl),
      Center(
        child: TextButton.icon(
          // What a delete loses is known once the detail is in.
          onPressed: _busy || !detailed ? null : () => _delete(habit),
          style: TextButton.styleFrom(
            foregroundColor: c.error,
            minimumSize: Hit.minSize,
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(l.habitsDelete),
        ),
      ),
    ];
  }

  /// A labelSmall surface2 pill: "Günlük · 8/gün".
  Widget _pill(BuildContext context, String label) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.surface2,
        shape: StadiumBorder(side: BorderSide(color: c.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
      ),
    );
  }

  Widget _note(BuildContext context, IconData icon, String message) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: c.surface2, borderRadius: Radii.mdAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.inkMid),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brings [habit] back from the archive; says so on [host] unless [quiet]
/// (an undo needs no confirmation), and says why when it fails. Takes the
/// repository rather than a ref: an undo runs after the sheet has closed.
/// [sync] hears of it, so the habit's card grows back in, washed.
Future<bool> _restoreHabit(
  MeridianRepository repo,
  BuildContext host,
  Habit habit, {
  bool quiet = false,
  DataSync? sync,
}) async {
  final l = host.l10n;
  try {
    await repo.unarchiveHabit(habit.id);
    sync?.noteChange(DataScope.habits, habit.id, ChangeKind.restored);
    if (!quiet && host.mounted) {
      showAppSnack(host, l.habitsUnarchived(habit.name));
    }
    return true;
  } catch (e) {
    if (host.mounted) {
      showAppSnack(
        host,
        failureMessage(e, l, fallback: l.habitsUnarchiveFailed),
        isError: true,
      );
    }
    return false;
  }
}

/// Brings archived habit [habit] back, from a list row: [host] hears how it
/// went.
Future<bool> restoreHabit(WidgetRef ref, BuildContext host, Habit habit) =>
    _restoreHabit(
      ref.read(repositoryProvider),
      host,
      habit,
      sync: ref.read(dataSyncProvider),
    );

/// Asks before [habit] is deleted for good, saying what goes with it: its
/// logged days (`logged_days_count`) and the link of the goals that count
/// it. It cascades, so there is no undo. True to delete.
Future<bool> confirmDeleteHabit(BuildContext context, Habit habit) {
  final l = context.l10n;
  final goals = habit.trackedByGoals ?? const <TrackingGoal>[];
  return showConfirmDialog(
    context,
    title: l.habitsDeleteTitle(habit.name),
    message: l.habitsDeleteBody(
      days: habit.loggedDaysCount ?? 0,
      goals: goals.map((g) => g.name).join(', '),
    ),
    confirmLabel: l.actionDelete,
    destructive: true,
  );
}

/// Deletes [habit] now: it leaves every list at once, and the snackbar on
/// [host] says so once the server has; a refusal brings it back.
void deleteHabitNow(
  BuildContext host,
  DeferredDeletes deletes,
  MeridianRepository repo,
  Habit habit,
) {
  final l = host.l10n;
  deleteNow(
    host,
    deletes,
    record: (scope: DataScope.habits, id: habit.id),
    message: l.habitsDeleted(habit.name),
    send: () => repo.deleteHabit(habit.id),
    failedMessage: l.habitsDeleteFailed,
  );
}

/// Formats an archive date for the archived list.
String archivedOnLabel(AppL10n l, Habit habit) {
  final at = habit.archivedAt;
  if (at == null) return l.habitsArchived;
  return l.habitsArchivedOn(
    formatDate(at, withYear: at.year != appToday().year),
  );
}
