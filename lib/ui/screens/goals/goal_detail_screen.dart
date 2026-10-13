import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/repository.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../flows/flows.dart' as flows;
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/rolling_number.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/streak_flame.dart';
import '../../widgets/sync_hint.dart';
import 'goal_actions.dart';
import 'goal_form.dart';
import 'goal_ui.dart';
import 'goal_value_sheet.dart';

/// How long the stepper waits after the last tap before it sends the value
/// (design-analysis §7.11): ten quick "+1"s are one PATCH.
const goalStepSendDelay = Motion.stepSendDelay;

class GoalDetailScreen extends ConsumerStatefulWidget {
  final int goalId;

  /// The goal as the list that opened it shows it (`extra`): drawn until
  /// the detail lands, so the ring's hero has somewhere to land at once.
  final Goal? preview;

  const GoalDetailScreen({super.key, required this.goalId, this.preview});

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

/// One goal and everything that can be done with it (design-analysis
/// §7.11): its 160 dp ring — the Hero from the grid, there in the first
/// frame from the list's preview, never a spinner — the status, deadline
/// and days left, and an action card by where its progress comes from:
///
/// * **manual** — −10 −1 +1 +10, optimistic and merged (below); "Değer gir"
///   on the keypad; "Tamamlandı olarak işaretle";
/// * **habit** — the habit with its streak, "Bugünü işaretle", a way to it;
/// * **account** — the account with its balance, "Hesaba git", "Yenile";
/// * **income** — "every income counts", and "Hesap bağla".
///
/// The pencil edits; the menu abandons (with undo) or reopens — with a
/// higher target on the keypad when it reached its own — and deletes (with
/// undo).
///
/// **The stepper.** Each tap shows at once (the ring springs, the numbers
/// roll, a tick) and adds to the value; [goalStepSendDelay] after the last
/// tap one `update_progress` goes with the absolute value. Taps during the
/// request add up and go after it. A failure springs back to the last value
/// the server confirmed, with the REJECT haptic and "Tekrar dene". Crossing
/// 100 % by these taps is celebrated once (tier 3).
///
/// Goal writes are reported by the repository; this goal, the Goals grid and
/// Today's goal bars refresh from that — also when the screen is left before
/// the server answers. A goal deleted elsewhere says so and goes back.
class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  /// A status or link write on its way: the menu and those buttons wait.
  bool _busy = false;

  /// Only [GoalDetailScreen.preview] is drawn: the detail is on its way.
  bool _previewOnly = false;
  bool _recalcLoading = false;

  /// "Yenile"'s spinner: on once a recalculation has taken longer than
  /// [Motion.spinnerDelay] (started by [_recalcSpinnerTimer]).
  bool _recalcSpinner = false;
  Timer? _recalcSpinnerTimer;
  bool _markingToday = false;

  /// The goal was found deleted (a 404) while this screen was open.
  bool _goneSeen = false;

  /// ...and the screen is on its way back.
  bool _goneHandled = false;

  // --- Stepper state ---------------------------------------------------------

  /// The value the user has stepped to, shown instead of the goal's own
  /// until the server's answer is on screen; null when nothing is pending.
  double? _desired;

  /// Fires [goalStepSendDelay] after the last tap.
  Timer? _sendTimer;

  /// The value of the request in flight, if any.
  double? _sending;

  /// The last request was answered; the next goal read clears [_desired].
  bool _answered = false;

  /// 100 % was celebrated on this visit: stepping down and up again does
  /// not repeat it (the celebration layer keeps it once per goal ever).
  bool _celebrated = false;

  /// The milestone celebrated at a tap whose value the server does not
  /// have yet: [goal] to measure what is saved against, and how to give the
  /// milestone back if no value past 100 % gets there ([_settleMilestone]).
  ({Goal goal, VoidCallback giveBack})? _heldMilestone;

  /// Captured for a send from [dispose], when `ref` can no longer be read.
  late MeridianRepository _repo;
  late AppL10n _l;
  BuildContext? _hostContext;

