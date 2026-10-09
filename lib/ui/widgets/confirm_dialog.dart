import 'package:flutter/material.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';

/// The confirm dialog (design-analysis §4.16) — kept for the five cases
/// where an action cannot be undone or reaches further than it looks
/// (IA-20): deleting a category in use, an account with history, a list
/// with tasks; archiving a habit that feeds a goal; deleting a habit for
/// good. Everything else deletes at once and offers "Geri al".
///
/// [title] names the thing, [message] the outcome — with numbers ("12
/// işlem 'Market'e taşınacak"). [confirmLabel] is a verb naming the outcome
/// ("Sil ve taşı", "Çıkış yap") — never a bare "Onayla". "Vazgeç"
/// ([cancelLabel]) is on the left, the verb filled on the right; a
/// [destructive] verb is error-filled with an onError label (6.18:1).
/// True when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
  String? cancelLabel,
}) async {
  final c = context.nok;
  final l = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: c.inkHi),
          child: Text(cancelLabel ?? l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, Hit.min),
            backgroundColor: destructive ? c.error : null,
            foregroundColor: destructive ? c.onError : null,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A dialog that only tells: why something cannot be done, with nothing to
/// offer instead — one "Tamam" closes it.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  String? message,
}) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: const Size(64, Hit.min)),
          child: Text(l.actionDone),
        ),
      ],
    ),
  );
}
