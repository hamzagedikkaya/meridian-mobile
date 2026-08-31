import 'package:flutter/material.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';

/// Destructive confirm — cancel text button + filled error button (design §4.8).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
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
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: c.error,
                  foregroundColor: c.inkHi,
                  minimumSize: const Size(0, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(confirmLabel ?? l.actionConfirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