  /// A context that outlives this screen, for a snackbar after it pops.
  BuildContext get _host => Navigator.of(context, rootNavigator: true).context;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = ref.read(repositoryProvider);
    _l = context.l10n;
    _hostContext = _host;
  }

  @override
  void dispose() {
    // Taps not sent yet go now: leaving never loses a step. With a request
    // in flight, they go once it is answered (see [_send]).
    final value = _desired;
    final timer = _sendTimer;
    timer?.cancel();
    _sendTimer = null;
    if (value != null && timer != null && _sending == null) {
      _sendAfterLeaving(value);
    }
    _recalcSpinnerTimer?.cancel();
    super.dispose();
  }

  /// Sends [value] for a screen that is gone; a failure is said on the
  /// app's messenger.
  void _sendAfterLeaving(double value) {
    final host = _hostContext;
    final l = _l;
    unawaited(
      _repo
          .goalUpdateProgress(widget.goalId, currentValue: value)
          .then<void>(
            (_) => _settleMilestone(value),
            onError: (Object e) {
              _settleMilestone(null);
              if (host != null && host.mounted) {
                showAppSnack(
                  host,
                  failureMessage(e, l, fallback: l.goalsProgressNotSaved),
                  isError: true,
                );
              }
            },
          ),
    );
  }

  /// Runs a status or link write on the goal; says [done] when given, and
  /// says why when it fails.
  Future<Goal?> _mutate(
    Future<Goal> Function() action, {
    String? done,
    bool Function(Object error)? handled,
  }) async {
    if (_busy) return null;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      final updated = await action();
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

  // --- Progress (manual) -----------------------------------------------------

  /// The value on screen: the stepped one while it is pending.
  double _shownValue(Goal goal) => _desired ?? goal.currentValue;

  /// Whether a number on screen changed because of the user's own step.
  NumberCause get _cause => _desired != null || DataSync.userWroteRecently
      ? NumberCause.user
      : NumberCause.background;

  /// Moves the shown value to [next] (never below zero) at once, and sends
  /// it [delay] later — or now, with a zero [delay].
  void _setValue(Goal goal, double next, {Duration delay = goalStepSendDelay}) {
    final from = _shownValue(goal);
    final value = (math.max(0.0, next) * 100).round() / 100;
    if (value == from && delay != Duration.zero) return;
    // At the tap that crosses it (§5.8: confirm only); given back if the
    // step never reaches the server.
    if (goalPercentOf(goal, from) < 100 && goalPercentOf(goal, value) >= 100) {
      _celebrate(goal);
    }
    setState(() {
      _desired = value;
      _answered = false;
    });
    _sendTimer?.cancel();
    if (delay == Duration.zero) {
      _sendTimer = null;
      _send();
    } else {
      _sendTimer = Timer(delay, () {
        _sendTimer = null;
        _send();
      });
    }
  }

  /// Tier 3 for the user's own write past 100 %, at its tap, once per
  /// visit (the layer keeps it once per goal ever). Held until the server
  /// has a value past 100 %.
  void _celebrate(Goal goal) {
    if (_celebrated || !mounted) return;
    _celebrated = true;
    final giveBack = celebrateGoalReached(context, goal);
    if (giveBack != null) _heldMilestone = (goal: goal, giveBack: giveBack);
  }

  /// A write was answered: [saved] is what the server now has (null: it
  /// refused, and the taps behind it are dropped), [stillToGo] a value
  /// stepped since and not sent yet. The milestone held from the tap stays
  /// once a value past 100 % is saved; it is given back when none is saved
  /// and none is still to go — a step taken back before it went, or a
  /// refused write, uses nothing up (§4.30: a local write that crossed).
  void _settleMilestone(double? saved, {double? stillToGo}) {
    final held = _heldMilestone;
    if (held == null) return;
    bool reached(double? v) => v != null && goalPercentOf(held.goal, v) >= 100;
    if (reached(saved)) {
      _heldMilestone = null;
    } else if (!reached(stillToGo)) {
      _heldMilestone = null;
      _celebrated = false;
      held.giveBack();
    }
  }

  void _step(Goal goal, int delta) {
    Haptics.tick();
    _setValue(goal, _shownValue(goal) + delta);
  }

  /// Sends the stepped value, unless a request is in flight: then it goes
  /// once that one is answered.
  Future<void> _send() async {
    final value = _desired;
    if (value == null || _sending != null) return;
    _sending = value;
    try {
      await _repo.goalUpdateProgress(widget.goalId, currentValue: value);
      _sending = null;
      if (!mounted) {
        // Left meanwhile, with taps after this one: they still go.
        final latest = _desired;
        final more = latest != null && latest != value;
        _settleMilestone(value, stillToGo: more ? latest : null);
        if (more) _sendAfterLeaving(latest);
        return;
      }
      _settleMilestone(value, stillToGo: _desired);
      if (_desired != value) {
        // Taps landed meanwhile: they go now, or when their wait is over.
        if (_sendTimer == null) unawaited(_send());
        return;
      }
      // The goal read that follows the write replaces the stepped value.
      setState(() => _answered = true);
    } catch (e) {
      _sending = null;
      _settleMilestone(null);
      if (!mounted) {
        // Left meanwhile: the taps queued behind this request are dropped
        // with it (they built on a value the server refused), and that is
        // said on the app's messenger, as [_sendAfterLeaving] does.
        final host = _hostContext;
        if (host != null && host.mounted) {
          showAppSnack(
            host,
            failureMessage(e, _l, fallback: _l.goalsProgressNotSaved),
            isError: true,
          );
        }
        return;
      }
      _sendTimer?.cancel();
      _sendTimer = null;
      final l = context.l10n;
      // What "Tekrar dene" sends: the value the user chose last — a value
      // typed after this request went out included — not the one refused.
      final latest = _desired ?? value;
      // Back to the last value the server confirmed.
      setState(() {
        _desired = null;
        _answered = false;
      });
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.goalsProgressNotSaved),
        isError: true,
        actionLabel: l.actionRetry,
        onAction: () {
          final goal = _loadedGoal;
          if (goal != null && mounted) {
            _setValue(goal, latest, delay: Duration.zero);
          }
        },
      );
    }
  }

  Goal? get _loadedGoal {
    final async = ref.read(goalDetailProvider(widget.goalId));
    return async.isGone ? null : async.value?.data;
  }

  Future<void> _enterValue(Goal goal) async {
    final l = context.l10n;
    final value = await showGoalValueSheet(
      context,
      title: l.goalsEnterValue,
      kind: goalValueKind(goal),
      initial: _shownValue(goal),
    );
    if (value == null || !mounted) return;
    _setValue(goal, value, delay: Duration.zero);
  }

  /// Only a goal logged by hand: its progress is set to its target — shown
  /// at once, taken back if the server refuses.
  Future<void> _markAchieved(Goal goal) async {
    if (_busy) return;
    final l = context.l10n;
    if (goalPercentOf(goal, _shownValue(goal)) < 100) _celebrate(goal);
    _sendTimer?.cancel();
    _sendTimer = null;
    // A step answered before this still waits for its read: that read
    // must not put the old value back while this write is out (the
    // listener also waits while [_busy]).
    setState(() {
      _desired = goal.targetValue;
      _answered = false;
    });
    final updated = await _mutate(
      () => _repo.markGoalAchieved(goal),
      done: l.goalsMarkedAchieved,
    );
    _settleMilestone(updated == null ? null : goal.targetValue);
    if (!mounted) return;
    setState(() {
      if (updated == null) {
        _desired = null;
      } else {
        _answered = true;
      }
    });
  }

  Future<void> _recalculate(Goal goal) async {
    if (_recalcLoading) return;
    setState(() => _recalcLoading = true);
    _recalcSpinnerTimer = Timer(Motion.spinnerDelay, () {
      if (mounted) setState(() => _recalcSpinner = true);
    });
    try {
      // At least 300 ms, as before the redesign: a fast answer does not
      // flash the button disabled and back.
      await Future.wait([
        _repo.goalRecalculate(widget.goalId),
        Future<void>.delayed(Motion.busyMinimum),
      ]);
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
      _recalcSpinnerTimer?.cancel();
      _recalcSpinnerTimer = null;
      if (mounted) {
        setState(() {
          _recalcLoading = false;
          _recalcSpinner = false;
        });
      }
    }
  }

  // --- Status ----------------------------------------------------------------

  /// Abandons at once, with "Geri al" (which reopens it).
  Future<void> _abandon(Goal goal) async {
    if (_busy) return;
    setState(() => _busy = true);
    await abandonGoalWithUndo(context, ref, goal);
    if (mounted) setState(() => _busy = false);
  }

  /// Makes an achieved or abandoned goal active again. One whose progress
  /// already reaches its target needs a higher one first (`target_reached`
  /// otherwise), which the keypad asks for — also when the server says so
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
      () => _repo.reopenGoal(goal.id, targetValue: target),
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

  Future<double?> _askHigherTarget(Goal goal, double current) {
    final l = context.l10n;
    final label = goalIsFinancial(goal)
        ? formatGoalMoney(goal, current)
        : formatGoalNumber(current);
    return showGoalValueSheet(
      context,
      title: l.goalsReopenTitle,
      message: l.goalsReopenNeedsHigherTarget(label),
      kind: goalValueKind(goal),
      actionLabel: l.goalsReopen,
      check: (value) =>
          value > current ? null : l.goalsReopenTargetTooLow(label),
    );
  }

  /// Leaves the screen and takes the goal off every list, with "Geri al";
  /// the delete is sent when the snackbar goes.
  void _delete(Goal goal) {
    final l = context.l10n;
    final host = _host;
    final deletes = ref.read(deferredDeletesProvider.notifier);
    // A step not sent yet has nothing left to change.
    _sendTimer?.cancel();
    _sendTimer = null;
    _desired = null;
    Navigator.of(context).pop();
    deleteWithUndo(
      host,
      deletes,
      record: (scope: DataScope.goals, id: goal.id),
      message: l.goalsDeleted(goal.name),
      send: () => _repo.deleteGoal(goal.id),
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
      () => _repo.linkGoal(goal.id, picked.related),
      done: picked.name == null ? l.goalsUnlinked : l.goalsLinked(picked.name!),
    );
  }

  /// "Bugünü işaretle": the linked habit's today, done — at once on every
  /// screen that shows it; the goal follows from the server.
  Future<void> _markToday(Habit habit) async {
    if (_markingToday) return;
    final l = context.l10n;
    Haptics.check();
    setState(() => _markingToday = true);
    try {
      await ref
          .read(habitActionsProvider)
          .setToday(habit.id, habit.targetCount < 1 ? 1 : habit.targetCount);
      ref.read(dataSyncProvider).refresh([goalDetailProvider(widget.goalId)]);
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.goalsActionFailed),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _markingToday = false);
    }
  }

  void _menu(Goal goal, String action) => switch (action) {
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
    final l = context.l10n;
    final async = ref.watch(goalDetailProvider(widget.goalId));
    // Deleted on the web or another device: say so and go back to a list
    // that no longer shows it — once this screen is on top, so a form or
    // sheet opened over it is never the one closed.
    ref.listen(goalDetailProvider(widget.goalId), (previous, next) {
      if (next.isGone) _goneSeen = true;
      // The read after an answered step: the server's value takes over.
      final fresh = next.value;
      if (_answered &&
          fresh != null &&
          !identical(fresh, previous?.value) &&
          _sending == null &&
          _sendTimer == null &&
          !_busy) {
        setState(() {
          _desired = null;
          _answered = false;
        });
      }
    });
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_goneSeen && !_goneHandled && isCurrent) _leave(l);
    final loaded = async.isGone ? null : async.value?.data;
    final preview = widget.preview?.id == widget.goalId ? widget.preview : null;
    // A failed read keeps the list's copy on screen, under the offline
    // banner (§5.6); only a goal that is gone loses it.
    final goal = loaded ?? (async.isGone ? null : preview);
    // Until the detail lands, the preview is only looked at: its actions
    // would build on the list's numbers.
    _previewOnly = loaded == null;

    void retry() =>
        ref.read(dataSyncProvider).refresh([goalDetailProvider(widget.goalId)]);

    final LoadPhase phase;
    if (goal != null) {
      phase = LoadPhase.content;
    } else if (async.isGone || async.hasFailed) {
      phase = LoadPhase.error;
    } else {
      phase = LoadPhase.waiting;
    }

    final body = LoadPhaseSwitcher(
      phase: phase,
      skeleton: (_) => const _DetailSkeleton(),
      error: (context) => async.isGone
          // A retry could only answer 404 again, so this says what
          // happened instead of blaming the connection.
          ? goalScrollableFill(
              EmptyState(
                icon: Icons.delete_outline_rounded,
                title: l.goalsGone,
                subtitle: l.errRecordGoneBody,
                actionLabel: l.actionBack,
                onAction: () => Navigator.of(context).maybePop(),
              ),
            )
          // Nothing to show at all: the app's error state (§7.15), with
          // the way to the server settings.
          : goalScrollableFill(
              EmptyState.error(
                onRetry: retry,
                onServerSettings: () => context.push('/profile/server'),
              ),
            ),
      content: (_) => Column(
        children: [
          // A refresh failed: the goal shown may be out of date. Or the
          // first read failed: the list's copy is what there is.
          if (async.refreshFailed && async.value != null)
            OfflineBanner(lastUpdated: async.value!.at, onRetry: retry)
          else if (async.hasFailed && loaded == null)
            OfflineBanner(
              lastUpdated:
                  ref.read(goalsProvider).value?.at ?? DateTime.now(),
              onRetry: retry,
            ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: context.nok.gold,
              onRefresh: () async {
                Haptics.armed();
                retry();
                await settleRefresh([
                  ref.read(goalDetailProvider(widget.goalId).future),
                ]);
              },
              child: _content(goal!),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        // The page's title is the goal itself (§6.4) — never "Hedef":
        // nothing until it is known.
        title: Text(
          goal?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (loaded != null) ...[
            IconButton(
              tooltip: l.actionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => _edit(loaded),
            ),
            PopupMenuButton<String>(
              tooltip: l.goalsMore,
              enabled: !_busy,
              onSelected: (action) => _menu(loaded, action),
              itemBuilder: (_) => [
                if (loaded.isActive)
                  _menuItem(
                    'abandon',
                    Icons.flag_outlined,
                    l.goalsAbandonAction,
                  ),
                if (!loaded.isActive)
                  _menuItem('reopen', Icons.replay_rounded, l.goalsReopen),
                _menuItem(
                  'delete',
                  Icons.delete_outline_rounded,
                  l.goalsDelete,
                  destructive: true,
                ),
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
    final days = goal.daysRemaining ?? 0;
    if (days < 0) return l.goalsDaysOverdue(-days);
    return '$days';
  }

  Widget _content(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = goalTone(goal, c);
    final shown = _shownValue(goal);
    final pct = _desired == null
        ? goal.progressPercent.clamp(0, 100).round()
        : goalPercentOf(goal, shown);
    final deadline = goal.deadline;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.xxl,
        Insets.gutter,
        Gap.x4,
      ),
      children: [
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
                size: 160,
                strokeWidth: 10,
                // The hero lands on the value; a new one springs to it.
                sweepOnMount: false,
                center: goalRingCenter(
                  160,
                  RollingNumber(
                    text: l.percent(pct),
                    cause: _cause,
                    fractionScale: 1,
                    style: text.displayMedium!.copyWith(
                      color: c.inkHi,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (goal.description.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          Text(
            goal.description,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: Gap.xxl),
        StatTileRow(
          tiles: [
            StatTile(
              label: l.goalsDetailStatus,
              value: goalStatusLabel(l, goal.status),
            ),
            if (deadline != null) ...[
              StatTile(
                label: l.goalsDetailDeadline,
                value: formatDate(
                  deadline,
                  withYear: deadline.year != appToday().year,
                ),
              ),
              StatTile(
                label: l.goalsDetailDaysLeft,
                value: _daysLeft(goal),
                valueColor: (goal.daysRemaining ?? 0) < 0 ? c.error : null,
              ),
            ],
          ],
        ),
        if (!goal.isActive) ...[
          const SizedBox(height: Gap.lg),
          _statusCard(goal),
        ],
        const SizedBox(height: Gap.xxl),
        // Until the goal is read, its actions would act on the list's
        // numbers: not tappable and not offered to a screen reader; their
        // buttons draw disabled.
        IgnorePointer(
          ignoring: _previewOnly,
          child: ExcludeSemantics(
            excluding: _previewOnly,
            child: _actionCard(goal),
          ),
        ),
      ],
    );
  }

  /// An achieved or abandoned goal: what it is, and the way back.
  Widget _statusCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final status = Row(
      children: [
        Icon(
          goal.isAchieved ? Icons.check_circle_rounded : Icons.flag_outlined,
          color: goal.isAchieved ? c.income : c.inkMid,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Text(goalStatusLabel(l, goal.status), style: text.titleMedium),
        ),
      ],
    );
    final reopen = OutlinedButton(
      onPressed: _busy || _previewOnly ? null : () => _reopen(goal),
      child: Text(l.goalsReopen),
    );
    // At large text the button goes under the status, full width.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return NokturnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            const SizedBox(height: Gap.md),
            reopen,
          ],
        ),
      );
    }
    return NokturnCard(
      child: Row(
        children: [
          Expanded(child: status),
          const SizedBox(width: Gap.md),
          reopen,
        ],
      ),
    );
  }

  Widget _actionCard(Goal goal) {
    final l = context.l10n;
    return switch (goal.progressSource) {
      'habit' when goal.related != null => _habitCard(goal),
      'account' when goal.related != null => _accountCard(goal),
      'income' => _incomeCard(goal),
      // Logged by hand — also a habit goal without a habit, which can link
      // one from here.
      _ => _manualCard(
        goal,
        header: goal.targetType == 'habit'
            ? _linkRow(goal, note: l.goalsNoHabitLinked)
            : null,
      ),
    };
  }

  /// The big "x / y" line, rolling when the user changed it.
  Widget _valueLine(String value) {
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: RollingNumber(
        text: value,
        cause: _cause,
        fractionScale: 1,
        semanticsLabel: value,
        style: text.headlineSmall!.copyWith(
          color: context.nok.inkHi,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }

  /// The steps, "Değer gir" and "Tamamlandı olarak işaretle": only for a
  /// goal logged by hand.
  Widget _manualCard(Goal goal, {Widget? header}) {
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final live = !_previewOnly;
    final shown = _shownValue(goal);
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, const SizedBox(height: Gap.lg)],
          Text(l.goalsDetailProgress, style: text.titleMedium),
          const SizedBox(height: Gap.xs),
          _valueLine(goalProgressLabel(goal, current: shown)),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              for (final d in const [-10, -1, 1, 10]) ...[
                if (d != -10) const SizedBox(width: Gap.sm),
                Expanded(
                  child: _StepButton(
                    delta: d,
                    // Nothing below zero to take away.
                    onTap: !live || (d < 0 && shown <= 0)
                        ? null
                        : () => _step(goal, d),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: live ? () => _enterValue(goal) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Hit.min),
            ),
            icon: const Icon(Icons.dialpad_rounded, size: 18),
            label: Text(l.goalsEnterValue),
          ),
          if (goal.isActive) ...[
            const SizedBox(height: Gap.xs),
            TextButton.icon(
              onPressed: live && !_busy ? () => _markAchieved(goal) : null,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(Hit.min),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(l.goalsMarkAchieved),
            ),
          ],
        ],
      ),
    );
  }

  /// The link's own row: what drives the progress, and a way to change it.
  Widget _linkRow(Goal goal, {String? note}) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final linked = goal.related != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!linked && note != null) ...[
          Text(note, style: text.bodySmall!.copyWith(color: c.inkMid)),
          const SizedBox(height: Gap.sm),
        ],
        TextButton.icon(
          onPressed: _busy || _previewOnly ? null : () => _link(goal),
          style: TextButton.styleFrom(minimumSize: Hit.minSize),
          icon: Icon(
            linked ? Icons.swap_horiz_rounded : Icons.link_rounded,
            size: 18,
          ),
          label: Text(
            linked
                ? l.goalsChangeLink
                : goal.targetType == 'financial'
                ? l.goalsLinkAccount
                : l.goalsLinkHabit,
          ),
        ),
      ],
    );
  }

  Widget _habitCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final related = goal.related!;
    final listed = ref.watch(
      habitsProvider.select(
        (a) =>
            a.value?.data.habits.where((h) => h.id == related.id).firstOrNull,
      ),
    );
    final listRead = ref.watch(habitsProvider.select((a) => a.hasValue));
    // Not among the active habits: an archived one (a goal keeps its link
    // to it, frozen) — read on its own, so the goal still leads to it.
    final alone = listed == null && listRead
        ? ref.watch(habitDetailProvider(related.id)).value?.data
        : null;
    final habit = listed ?? alone;
    final archived = listed == null && (alone?.archived ?? false);
    final streak = related.currentStreak ?? habit?.currentStreak ?? 0;
    final doneToday = !archived && (habit?.today.completed ?? false);
    final live = !_previewOnly;

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.repeat_rounded,
                size: 20,
                color: habit == null
                    ? c.inkMid
                    : entityTone(habit.color, c).fill,
              ),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(related.name, style: text.titleMedium)),
              if (streak > 0) ...[
                const SizedBox(width: Gap.sm),
                StreakFlame(days: streak, size: StreakFlameSize.detail),
              ],
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            l.goalsHabitProgress,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.md),
          _valueLine(
            l.goalsProgressDays(
              formatGoalNumber(goal.currentValue),
              formatGoalNumber(goal.targetValue),
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (archived)
            // The server would refuse the log (`habit_archived`): say why,
            // and the way to the habit below restores it.
            Text(
              l.goalsHabitArchived,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            )
          else if (doneToday)
            OutlinedButton.icon(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(Hit.min),
              ),
              icon: Icon(Icons.check_circle_rounded, size: 18, color: c.income),
              label: Text(l.goalsTodayDone),
            )
          else
            FilledButton.icon(
              onPressed: live && habit != null && !_markingToday
                  ? () => _markToday(habit)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Hit.min),
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(l.goalsMarkToday),
            ),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.sm,
            children: [
              TextButton.icon(
                onPressed: live && habit != null
                    ? () => flows.openHabitDetail(context, habit)
                    : null,
                style: TextButton.styleFrom(minimumSize: Hit.minSize),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l.goalsOpenHabit),
              ),
              _linkRow(goal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final related = goal.related!;
    final meta = goalMoneyMeta(goal);
    final live = !_previewOnly;

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(related.name, style: text.titleMedium),
          const SizedBox(height: Gap.xs),
          Text(
            l.goalsCurrentBalance,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: related.balanceCents != null
                ? MoneyText(
                    related.balanceCents!,
                    currency: related.currency ?? meta.currency,
                    subunitToUnit: related.subunitToUnit ?? meta.subunit,
                    variant: MoneyVariant.title,
                  )
                : _valueLine(formatGoalMoney(goal, goal.currentValue)),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            goalProgressLabel(goal),
            style: context.nokText.numMeta.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: live
                      ? () => context.push('/finance/account/${related.id}')
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(Hit.min),
                  ),
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(l.goalsOpenAccount),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(child: _refreshButton(goal)),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _linkRow(goal),
          ),
        ],
      ),
    );
  }

  /// A savings goal without an account: every income counts — never
  /// called a balance.
  Widget _incomeCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.goalsTotalIncome, style: text.titleMedium),
          const SizedBox(height: Gap.xs),
          Text(
            l.goalsIncomeCounts,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.md),
          // Full amounts, as the account card shows them: compact money is
          // for the grid's narrow cards (§3.7).
          _valueLine(goalProgressLabel(goal)),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              Expanded(child: _linkRow(goal)),
              const SizedBox(width: Gap.sm),
              Expanded(child: _refreshButton(goal)),
            ],
          ),
        ],
      ),
    );
  }

  /// "Yenile": the server works the progress out again. The button is
  /// disabled at once; its spinner shows only when that takes longer than
  /// [Motion.spinnerDelay].
  Widget _refreshButton(Goal goal) {
    final l = context.l10n;
    return OutlinedButton.icon(
      onPressed: _previewOnly || _recalcLoading
          ? null
          : () => _recalculate(goal),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(Hit.min),
      ),
      icon: _recalcSpinner
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(l.goalsRefresh),
    );
  }
}

