import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/money_text.dart';
import '../../widgets/sync_hint.dart';
import 'finance_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_row.dart';

/// How deleting [tx] goes, settled before it leaves any list.
///
/// The web can save a transaction with a linked counter-transaction (an
/// expense on one account and an income on another: buying gold with cash).
/// Deleting the pair's parent deletes the other row too (GET
/// /transactions/:id says so: `linked.relation == "child"`), which moves
/// another account's balance and cannot be undone — so that delete asks
/// first, naming the other row, and is sent at once ([deleteNow]). Any other
/// transaction goes with "Geri al" ([deleteWithUndo]): nothing is re-created
/// on undo, so a note and the row's id stay as they were.
///
/// Resolves to the delete to run, or null when the user kept the
/// transaction — or when what it is linked to could not be read: nothing is
/// deleted then, and [onUnreadable] hears why (by default a snackbar says
/// it). [known] is the detail when it is at hand already (the sheet's). The
/// delete's snackbars are shown from [context].
Future<VoidCallback?> planTransactionDelete(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  TransactionDetail? known,
  void Function(Object error)? onUnreadable,
}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final deletes = ref.read(deferredDeletesProvider.notifier);
  void unreadable(Object error) {
    if (onUnreadable != null) {
      onUnreadable(error);
    } else if (context.mounted) {
      _sayKept(context, error);
    }
  }

  var detail = known;
  if (detail == null) {
    try {
      detail = await repo.fetchTransaction(tx.id);
    } on ApiException catch (e) {
      // Gone already (deleted on the web): nothing is left to take along,
      // and its delete counts it as deleted.
      if (e.kind != ApiErrorKind.notFound) {
        unreadable(e);
        return null;
      }
    } catch (e) {
      unreadable(e);
      return null;
    }
  }
  if (!context.mounted) return null;
  final record = (scope: DataScope.transactions, id: tx.id);
  Future<void> send() => repo.deleteTransaction(tx.id);
  final linked = detail?.linked;
  if (linked == null || !linked.isChild) {
    return () {
      if (!context.mounted) return;
      deleteWithUndo(
        context,
        deletes,
        record: record,
        message: l.txDeleted,
        send: send,
        failedMessage: l.txDeleteFailed,
      );
    };
  }
  final confirmed = await showConfirmDialog(
    context,
    title: l.txDeleteLinkedTitle(TxRow.describe(l, tx).title),
    message: l.txDeleteLinkedBody(describeLinked(l, linked)),
    confirmLabel: l.txDeleteBoth,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return null;
  return () {
    if (!context.mounted) return;
    deleteNow(
      context,
      deletes,
      record: record,
      alongWith: {(scope: DataScope.transactions, id: linked.id)},
      message: l.txDeletedWithLinked,
      send: send,
      failedMessage: l.txDeleteFailed,
    );
  };
}

/// What it is linked to could not be read, so nothing was deleted.
void _sayKept(BuildContext context, Object error) => showAppSnack(
      context,
      failureMessage(error, context.l10n, fallback: context.l10n.txDeleteFailed),
      isError: true,
    );

/// The other row of a linked pair in a few words: "Altın · +2 gr ·
/// 2 Ekim 2026".
String describeLinked(AppL10n l, LinkedTransaction linked) => [
      linked.account.name,
      formatMoney(
        linked.amountCents,
        linked.account.currency,
        linked.account.subunitToUnit,
        signed: linked.kind == 'income',
        negative: linked.kind == 'expense',
      ),
      formatDate(linked.date, withYear: true),
    ].join(' · ');

/// A transaction row a swipe to the left deletes (design-research §4.2) —
/// with "Geri al" and no dialog, unless the delete would take a linked
/// transaction along: then the row stays swiped open under the dialog that
/// names it, and slides back if the user keeps it (see
/// [planTransactionDelete]). Screen readers get the same as an action, and
/// a tap opens the row's sheet, which has "Sil" too.
class TxSwipeToDelete extends ConsumerStatefulWidget {
  final Transaction tx;
  final Widget child;

  const TxSwipeToDelete({required super.key, required this.tx, required this.child});

  @override
  ConsumerState<TxSwipeToDelete> createState() => _TxSwipeToDeleteState();
}

class _TxSwipeToDeleteState extends ConsumerState<TxSwipeToDelete> {
  /// The delete the swipe settled on, run once the row has slid away.
  VoidCallback? _delete;

  Future<bool> _confirm() async {
    _delete = await planTransactionDelete(context, ref, widget.tx);
    return _delete != null;
  }

  void _dismissed() {
    final delete = _delete;
    _delete = null;
    delete?.call();
  }

