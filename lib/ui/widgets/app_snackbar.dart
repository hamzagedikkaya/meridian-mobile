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

/// Deletes [record] the forgiving way (design-research §4.3): it leaves
/// every list at once, the snackbar says [message] and offers "Geri al" for
/// [actionSnackDuration], and the delete — [send] — goes out only when the
/// snackbar goes for any other reason (it times out, is swiped away, or a
/// newer message replaces it), or when the app is hidden. Undo just shows
/// the record again: nothing was sent.
///
/// Should the server refuse the delete once it is sent, the record comes
/// back and the snackbar says so — with the server's reason when it gave
/// one, else [failedMessage].
void deleteWithUndo(
  BuildContext context,
  DeferredDeletes deletes, {
  required DeletedRecord record,
  required String message,
  required Future<void> Function() send,
  String? failedMessage,
}) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  deletes.stage(
    record,
    send: send,
    onFailed: (error) {
      Haptics.danger();
      if (!messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(failureMessage(
            error,
            l,
            fallback: failedMessage ?? l.errDeleteFailed,
          )),
        ));
    },
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
}

/// A delete the user already confirmed in a dialog — one that cascades, so
/// it has no undo: [record] leaves the lists at once and the delete is sent
/// now. The snackbar says [message] once the server has deleted it; should
/// the server refuse, the record comes back and the snackbar says why.
void deleteNow(
  BuildContext context,
  DeferredDeletes deletes, {
  required DeletedRecord record,
  required String message,
  required Future<void> Function() send,
  String? failedMessage,
}) {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  deletes.stage(
    record,
    send: send,
    onFailed: (error) {
      Haptics.danger();
      if (!messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(failureMessage(
            error,
            l,
            fallback: failedMessage ?? l.errDeleteFailed,
          )),
        ));
    },
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