/// One step of the manual stepper: 56 dp tall, "+1" / "−10" (the true minus
/// sign), a gold ripple; a screen reader hears "1 ekle" / "10 çıkar".
class _StepButton extends StatelessWidget {
  final int delta;
  final VoidCallback? onTap;

  const _StepButton({required this.delta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final amount = '${delta.abs()}';
    final label = delta > 0 ? '+$amount' : '$minusSign$amount';
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: delta > 0 ? l.goalsStepAdd(amount) : l.goalsStepRemove(amount),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: text.titleMedium!.copyWith(
                      fontFeatures: tabularFigures,
                      color: onTap == null ? c.inkDisabled : c.inkHi,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The detail's shape while a goal opened without its preview (a link) is
/// read: the ring, the tiles, the card — never a spinner.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.xxl,
          Insets.gutter,
          Gap.x4,
        ),
        children: const [
          Center(child: Bone.circle(size: 160)),
          SizedBox(height: Gap.xxl),
          Row(
            children: [
              Expanded(child: Bone(height: 64)),
              SizedBox(width: Gap.sm),
              Expanded(child: Bone(height: 64)),
              SizedBox(width: Gap.sm),
              Expanded(child: Bone(height: 64)),
            ],
          ),
          SizedBox(height: Gap.xxl),
          Bone(height: 220, shape: BoneShape.card),
        ],
      ),
    );
  }
}
