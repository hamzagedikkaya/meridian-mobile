import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/money_text.dart';
import 'transaction_form_screen.dart';
import 'tx_row.dart';

/// Deletes [tx] with "Geri al": it leaves every list at once and the delete
/// is sent when the undo window closes (see `deleteWithUndo`). Nothing is
/// re-created on undo, so a note, a linked counter-transaction the delete
/// would take along, and the row's id all stay as they were.
void deleteTransactionWithUndo(
  BuildContext context,
  WidgetRef ref,
  Transaction tx,
) {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  deleteWithUndo(
    context,
    ref.read(deferredDeletesProvider.notifier),
    record: (scope: DataScope.transactions, id: tx.id),
    message: l.txDeleted,
    send: () => repo.deleteTransaction(tx.id),
    failedMessage: l.txDeleteFailed,
  );
}

/// Opens [tx]'s edit form; [onSaved] gets the transaction as the server
/// saved it (a feed puts it in place at once with it).
Future<void> editTransaction(
  BuildContext context,
  Transaction tx, {
  void Function(Transaction saved)? onSaved,
}) async {
  final l = context.l10n;
  final saved = await openTransactionForm(context, existing: tx);
  if (saved == null || !context.mounted) return;
  onSaved?.call(saved);
  showAppSnack(context, l.txUpdated);
}

/// The detail sheet of a transaction — the one way a tapped transaction
/// opens, on Finance, İşlemler and an account's screen alike: what it is,
/// its note, "Düzenle" as the full-width primary and a quieter "Sil" below
/// it. [perspectiveAccountId] signs a transfer by direction, as the row
/// did; [onSaved] gets an edit's saved transaction.
Future<void> showTransactionSheet(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  int? perspectiveAccountId,
  void Function(Transaction saved)? onSaved,
}) {
  final c = context.nok;
  final text = Theme.of(context).textTheme;
  final l = context.l10n;
  final described = TxRow.describe(l, tx);
  final note = tx.note?.trim() ?? '';
  final isTransfer = tx.kind == 'transfer';
  final incoming = isTransfer &&
      perspectiveAccountId != null &&
      tx.relatedAccount?.id == perspectiveAccountId;
  final outgoing = isTransfer &&
      perspectiveAccountId != null &&
      tx.account.id == perspectiveAccountId;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(described.title, style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                described.meta,
                formatDate(tx.date, withYear: true),
              ].where((part) => part.isNotEmpty).join(' · '),
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: MoneyText(
                tx.amountCents,
                currency: tx.account.currency,
                subunitToUnit: tx.account.subunitToUnit,
                variant: MoneyVariant.title,
                signed: tx.kind == 'income' || incoming,
                positiveGreen: tx.kind == 'income' || incoming,
                negative: tx.kind == 'expense' || outgoing,
              ),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l.txFormNote,
                style: text.labelMedium!.copyWith(color: c.inkMid),
              ),
              const SizedBox(height: 4),
              Text(note, style: text.bodyMedium),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                editTransaction(context, tx, onSaved: onSaved);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.actionEdit),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                Navigator.of(sheetCtx).pop();
                deleteTransactionWithUndo(context, ref, tx);
              },
              style: TextButton.styleFrom(
                foregroundColor: c.error,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.actionDelete),
            ),
          ],
        ),
      ),
    ),
  );
}
