import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../data/data_scope.dart';
import '../../data/deferred_deletes.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';

/// How long a snackbar that offers an action ("Geri al") stays: long enough
/// to reach the action, short enough not to linger over the next screen
/// (design-research §4.3).
const actionSnackDuration = Duration(seconds: 6);

/// How long a plain message stays (the Material default).
const _plainSnackDuration = Duration(milliseconds: 4000);

/// How long a notice the user did not ask for stays — the sign-in screen's
/// "your session ended" line — long enough to read it once at large text.
const noticeSnackDuration = Duration(seconds: 8);

/// What a snackbar says about how things went (design-analysis §4.17).
enum SnackTone {
  /// A plain message, or an undo offer: no icon.
  plain,

  /// Done: `check_circle_rounded` in income.
  success,

  /// Failed: `error_rounded` in error, and the REJECT haptic.
  error,
}

/// How far a snackbar floats over a tab's FAB (16 + 56 + 8).
const _overFab = 80.0;

/// How far a snackbar floats over the capture bar.
const _overCaptureBar = 76.0;

/// How far a snackbar floats with nothing under it.
const _overNothing = 12.0;

/// Where a snackbar shown from [context] floats now (design-analysis
/// §4.17).
///
/// Snackbars are drawn by the outermost scaffold (the shell's, under the
/// navigation bar) — not by a tab's own scaffold, so they cannot see its
/// FAB or capture bar and are lifted above them: 80 dp over a tab's FAB
/// (16 + 56 + 8), 76 dp over the capture bar, 12 dp otherwise. A page's
/// own outermost scaffold lifts it over its FAB by itself.
///
/// The FAB and the bar on screen say where they are themselves
/// ([SnackClearance], put in place by `CollapsingFab` and
/// `CaptureBarLayout`), so any [context] under the app's messenger will do:
/// a screen's own (above its scaffold), a row's, a sheet's or a form's.
///
/// The app's snackbars do not keep this margin: they follow what is on
/// view while they show. A form that says "Kaydedildi" as it closes, or a
/// screen that says it the moment the form has gone, shows it while the
/// form still hides the tab; it floats over the tab's FAB or capture bar
/// once the tab is back on view.
EdgeInsets snackMarginFor(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return messenger == null
      ? _marginOver(null)
      : snackMarginOn(messenger);
}

/// Where a snackbar shown on [messenger] floats now: above the FAB or the
/// capture bar of the screen on view ([SnackClearance]), else 12 dp up.
EdgeInsets snackMarginOn(ScaffoldMessengerState messenger) =>
    _marginOver(_clearances[messenger]?.lift);

EdgeInsets _marginOver(double? lift) =>
    EdgeInsets.fromLTRB(16, 0, 16, lift ?? _overNothing);

/// What the screens on view under each messenger hold above its snackbars.
final _clearances = Expando<_Clearances>('snack clearances');

_Clearances _clearancesOn(ScaffoldMessengerState messenger) =>
    _clearances[messenger] ??= _Clearances();

/// The FABs and capture bars on view under one messenger. Tells the
/// snackbars on screen when the highest of them changes.
class _Clearances extends ChangeNotifier {
  final _holders = <_SnackClearanceState>{};

  /// What the snackbars were last told.
  double? _told;

  /// The highest lift on view, or null when nothing is.
  double? get lift {
    double? most;
    for (final h in _holders) {
      final lift = h.widget.lift;
      if (most == null || lift > most) most = lift;
    }
    return most;
  }

  void add(_SnackClearanceState holder) {
    if (_holders.add(holder)) _changed();
  }

  void remove(_SnackClearanceState holder) {
    if (_holders.remove(holder)) _changed();
  }

  /// A holder's lift changed.
  void touch() => _changed();

