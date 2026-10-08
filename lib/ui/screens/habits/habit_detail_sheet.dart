import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../theme/app_typography.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/sync_hint.dart';
import 'habit_form.dart';
import 'widgets/chain_row.dart';
import 'widgets/habit_calendar.dart';
import 'widgets/habit_visuals.dart';
import 'widgets/mini_heatmap.dart';

/// Habit detail bottom sheet (design-research §5.4): stats, a month
/// calendar whose days can be logged (today or any earlier day since the
/// habit started), the 30-day chain, the 84-day heatmap, and the habit's
/// actions — edit, archive (or restore, for an archived one) and delete.
///
/// Watches `habitDetailProvider(id)`, so a check-in made elsewhere while it
/// is open refreshes it too.
Future<void> showHabitDetailSheet(BuildContext context, Habit initial) {
  return showModalBottomSheet<void>(
    context: context,
    // Over the tab bar, like every sheet, and gone with the back gesture.
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
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
    Haptics.tick();
    void failed(Object error) {
      Haptics.danger();
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
    try {
      await repo.archiveHabit(habit.id);
      Haptics.tick();
      if (mounted) Navigator.of(context).pop();
      if (!host.mounted) return;
      showAppSnack(
        host,
        l.habitsArchivedNamed(habit.name),
        actionLabel: l.actionUndo,
        onAction: () => _restoreHabit(repo, host, habit, quiet: true),
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
    final ok = await _restoreHabit(ref.read(repositoryProvider), host, habit);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  /// Deletes after a dialog that says what goes with it: the logged days,
  /// and the link of the goals that count it. It cascades, so no undo.
  Future<void> _delete(Habit habit) async {
    final l = context.l10n;
    final goals = habit.trackedByGoals ?? const <TrackingGoal>[];
    final ok = await showConfirmDialog(
      context,
      title: l.habitsDeleteTitle(habit.name),
      message: l.habitsDeleteBody(
        days: habit.loggedDaysCount ?? 0,
        goals: goals.map((g) => g.name).join(', '),
      ),
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final host = _host;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    Navigator.of(context).pop();
    if (!host.mounted) return;
    deleteNow(
      host,
      deletes,
      record: (scope: DataScope.habits, id: habit.id),
      message: l.habitsDeleted(habit.name),
      send: () => repo.deleteHabit(habit.id),
      failedMessage: l.habitsDeleteFailed,
    );
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
    // not be loaded, which the history header then says.
    final loaded = async.value?.data;
    final habit = _withWanted(loaded ?? widget.initial);
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SyncHint.over(
        active: async.isRefetching,
        child: _content(
          context,
          habit,
          detailed: loaded != null,
          loading: async.isLoading,
          failed: async.hasFailed,
          gone: async.isGone,
        ),
      ),
    );
  }

  void _retry() =>
      ref.read(dataSyncProvider).refresh([habitDetailProvider(_id)]);

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
    final color = hexColor(habit.color);
    final rate = habit.completionRate30d <= 1
        ? (habit.completionRate30d * 100).round()
        : habit.completionRate30d.round();
    final chain30 = habit.chain.length > 30
        ? habit.chain.sublist(habit.chain.length - 30)
        : habit.chain;
    final goals = habit.trackedByGoals ?? const <TrackingGoal>[];
    final servedGoal = _servedGoalName(habit.goalId);

    // The calendar goes back as far as the chain read, never before the
    // habit started.
    final firstDay = [
      if (habit.chain.isNotEmpty) dateOnly(habit.chain.first.date),
      if (habit.startDate != null) dateOnly(habit.startDate!),
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final lastMonth = monthOf(habit.today.date);
    final firstMonth = firstDay == null ? lastMonth : monthOf(firstDay);

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(habit.name, style: text.headlineMedium)),
            ],
          ),
          if (habit.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              habit.description,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
          ],
          if (servedGoal != null || goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (servedGoal != null)
                  _chip(
                    context,
                    Icons.flag_outlined,
                    l.habitsServesGoal(servedGoal),
                  ),
                if (goals.isNotEmpty)
                  _chip(
                    context,
                    Icons.track_changes,
                    l.habitsTrackedBy(goals.map((g) => g.name).join(', ')),
                  ),
              ],
            ),
          ],
          if (habit.archived) ...[
            const SizedBox(height: 12),
            _note(context, Icons.archive_outlined, l.habitsArchivedNote),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              _stat(context, l.habitsStatStreak, '🔥 ${habit.currentStreak}'),
              _stat(context, l.habitsStatRecord, '${habit.longestStreak}'),
              _stat(context, l.habitsStatRate30d, l.percent(rate)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text(l.habitsCalendar, style: text.titleSmall)),
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
                Icon(Icons.cloud_off, size: 14, color: c.inkMid),
                const SizedBox(width: 8),
                TextButton(onPressed: _retry, child: Text(l.actionRetry)),
              ],
            ],
          ),
          if (!habit.archived)
            Text(
              l.habitsCalendarHint,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            HabitDayEditor(
              habit: habit,
              day: day,
              error: _dayError,
              onSet: (count) => _setDay(habit, day, count),
            ),
          ],
          const SizedBox(height: 24),
          Text(l.habitsLast30Days, style: text.titleSmall),
          const SizedBox(height: 12),
          ChainRow(chain: chain30, color: color),
          const SizedBox(height: 12),
          _legend(context, color),
          const SizedBox(height: 24),
          Text(l.habitsLast84Days, style: text.titleSmall),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MiniHeatmap(chain: habit.chain, color: color),
          ),
          const SizedBox(height: 32),
          if (!gone) ..._actions(context, habit, detailed: detailed),
        ],
      ),
    );
  }

  /// "Düzenle" first and full width (or, for an archived habit, "Arşivden
  /// çıkar"); archiving beside it; for an archived habit, delete quieter,
  /// below.
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
    final edit = FilledButton.icon(
      onPressed: _busy ? null : () => _edit(habit),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(l.actionEdit),
    );
    return [
      if (habit.archived) ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => _unarchive(habit),
          icon: _busy
              ? spinner
              : const Icon(Icons.unarchive_outlined, size: 18),
          label: Text(l.habitsUnarchive),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _edit(habit),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(l.actionEdit),
        ),
      ] else ...[
        edit,
        const SizedBox(height: 8),
        OutlinedButton.icon(
          // What it freezes is known once the detail is in.
          onPressed: _busy || !detailed ? null : () => _archive(habit),
          icon: _busy ? spinner : const Icon(Icons.archive_outlined, size: 18),
          label: Text(l.habitsArchive),
        ),
        const SizedBox(height: 6),
        // What archiving does, before it is done.
        Text(
          l.habitsArchiveBody(habit.name),
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: c.inkMid),
        ),
      ],
      // Deleted only from the archive (design-research §4.4): archiving is
      // the safer way out of the list, and comes first.
      if (habit.archived) ...[
        const SizedBox(height: 24),
        Center(
          child: TextButton.icon(
            // What a delete loses is known once the detail is in.
            onPressed: _busy || !detailed ? null : () => _delete(habit),
            style: TextButton.styleFrom(
              foregroundColor: c.error,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l.habitsDelete),
          ),
        ),
      ],
    ];
  }

  String? _servedGoalName(int? goalId) {
    if (goalId == null) return null;
    final goals = ref.watch(goalsProvider).value?.data;
    if (goals == null) return null;
    for (final g in [...goals.active, ...goals.achieved, ...goals.abandoned]) {
      if (g.id == goalId) return g.name;
    }
    return null;
  }

  Widget _chip(BuildContext context, IconData icon, String label) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.inkMid),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: text.labelMedium!.copyWith(color: c.inkMid),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, IconData icon, String message) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.inkMid),
          const SizedBox(width: 8),
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

  Widget _stat(BuildContext context, String label, String value) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.titleLarge!.copyWith(fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 2),
          Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    Widget item(Color fill, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(color, l.habitsLegendDone),
        item(color.withValues(alpha: 0.4), l.habitsLegendPartial),
        item(c.surface2, l.habitsLegendMissed),
      ],
    );
  }
}

/// Brings [habit] back from the archive; says so on [host] unless [quiet]
/// (an undo needs no confirmation), and says why when it fails. Takes the
/// repository rather than a ref: an undo runs after the sheet has closed.
Future<bool> _restoreHabit(
  MeridianRepository repo,
  BuildContext host,
  Habit habit, {
  bool quiet = false,
}) async {
  final l = host.l10n;
  try {
    await repo.unarchiveHabit(habit.id);
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
    _restoreHabit(ref.read(repositoryProvider), host, habit);

/// Formats an archive date for the archived list.
String archivedOnLabel(AppL10n l, Habit habit) {
  final at = habit.archivedAt;
  if (at == null) return l.habitsArchived;
  return l.habitsArchivedOn(
    formatDate(at, withYear: at.year != appToday().year),
  );
}
