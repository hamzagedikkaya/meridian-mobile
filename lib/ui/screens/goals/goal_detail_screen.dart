import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/sync_hint.dart';
import 'goal_form.dart';
import 'goal_ui.dart';

class GoalDetailScreen extends ConsumerStatefulWidget {
  final int goalId;

  const GoalDetailScreen({super.key, required this.goalId});

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

/// One goal and everything that can be done with it (design-research §5.5):
/// log progress (goals logged by hand), link or relink the account or habit
/// that drives it, edit, mark achieved, abandon (with undo), reopen —
/// following the server's status rules — and delete (with undo).
///
/// Goal writes are reported by the repository; this goal, the Goals grid and
/// Today's goal bars refresh from that — also when the screen is left before
/// the server answers. A goal deleted elsewhere says so and goes back.
class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  bool _busy = false;
  bool _recalcLoading = false;

  /// The goal was found deleted (a 404) while this screen was open.
  bool _goneSeen = false;

  /// ...and the screen is on its way back.
  bool _goneHandled = false;

  /// A context that outlives this screen, for a snackbar after it pops.
  BuildContext get _host => Navigator.of(context, rootNavigator: true).context;

  /// Runs a write on the goal; celebrates when it takes the goal to its
  /// target, says [done] when given, and says why when it fails.
  Future<Goal?> _mutate(
    Future<Goal> Function() action, {
    double? before,
    String? done,
    bool Function(Object error)? handled,
  }) async {
    if (_busy) return null;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      final updated = await action();
      final crossed = (before ?? 100) < 100 && updated.progressPercent >= 100;
      if (crossed) {
        Haptics.celebrate();
      } else {
        Haptics.tick();
      }
      if (done != null && mounted) showAppSnack(context, done);
      return updated;
    } catch (e) {
      if (mounted && !(handled?.call(e) ?? false)) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.goalsActionFailed),
          isError: true,
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recalculate(Goal goal) async {
    if (_recalcLoading) return;
    setState(() => _recalcLoading = true);
    try {
      final results = await Future.wait([
        ref.read(repositoryProvider).goalRecalculate(widget.goalId),
        Future.delayed(const Duration(milliseconds: 300)),
      ]);
      final after = results.first as Goal;
      if (goal.progressPercent < 100 && after.progressPercent >= 100) {
        Haptics.celebrate();
      }
    } catch (e) {
      // The last good value stays on screen; say the refresh did not happen.
      if (mounted) {
        final l = context.l10n;
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.goalsActionFailed),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _recalcLoading = false);
    }
  }

  // --- Status ----------------------------------------------------------------

  /// Abandons at once, with "Geri al" (which reopens it).
  Future<void> _abandon(Goal goal) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final host = _host;
    final abandoned = await _mutate(() => repo.abandonGoal(goal.id));
    if (abandoned == null || !host.mounted) return;
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
  }

  /// Makes an achieved or abandoned goal active again. One whose progress
  /// already reaches its target needs a higher one first (`target_reached`
  /// otherwise), which a sheet asks for — also when the server says so
  /// about progress made elsewhere since, with the progress it reports
  /// ([reachedAt]).
  Future<void> _reopen(Goal goal, {double? reachedAt}) async {
    final l = context.l10n;
    num? target;
    if (reachedAt != null || goal.reachedTarget) {
      target = await _askHigherTarget(goal, reachedAt ?? goal.currentValue);
      if (target == null || !mounted) return;
    }
    double? refusedAt;
    await _mutate(
      () => ref
          .read(repositoryProvider)
          .reopenGoal(goal.id, targetValue: target),
      done: l.goalsReopened,
      handled: (e) {
        if (target != null ||
            e is! ApiException ||
            e.code != 'target_reached') {
          return false;
        }
        refusedAt = e.number('current_value')?.toDouble() ?? goal.targetValue;
        return true;
      },
    );
    final at = refusedAt;
    if (at != null && mounted) await _reopen(goal, reachedAt: at);
  }

  Future<num?> _askHigherTarget(Goal goal, double current) {
    final label = goalIsFinancial(goal)
        ? formatGoalMoney(goal, current)
        : formatGoalNumber(current);
    return showModalBottomSheet<num>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (_) => _HigherTargetSheet(
        current: current,
        currentLabel: label,
      ),
    );
  }

  /// Only a goal logged by hand: its progress is set to its target.
  Future<void> _markAchieved(Goal goal) => _mutate(
        () => ref.read(repositoryProvider).markGoalAchieved(goal),
        before: goal.progressPercent,
        done: context.l10n.goalsMarkedAchieved,
      );

  /// Leaves the screen and takes the goal off every list, with "Geri al";
  /// the delete is sent when the snackbar goes.
  void _delete(Goal goal) {
    final l = context.l10n;
    final host = _host;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    Navigator.of(context).pop();
    deleteWithUndo(
      host,
      deletes,
      record: (scope: DataScope.goals, id: goal.id),
      message: l.goalsDeleted(goal.name),
      send: () => repo.deleteGoal(goal.id),
      failedMessage: l.goalsDeleteFailed,
    );
  }

  Future<void> _edit(Goal goal) async {
    await openGoalForm(context, goal: goal);
  }

  /// Links (or relinks, or unlinks) the account or habit that drives the
  /// goal's progress.
  Future<void> _link(Goal goal) async {
    final l = context.l10n;
    final picked = await pickGoalLink(
      context,
      ref,
      targetType: goal.targetType,
      current: goal.relatedRef,
    );
    if (picked == null || !mounted || picked.related == goal.relatedRef) {
      return;
    }
    await _mutate(
      () => ref.read(repositoryProvider).linkGoal(goal.id, picked.related),
      before: goal.progressPercent,
      done: picked.name == null ? l.goalsUnlinked : l.goalsLinked(picked.name!),
    );
  }

  void _menu(Goal goal, String action) => switch (action) {
        'achieved' => _markAchieved(goal),
        'abandon' => _abandon(goal),
        'reopen' => _reopen(goal),
        'delete' => _delete(goal),
        _ => null,
      };

  /// Goes back from a goal found deleted: this screen's own route only,
  /// when it is the one on top (the build runs again when it becomes so).
  void _leave(AppL10n l) {
    _goneHandled = true;
    final host = _host;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _goneHandled = false;
        return;
      }
      Navigator.of(context).maybePop();
      if (host.mounted) showAppSnack(host, l.goalsGone);
    });
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(goalDetailProvider(widget.goalId));
    // Deleted on the web or another device: say so and go back to a list
    // that no longer shows it — once this screen is on top, so a form or
    // sheet opened over it is never the one closed.
    ref.listen(goalDetailProvider(widget.goalId), (_, next) {
      if (next.isGone) _goneSeen = true;
    });
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_goneSeen && !_goneHandled && isCurrent) _leave(l);
    final goal = async.isGone ? null : async.value?.data;

    void retry() =>
        ref.read(dataSyncProvider).refresh([goalDetailProvider(widget.goalId)]);

    final Widget body;
    if (async.isGone) {
      // A retry could only answer 404 again, so this says what happened
      // instead of blaming the connection.
      body = EmptyState(
        icon: Icons.delete_outline,
        title: l.goalsGone,
        subtitle: l.errRecordGoneBody,
        actionLabel: l.actionBack,
        onAction: () => Navigator.of(context).maybePop(),
      );
    } else if (goal != null) {
      body = Column(
        children: [
          // A refresh failed: the goal shown may be out of date.
          if (async.refreshFailed)
            OfflineBanner(
              lastUpdated: async.value!.at,
              onRetry: retry,
            ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: context.nok.gold,
              onRefresh: () async {
                retry();
                await settleRefresh(
                    [ref.read(goalDetailProvider(widget.goalId).future)]);
              },
              child: _content(goal),
            ),
          ),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: l.goalsLoadFailed,
        actionLabel: l.actionRetry,
        onAction: retry,
      );
    } else {
      body = Center(
        child: CircularProgressIndicator(color: context.nok.gold),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.titleGoal, style: text.headlineMedium),
        actions: [
          if (goal != null) ...[
            IconButton(
              tooltip: l.actionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => _edit(goal),
            ),
            PopupMenuButton<String>(
              tooltip: l.goalsMore,
              enabled: !_busy,
              onSelected: (action) => _menu(goal, action),
              itemBuilder: (_) => [
                if (goal.isActive && goal.isManual)
                  _menuItem('achieved', Icons.check_circle_outline,
                      l.goalsMarkAchieved),
                if (goal.isActive)
                  _menuItem('abandon', Icons.flag_outlined, l.goalsAbandonAction),
                if (!goal.isActive)
                  _menuItem('reopen', Icons.replay, l.goalsReopen),
                _menuItem('delete', Icons.delete_outline, l.goalsDelete,
                    destructive: true),
              ],
            ),
          ],
        ],
      ),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final c = context.nok;
    final color = destructive ? c.error : null;
    return PopupMenuItem(
      value: value,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
      ),
    );
  }

  String _daysLeft(Goal goal) {
    final l = context.l10n;
    final days = goal.daysRemaining;
    if (days == null) return '—';
    if (days < 0) return l.goalsDaysOverdue(-days);
    return '$days';
  }

  Widget _content(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final color = goalColor(goal.color);
    final pct = goal.progressPercent.clamp(0, 100).round();
    final deadline = goal.deadline;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Center(
          child: Hero(
            tag: 'goal-ring-${goal.id}',
            flightShuttleBuilder: goalRingFlightShuttle,
            child: ProgressRing(
              value: pct / 100,
              color: color,
              size: 160,
              strokeWidth: 10,
              center: Text(
                l.percent(pct),
                style: text.displayMedium!.copyWith(fontFeatures: tabularFigures),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(goal.name, style: text.titleLarge, textAlign: TextAlign.center),
        if (goal.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            goal.description,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            _StatTile(
              label: l.goalsDetailStatus,
              value: goalStatusLabel(l, goal.status),
            ),
            const SizedBox(width: 12),
            _StatTile(
              label: l.goalsDetailDeadline,
              value: deadline == null
                  ? '—'
                  : formatDate(deadline,
                      withYear: deadline.year != appToday().year),
            ),
            const SizedBox(width: 12),
            _StatTile(label: l.goalsDetailDaysLeft, value: _daysLeft(goal)),
          ],
        ),
        if (!goal.isActive) ...[
          const SizedBox(height: 16),
          _statusCard(goal),
        ],
        const SizedBox(height: 24),
        _actionCard(goal),
      ],
    );
  }

  /// An achieved or abandoned goal: what it is, and the way back.
  Widget _statusCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      child: Row(
        children: [
          Icon(
            goal.isAchieved ? Icons.check_circle : Icons.flag_outlined,
            color: goal.isAchieved ? c.income : c.inkMid,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(goalStatusLabel(l, goal.status),
                style: text.titleMedium),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _reopen(goal),
            child: Text(l.goalsReopen),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(Goal goal) => switch (goal.targetType) {
        'habit' => _habitCard(goal),
        'financial' => _financialCard(goal),
        _ => _manualCard(goal),
      };

  /// The step buttons and "enter a value": only for a goal logged by hand.
  Widget _manualCard(Goal goal, {Widget? header}) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?header,
          Text(context.l10n.goalsDetailProgress, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            goalProgressLabel(goal),
            style: text.bodyMedium!
                .copyWith(color: c.inkMid, fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final d in const [-10, -1, 1, 10]) ...[
                Expanded(
                  child: _StepButton(
                    delta: d,
                    onTap: _busy ? null : () => _step(goal, d),
                  ),
                ),
                if (d != 10) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _DirectValueField(
            initial: goal.currentValue,
            onSubmit: (v) => _mutate(
              () => ref
                  .read(repositoryProvider)
                  .goalUpdateProgress(goal.id, currentValue: v),
              before: goal.progressPercent,
            ),
          ),
        ],
      ),
    );
  }

  void _step(Goal goal, int delta) => _mutate(
        () => ref
            .read(repositoryProvider)
            .goalUpdateProgress(goal.id, delta: delta),
        before: goal.progressPercent,
      );

  /// The link's own row: what drives the progress, and a way to change it.
  Widget _linkRow(Goal goal, {required String note}) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final linked = goal.related != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!linked) ...[
          Text(note, style: text.bodySmall!.copyWith(color: c.inkMid)),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _link(goal),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(linked ? Icons.swap_horiz : Icons.link, size: 18),
            label: Text(
              linked
                  ? l.goalsChangeLink
                  : goal.targetType == 'financial'
                      ? l.goalsLinkAccount
                      : l.goalsLinkHabit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _habitCard(Goal goal) {
    final l = context.l10n;
    final link = _linkRow(goal, note: l.goalsNoHabitLinked);
    // Without a habit, progress is logged by hand.
    if (goal.related == null) {
      return _manualCard(
        goal,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: link,
        ),
      );
    }
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final streak = goal.related?.currentStreak;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(goal.related!.name, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(l.goalsHabitProgress,
              style: text.bodySmall!.copyWith(color: c.inkMid)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 20, color: c.goldBright),
              const SizedBox(width: 6),
              Text(
                streak == null ? '—' : l.goalsStreakDays(streak),
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.goalsProgressDays(
              formatGoalNumber(goal.currentValue),
              formatGoalNumber(goal.targetValue),
            ),
            style: text.headlineMedium!.copyWith(fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 8),
          link,
        ],
      ),
    );
  }

  Widget _financialCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final related = goal.related;
    final meta = goalMoneyMeta(goal);

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Without an account, the progress is the user's income of all
          // time — never labelled as an account balance.
          Text(related?.name ?? l.goalsTotalIncome, style: text.titleMedium),
          if (related != null) ...[
            const SizedBox(height: 4),
            Text(l.goalsCurrentBalance,
                style: text.bodySmall!.copyWith(color: c.inkMid)),
          ],
          const SizedBox(height: 8),
          if (related?.balanceCents != null)
            MoneyText(
              related!.balanceCents!,
              currency: related.currency ?? meta.currency,
              subunitToUnit: related.subunitToUnit ?? meta.subunit,
              variant: MoneyVariant.title,
            )
          else
            Text(
              formatGoalMoney(goal, goal.currentValue),
              style: text.titleLarge!.copyWith(fontFeatures: tabularFigures),
            ),
          const SizedBox(height: 4),
          Text(
            goalProgressLabel(goal),
            style: text.bodySmall!
                .copyWith(color: c.inkMid, fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 8),
          _linkRow(goal, note: l.goalsNoAccountLinked),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: l.goalsRefresh,
              loading: _recalcLoading,
              onPressed: () => _recalculate(goal),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a target above [current], to reopen a goal that reached its
/// own; pops with it.
class _HigherTargetSheet extends StatefulWidget {
  final double current;
  final String currentLabel;

  const _HigherTargetSheet({required this.current, required this.currentLabel});

  @override
  State<_HigherTargetSheet> createState() => _HigherTargetSheetState();
}

class _HigherTargetSheetState extends State<_HigherTargetSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l = context.l10n;
    final value = parseGoalNumber(_controller.text);
    if (value == null || value <= widget.current) {
      Haptics.danger();
      setState(() => _error = goalNumberError(l, _controller.text,
          invalid: l.goalsReopenTargetTooLow(widget.currentLabel)));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        // Scrolls on a small screen, with large text or the keyboard up,
        // so the button is always reachable.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.goalsReopenTitle, style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                l.goalsReopenNeedsHigherTarget(widget.currentLabel),
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: l.goalsReopenNewTarget,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(l.goalsReopen),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: text.titleMedium!.copyWith(fontFeatures: tabularFigures),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final int delta;
  final VoidCallback? onTap;

  const _StepButton({required this.delta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              delta > 0 ? '+$delta' : '$delta',
              style: text.titleSmall!.copyWith(
                fontFeatures: tabularFigures,
                color: onTap == null ? c.inkFaint : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectValueField extends StatefulWidget {
  final double initial;
  final ValueChanged<num> onSubmit;

  const _DirectValueField({required this.initial, required this.onSubmit});

  @override
  State<_DirectValueField> createState() => _DirectValueFieldState();
}

class _DirectValueFieldState extends State<_DirectValueField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: goalNumberInput(widget.initial));
  }

  /// Follows the goal when its value changes underneath — a ± step, a
  /// refresh — so Save never writes back a stale number. Left alone while the
  /// user is typing in it.
  @override
  void didUpdateWidget(_DirectValueField old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial && !_focus.hasFocus) {
      _controller.text = goalNumberInput(widget.initial);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseGoalNumber(_controller.text);
    if (v == null || v < 0) {
      final l = context.l10n;
      setState(() => _error = goalNumberError(l, _controller.text,
          invalid: l.errInvalidData));
      return;
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    widget.onSubmit(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.goalsEnterValue,
              errorText: _error,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