  Future<void> _deleteAction() async {
    final delete = await planTransactionDelete(context, ref, widget.tx);
    delete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.actionDelete): _deleteAction,
      },
      child: Dismissible(
        key: ValueKey(widget.tx.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirm(),
        onDismissed: (_) => _dismissed(),
        background: Container(
          color: c.error,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.actionDelete,
                style: text.labelLarge!.copyWith(color: c.bg),
              ),
              const SizedBox(width: 8),
              Icon(Icons.delete_outline, color: c.bg),
            ],
          ),
        ),
        child: widget.child,
      ),
    );
  }
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
/// its note, the other row of its linked pair if it has one, "Düzenle" as
/// the full-width primary and a quieter "Sil" below it.
/// [perspectiveAccountId] signs a transfer by direction, as the row did;
/// [onSaved] gets an edit's saved transaction.
///
/// [context] and [ref] are the screen's: the edit form, the delete and
/// their snackbars outlive the sheet.
Future<void> showTransactionSheet(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  int? perspectiveAccountId,
  void Function(Transaction saved)? onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _TransactionSheet(
      host: context,
      hostRef: ref,
      tx: tx,
      perspectiveAccountId: perspectiveAccountId,
      onSaved: onSaved,
    ),
  );
}

class _TransactionSheet extends ConsumerStatefulWidget {
  final BuildContext host;
  final WidgetRef hostRef;
  final Transaction tx;
  final int? perspectiveAccountId;
  final void Function(Transaction saved)? onSaved;

  const _TransactionSheet({
    required this.host,
    required this.hostRef,
    required this.tx,
    this.perspectiveAccountId,
    this.onSaved,
  });

  @override
  ConsumerState<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<_TransactionSheet> {
  /// "Sil" is settling how the delete goes (reading what the transaction
  /// is linked to, or asking): a second tap waits for it.
  bool _deleting = false;

  /// Why "Sil" deleted nothing: what the transaction is linked to could not
  /// be read. Said in the sheet — a snackbar would be under it.
  String? _deleteError;

  Future<void> _delete(Transaction tx, TransactionDetail? detail) async {
    final l = context.l10n;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    String? unreadable;
    final delete = await planTransactionDelete(
      widget.host,
      widget.hostRef,
      tx,
      known: detail,
      onUnreadable: (error) {
        Haptics.danger();
        unreadable = failureMessage(error, l, fallback: l.txDeleteFailed);
      },
    );
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _deleteError = unreadable;
    });
    if (delete == null) return;
    Navigator.of(context).pop();
    delete();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(transactionDetailProvider(widget.tx.id));
    final gone = async.isGone;
    final detail = gone ? null : async.value?.data;
    // The row it was opened from stands in until the detail is in.
    final tx = detail?.transaction ?? widget.tx;
    final linked = detail?.linked;
    final described = TxRow.describe(l, tx);
    final note = tx.note?.trim() ?? '';
    final perspective = widget.perspectiveAccountId;
    final isTransfer = tx.kind == 'transfer';
    final incoming = isTransfer &&
        perspective != null &&
        tx.relatedAccount?.id == perspective;
    final outgoing =
        isTransfer && perspective != null && tx.account.id == perspective;
    return SafeArea(
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
            if (linked != null) ...[
              const SizedBox(height: 16),
              _LinkedSection(linked: linked),
            ],
            if (gone) ...[
              // Deleted on the web or another device: there is nothing left
              // to edit or delete, and the lists are refetched already.
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(l.txGone, style: text.titleSmall),
              ),
              const SizedBox(height: 4),
              Text(
                l.errRecordGoneBody,
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ] else ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  editTransaction(widget.host, tx, onSaved: widget.onSaved);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l.actionEdit),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _deleting ? null : () => _delete(tx, detail),
                style: TextButton.styleFrom(
                  foregroundColor: c.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l.actionDelete),
              ),
              if (_deleteError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _deleteError!,
                    textAlign: TextAlign.center,
                    style: text.bodySmall!.copyWith(color: c.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The other row of a transaction's linked pair, and what deleting the
/// transaction does to it.
class _LinkedSection extends StatelessWidget {
  final LinkedTransaction linked;

  const _LinkedSection({required this.linked});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final description = linked.description?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.txLinkedTitle,
          style: text.labelMedium!.copyWith(color: c.inkMid),
        ),
        const SizedBox(height: 8),
        MergeSemantics(
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: hexColor(linked.account.color, fallback: c.inkLow),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(linked.account.name, style: text.titleSmall),
                    Text(
                      [
                        if (description.isNotEmpty) description,
                        formatDate(linked.date, withYear: true),
                      ].join(' · '),
                      style: text.bodySmall!.copyWith(color: c.inkMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MoneyText(
                linked.amountCents,
                currency: linked.account.currency,
                subunitToUnit: linked.account.subunitToUnit,
                signed: linked.kind == 'income',
                positiveGreen: linked.kind == 'income',
                negative: linked.kind == 'expense',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          linked.isChild ? l.txLinkedDeletedAlong : l.txLinkedStays,
          style: text.bodySmall!.copyWith(
            color: linked.isChild ? c.warning : c.inkMid,
          ),
        ),
      ],
    );
  }
}
