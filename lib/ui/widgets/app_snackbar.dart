import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../data/data_scope.dart';
import '../../data/deferred_deletes.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'capture_bar.dart';

/// How long a snackbar that offers an action ("Geri al") stays: long enough
/// to reach the action, short enough not to linger over the next screen
/// (design-research §4.3).
const actionSnackDuration = Duration(seconds: 6);

/// How long a plain message stays (the Material default).
const _plainSnackDuration = Duration(milliseconds: 4000);

/// What a snackbar says about how things went (design-analysis §4.17).
enum SnackTone {
  /// A plain message, or an undo offer: no icon.
  plain,

  /// Done: `check_circle_rounded` in income.
  success,

  /// Failed: `error_rounded` in error, and the REJECT haptic.
  error,
}

/// Where a snackbar shown from [context] floats (design-analysis §4.17).
///
/// Snackbars are drawn by the outermost scaffold (the shell's, under the
/// navigation bar) — not by a tab's own scaffold, so they cannot see its
/// FAB or capture bar and are lifted above them here: 80 dp over a tab's
/// FAB (16 + 56 + 8), 76 dp over the capture bar, 12 dp otherwise. A
/// page's own outermost scaffold lifts it over its FAB by itself.
///
/// [context] must be the screen's: a sheet (`showNokSheet`) sits on the
/// root navigator, outside the tab, and a sheet's context sees neither
/// the FAB nor the capture bar — keep the screen's context and use it
/// after the sheet closes.
EdgeInsets snackMarginFor(BuildContext context) {
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold != null &&
      scaffold.hasFloatingActionButton &&
      scaffold.context.findAncestorStateOfType<ScaffoldState>() != null) {
    return const EdgeInsets.fromLTRB(16, 0, 16, 80);
  }
  if (CaptureBarScope.maybeOf(context) != null) {
    return const EdgeInsets.fromLTRB(16, 0, 16, 76);
  }
  return const EdgeInsets.fromLTRB(16, 0, 16, 12);
}

/// The app's snackbar: surface3 with the overlay border, 12 dp corners,
/// [message] in up to two lines after the [tone]'s 20 dp icon, the gold
/// action(s) — the theme draws the rest.
SnackBar _appSnackBar({
  required String message,
  required EdgeInsets margin,
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
  return SnackBar(
    margin: margin,
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
/// * It floats above the screen's FAB or capture bar ([snackMarginFor]) —
///   pass the screen's [context], never a sheet's, or it cannot see them.
///
/// With an action it stays [actionSnackDuration] and then goes, like any
/// other — Flutter would otherwise keep a snackbar with an action up until
/// it is swiped away, over every tab, since they share the messenger. It
/// stays until dismissed only while a screen reader or switch access is on
/// (`MediaQuery.accessibleNavigationOf`), where reaching the action can
/// take longer than any timeout. [duration] and [persist] override either
/// rule.
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
}) {
  final effectiveTone = tone ?? (isError ? SnackTone.error : SnackTone.plain);
  if (effectiveTone == SnackTone.error) Haptics.danger();
  final hasAction = actionLabel != null;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    _appSnackBar(
      message: message,
      margin: snackMarginFor(context),
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
  required EdgeInsets margin,
  DeleteRecovery? recover,
  DeleteRefusal? explain,
}) {
  Haptics.danger();
  if (!messenger.mounted) return;
  final action = recover?.call(error);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(_appSnackBar(
      message:
          explain?.call(error) ?? failureMessage(error, l, fallback: fallback),
      margin: margin,
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
  final margin = snackMarginFor(context);
  deletes.stage(
    record,
    send: send,
    onFailed: (error) => _sayRefused(
      messenger,
      l,
      error,
      fallback: failedMessage ?? l.errDeleteFailed,
      margin: margin,
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
  final margin = snackMarginFor(context);
  deletes.stage(
    record,
    send: send,
    alongWith: alongWith,
    onFailed: (error) => _sayRefused(
      messenger,
      l,
      error,
      fallback: failedMessage ?? l.errDeleteFailed,
      margin: margin,
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
          margin: margin,
          duration: _plainSnackDuration,
        ));
    }
  });
}