  void _changed() {
    final now = lift;
    if (now == _told) return;
    _told = now;
    // Holders come and go while the tree builds (a page popped turns the
    // tab's tickers back on): the snackbars rebuild in the next frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

/// Says that [child] — a tab's FAB or capture bar — sits at the bottom of
/// the screen, so the app's snackbars float [lift] dp up to clear it
/// ([snackMarginFor]) wherever they are shown from.
///
/// It counts only while it is on view: not on a tab in the background, not
/// under a page pushed over it (both turn its tickers off), and not while
/// [active] is false (a hidden FAB).
class SnackClearance extends StatefulWidget {
  const SnackClearance({
    super.key,
    required this.lift,
    this.active = true,
    required this.child,
  });

  /// Over a tab's FAB.
  static const overFab = _overFab;

  /// Over the capture bar.
  static const overCaptureBar = _overCaptureBar;

  final double lift;
  final bool active;
  final Widget child;

  @override
  State<SnackClearance> createState() => _SnackClearanceState();
}

class _SnackClearanceState extends State<SnackClearance> {
  _Clearances? _on;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final on = messenger == null ? null : _clearancesOn(messenger);
    if (!identical(on, _on)) _on?.remove(this);
    _on = on;
    _sync();
  }

  @override
  void didUpdateWidget(SnackClearance old) {
    super.didUpdateWidget(old);
    _sync();
    if (old.lift != widget.lift) _on?.touch();
  }

  void _sync() {
    final on = _on;
    if (on == null) return;
    if (_visible && widget.active) {
      on.add(this);
    } else {
      on.remove(this);
    }
  }

  @override
  void dispose() {
    _on?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A floating [SnackBar] whose margin follows the FAB or capture bar on
/// view under its messenger ([_clearances]) for as long as it shows,
/// rather than what was on view when it was shown.
class _LiftedSnackBar extends SnackBar {
  const _LiftedSnackBar({
    super.key,
    required this.clearances,
    this.pinned,
    required super.content,
    super.duration,
    super.persist,
    super.action,
    super.animation,
  });

  final _Clearances clearances;

  /// A margin given by the caller ([showAppSnack]'s `margin`): kept as is.
  final EdgeInsets? pinned;

  @override
  EdgeInsetsGeometry get margin => pinned ?? _marginOver(clearances.lift);

  // The messenger hands every snackbar its animation through this copy.
  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) =>
      _LiftedSnackBar(
        key: key ?? fallbackKey,
        clearances: clearances,
        pinned: pinned,
        content: content,
        duration: duration,
        persist: persist,
        action: action,
        animation: newAnimation,
      );

  @override
  State<SnackBar> createState() => _LiftedSnackBarState();
}

class _LiftedSnackBarState extends State<SnackBar> {
  @override
  Widget build(BuildContext context) {
    final bar = widget as _LiftedSnackBar;
    return ListenableBuilder(
      listenable: bar.clearances,
      builder: (context, _) => SnackBar(
        content: bar.content,
        margin: bar.margin,
        duration: bar.duration,
        persist: bar.persist,
        action: bar.action,
        animation: bar.animation,
        onVisible: bar.onVisible,
      ),
    );
  }
}

/// The app's snackbar: surface3 with the overlay border, 12 dp corners,
/// [message] in up to two lines after the [tone]'s 20 dp icon, the gold
/// action(s) — the theme draws the rest.
SnackBar _appSnackBar({
  required String message,
  required ScaffoldMessengerState messenger,
  EdgeInsets? margin,
  required Duration duration,
  bool persist = false,
  SnackTone tone = SnackTone.plain,
  String? actionLabel,
  VoidCallback? onAction,
  String? secondaryLabel,
  VoidCallback? onSecondary,
}) {
  final icon = switch (tone) {
    SnackTone.plain => null,
    SnackTone.success => Icons.check_circle_rounded,
    SnackTone.error => Icons.error_rounded,
  };
  final text = Text(message, maxLines: 2, overflow: TextOverflow.ellipsis);
  // Two actions do not fit SnackBarAction (it takes one): both are drawn
  // under the message, the primary last.
  final twoActions = secondaryLabel != null && actionLabel != null;
  return _LiftedSnackBar(
    clearances: _clearancesOn(messenger),
    pinned: margin,
    duration: duration,
    persist: persist,
    content: Builder(
      builder: (context) {
        final c = context.nok;
        final line = icon == null
            ? text
            : Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: tone == SnackTone.error ? c.error : c.income,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: text),
                ],
              );
        if (!twoActions) return line;
        void act(VoidCallback? run, SnackBarClosedReason reason) {
          run?.call();
          ScaffoldMessenger.of(context).hideCurrentSnackBar(reason: reason);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      act(onSecondary, SnackBarClosedReason.hide),
                  child: Text(secondaryLabel),
                ),
                TextButton(
                  onPressed: () =>
                      act(onAction, SnackBarClosedReason.action),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ],
        );
      },
    ),
    action: actionLabel == null || twoActions
        ? null
        : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  );
}

