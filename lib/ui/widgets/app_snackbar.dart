import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../data/data_scope.dart';
import '../../data/deferred_deletes.dart';
import '../../l10n/app_l10n.dart';

/// How long a snackbar that offers an action ("Geri al") stays: long enough
/// to reach the action, short enough not to linger over the next screen
/// (design-research §4.3).
const actionSnackDuration = Duration(seconds: 6);

/// How long a plain message stays (the Material default).
const _plainSnackDuration = Duration(milliseconds: 4000);

/// Shows [message] in the app's snackbar, replacing the one on screen.
///
/// With an action ([actionLabel], [onAction]) it stays [actionSnackDuration]
/// and then goes, like any other — Flutter would otherwise keep a snackbar
/// with an action up until it is swiped away, over every tab, since they
/// share the messenger. It stays until dismissed only while a screen reader
/// or switch access is on (`MediaQuery.accessibleNavigationOf`), where
/// reaching the action can take longer than any timeout. [duration] and
/// [persist] override either rule.
///
/// Returns the snackbar's controller: its `closed` future says how it went.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool isError = false,
  Duration? duration,
  bool? persist,
}) {
  if (isError) Haptics.danger();
  final hasAction = actionLabel != null;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration:
          duration ?? (hasAction ? actionSnackDuration : _plainSnackDuration),
      persist: persist ??
          (hasAction && MediaQuery.accessibleNavigationOf(context)),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
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
  DeleteRecovery? recover,
  DeleteRefusal? explain,
}) {
  Haptics.danger();
  if (!messenger.mounted) return;
  final action = recover?.call(error);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(
        explain?.call(error) ?? failureMessage(error, l, fallback: fallback),
      ),
      duration: action == null ? _plainSnackDuration : actionSnackDuration,
      persist: false,
      action: action == null
          ? null
          : SnackBarAction(label: action.label, onPressed: action.run),
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
  Haptics.tick();
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
  Haptics.danger();
  deletes.commit(record).then((deleted) {
    if (deleted && messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  });
}