/// Shows [message] in the app's snackbar, replacing the one on screen
/// (design-analysis §4.17).
///
/// * [tone]: [SnackTone.success] or [SnackTone.error] put an icon before
///   the message; an error also plays the REJECT haptic. [isError] is the
///   older spelling of `tone: SnackTone.error`.
/// * One action ([actionLabel], [onAction]) — "Geri al" — or two, with
///   [secondaryLabel] and [onSecondary] ("Düzenle" + "Geri al", quick add
///   only), drawn under the message, both gold and 48 dp.
/// * It floats above the FAB or capture bar on view ([snackMarginFor]),
///   whichever [context] it is shown from.
///
/// With an action it stays [actionSnackDuration] and then goes, like any
/// other — Flutter would otherwise keep a snackbar with an action up until
/// it is swiped away, over every tab, since they share the messenger. It
/// stays until dismissed only while a screen reader or switch access is on
/// (`MediaQuery.accessibleNavigationOf`), where reaching the action can
/// take longer than any timeout. [duration] and [persist] override either
/// rule.
///
/// [margin] pins where it floats instead of following what is on view —
/// for a screen with a bar of its own at the bottom that no
/// [SnackClearance] reports (the journal editor's accessory bar).
///
/// Returns the snackbar's controller: its `closed` future says how it went
/// (`action` when the primary action was used).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  String? secondaryLabel,
  VoidCallback? onSecondary,
  SnackTone? tone,
  bool isError = false,
  Duration? duration,
  bool? persist,
  EdgeInsets? margin,
}) {
  final effectiveTone = tone ?? (isError ? SnackTone.error : SnackTone.plain);
  if (effectiveTone == SnackTone.error) Haptics.reject();
  final hasAction = actionLabel != null;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    _appSnackBar(
      message: message,
      messenger: messenger,
      margin: margin,
      tone: effectiveTone,
      duration:
          duration ?? (hasAction ? actionSnackDuration : _plainSnackDuration),
      persist: persist ??
          (hasAction && MediaQuery.accessibleNavigationOf(context)),
      actionLabel: actionLabel,
      onAction: onAction,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
    ),
  );
}

/// [showAppSnack] on [messenger] itself — for a message that comes after
/// the screen that started it may be gone, such as an undo that failed:
/// keep `ScaffoldMessenger.of(context)` from when it started and say it
/// here. Floats as [snackMarginOn] says; does nothing once [messenger] is
/// gone (an error still plays its haptic).
void showAppSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  SnackTone? tone,
  bool isError = false,
}) {
  final effectiveTone = tone ?? (isError ? SnackTone.error : SnackTone.plain);
  if (effectiveTone == SnackTone.error) Haptics.reject();
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(_appSnackBar(
      message: message,
      messenger: messenger,
      tone: effectiveTone,
      duration: _plainSnackDuration,
    ));
}

/// What a refused delete can offer instead, by the refusal: an account
/// with history can be archived. Null offers nothing.
typedef DeleteRecovery = ({String label, VoidCallback run})? Function(
  Object error,
);

/// How a refused delete is worded where the app's usual wording
/// ([failureMessage]) does not fit the record — an archived account cannot
/// be told to archive itself instead. Null keeps the usual wording.
typedef DeleteRefusal = String? Function(Object error);

/// Tells the user a delete was refused (the record is back): what
/// [explain] says, else the server's reason when it gave one, else
/// [fallback] — and what [recover] offers.
void _sayRefused(
  ScaffoldMessengerState messenger,
  AppL10n l,
  Object error, {
  required String fallback,
  DeleteRecovery? recover,
  DeleteRefusal? explain,
}) {
  Haptics.reject();
  if (!messenger.mounted) return;
  final action = recover?.call(error);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(_appSnackBar(
      message:
          explain?.call(error) ?? failureMessage(error, l, fallback: fallback),
      messenger: messenger,
      tone: SnackTone.error,
      duration: action == null ? _plainSnackDuration : actionSnackDuration,
      actionLabel: action?.label,
      onAction: action?.run,
    ));
}

/// Deletes [record] the forgiving way (design-research §4.3): it leaves
/// every list at once, the snackbar says [message] and offers "Geri al" for
/// [actionSnackDuration], and the delete — [send] — goes out only when the
/// undo window closes:
///
/// * the snackbar goes for any reason but its action (it times out, is
///   swiped away, or a newer message replaces it);
/// * the user leaves the screen it was made on — [context]'s route is
///   popped. The snackbar lives on the app's messenger and would otherwise
///   follow them back, while the screen they land on still counted the
///   record in its totals and balances. The snackbar goes with it: its undo
///   no longer can;
/// * the app is hidden.
///
/// Undo just shows the record again: nothing was sent.
///
/// [context] is the screen's, then — not a sheet's, which closes first.
/// A screen that is the first of its navigator (a tab) is never left that
/// way; nor is a navigator's own context, which a delete that closes its
/// screen (an account's) passes on purpose: there only the snackbar and
/// the app end the window.
///
/// Should the server refuse the delete once it is sent, the record comes
/// back and the snackbar says so — in [explain]'s words, else with the
/// server's reason when it gave one, else [failedMessage] — and offers what
/// [recover] has for it.
void deleteWithUndo(
  BuildContext context,
  DeferredDeletes deletes, {
  required DeletedRecord record,
  required String message,
  required Future<void> Function() send,
  String? failedMessage,
  DeleteRecovery? recover,
  DeleteRefusal? explain,
}) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  deletes.stage(
    record,
    send: send,
    onFailed: (error) => _sayRefused(
      messenger,
      l,
      error,
      fallback: failedMessage ?? l.errDeleteFailed,
      recover: recover,
      explain: explain,
    ),
  );
  // Silent: deleting plays no haptic — the snackbar is the feedback.
  final snack = showAppSnack(
    context,
    message,
    actionLabel: l.actionUndo,
    onAction: () => deletes.undo(record),
  );
  snack.closed.then((reason) {
    if (reason == SnackBarClosedReason.action) return;
    deletes.commit(record);
  });
  final route = ModalRoute.of(context);
  if (route != null && !route.isFirst) {
    route.popped.then((_) {
      // Undone, or sent already: the window closed before the screen did.
      if (!deletes.isWaiting(record)) return;
      deletes.commit(record);
      // While the delete waited, its snackbar was the one on screen, or
      // next in line behind one still going: either way it is taken down,
      // and its "Geri al" with it.
      if (messenger.mounted) messenger.clearSnackBars();
    });
  }
}

/// A delete the user already confirmed in a dialog — one that cascades, so
/// it has no undo: [record] leaves the lists at once and the delete is sent
/// now. The snackbar says [message] once the server has deleted it; should
/// the server refuse, the record comes back and the snackbar says why.
///
/// [alongWith] are the records the server deletes with it (a transaction's
/// linked counter-transaction): they leave the lists, and come back, with
/// [record].
void deleteNow(
  BuildContext context,
  DeferredDeletes deletes, {
  required DeletedRecord record,
  required String message,
  required Future<void> Function() send,
  String? failedMessage,
  DeleteRecovery? recover,
  DeleteRefusal? explain,
  Set<DeletedRecord> alongWith = const {},
}) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  deletes.stage(
    record,
    send: send,
    alongWith: alongWith,
    onFailed: (error) => _sayRefused(
      messenger,
      l,
      error,
      fallback: failedMessage ?? l.errDeleteFailed,
      recover: recover,
      explain: explain,
    ),
  );
  // Silent, like every delete: the snackbar says it went.
  deletes.commit(record).then((deleted) {
    if (deleted && messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(_appSnackBar(
          message: message,
          messenger: messenger,
          duration: _plainSnackDuration,
        ));
    }
  });
}
