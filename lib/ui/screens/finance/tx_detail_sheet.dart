import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/swipe_action.dart';
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

/// A transaction row a swipe to the left deletes (design-analysis §4.28):
/// the errorContainer background warms to error under "Sil", the row folds
/// away and "Geri al" offers it back — no dialog, no haptic on the delete —
/// unless the delete would take a linked transaction along: then the row
/// stays swiped open under the dialog that names it, and slides back if
/// the user keeps it (see [planTransactionDelete]). Screen readers get the
/// same as the row's "Sil" action; a long press and the row's sheet have
/// "Sil" too.
class TxSwipeToDelete extends ConsumerStatefulWidget {
  final Transaction tx;
  final Widget child;

  const TxSwipeToDelete({required super.key, required this.tx, required this.child});

  @override
  ConsumerState<TxSwipeToDelete> createState() => _TxSwipeToDeleteState();
}

class _TxSwipeToDeleteState extends ConsumerState<TxSwipeToDelete> {
  /// The delete the swipe settled on, run once the row has folded away.
  VoidCallback? _delete;

  Future<bool> _plan() async {
    _delete = await planTransactionDelete(context, ref, widget.tx);
    return _delete != null;
  }

  void _dismissed() {
    final delete = _delete;
    _delete = null;
    delete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SwipeAction(
      key: ValueKey(widget.tx.id),
      endToStart: SwipeSpec.delete(
        context.nok,
        label: context.l10n.actionDelete,
        onSwipe: _plan,
        onDismissed: _dismissed,
      ),
      child: widget.child,
    );
  }
}

/// Copies [tx] to today: the same kind, amount, accounts, category,
/// description and note, dated the account's today — saved at once, with
/// "Geri al", which deletes the copy. [onSaved] gets the copy as the server
/// saved it (a feed puts it in place at once with it).
Future<void> copyTransactionToToday(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  void Function(Transaction saved)? onSaved,
}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final transfer = tx.kind == 'transfer';
  try {
    final copy = await repo.createTransaction(TransactionInput(
      kind: tx.kind,
      amountCents: tx.amountCents,
      date: ref.read(currentDayProvider),
      description: _orNull(tx.description),
      note: _orNull(tx.note),
      accountId: tx.account.id,
      financeCategoryId: transfer ? null : tx.category?.id,
      relatedAccountId: transfer ? tx.relatedAccount?.id : null,
    ));
    if (!context.mounted) return;
    Haptics.confirm();
    onSaved?.call(copy);
    showAppSnack(
      context,
      l.txCopiedToToday,
      actionLabel: l.actionUndo,
      onAction: () async {
        try {
          await repo.deleteTransaction(copy.id);
        } catch (e) {
          if (context.mounted) {
            showAppSnack(
              context,
              failureMessage(e, l, fallback: l.txDeleteFailed),
              isError: true,
            );
          } else {
            Haptics.reject();
          }
        }
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    // The answer was lost: the copy may well be saved (a POST is not safe
    // to repeat) — say so, rather than invite a second copy.
    final maybe = e is ApiException && e.isNetwork && e.mayHaveArrived;
    showAppSnack(
      context,
      maybe ? l.txSaveMaybe : failureMessage(e, l, fallback: l.txCopyFailed),
      isError: true,
    );
  }
}

String? _orNull(String? text) {
  final value = text?.trim() ?? '';
  return value.isEmpty ? null : text;
}

/// A row's gesture-only actions as screen-reader actions: "Düzenle" and
/// "Bugüne kopyala" (the swipe adds "Sil").
Map<CustomSemanticsAction, VoidCallback> txRowSemanticActions(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  void Function(Transaction saved)? onSaved,
}) {
  final l = context.l10n;
  return {
    CustomSemanticsAction(label: l.actionEdit): () =>
        editTransaction(context, tx, onSaved: onSaved),
    CustomSemanticsAction(label: l.txCopyToToday): () =>
        copyTransactionToToday(context, ref, tx, onSaved: onSaved),
  };
}

/// What a long press on a transaction row offers (design-analysis §6.4):
/// Düzenle · Bugüne kopyala · Sil, in a sheet titled with the row's title.
/// [context] and [ref] are the screen's: what each action opens or says
/// outlives the sheet.
Future<void> showTransactionActions(
  BuildContext context,
  WidgetRef ref,
  Transaction tx, {
  void Function(Transaction saved)? onSaved,
}) async {
  final l = context.l10n;
  final action = await showNokSheet<String>(
    context,
    title: TxRow.describe(l, tx).title,
    builder: (sheet) {
      final c = sheet.nok;
      Widget row(String value, IconData icon, String label, {Color? color}) =>
          ListTile(
            leading: Icon(icon, color: color ?? c.inkMid),
            title: Text(
              label,
              style: Theme.of(sheet)
                  .textTheme
                  .titleMedium!
                  .copyWith(color: color),
            ),
            onTap: () => Navigator.of(sheet).pop(value),
          );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('edit', Icons.edit_outlined, l.actionEdit),
              row('copy', Icons.content_copy_rounded, l.txCopyToToday),
              row('delete', Icons.delete_outline_rounded, l.actionDelete,
                  color: c.error),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'edit':
      await editTransaction(context, tx, onSaved: onSaved);
    case 'copy':
      await copyTransactionToToday(context, ref, tx, onSaved: onSaved);
    case 'delete':
      final delete = await planTransactionDelete(context, ref, tx);
      delete?.call();
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

/// The detail sheet of a transaction (design-analysis §7.7) — the one way
/// a tapped transaction opens, on Finance, İşlemler and an account's screen
/// alike: its title (the description, else the category) in Fraunces, the
/// amount, a table of account · category · date · note, the other row of
/// its linked pair if it has one, "Düzenle" as the full-width primary and,
/// 24 dp below, the error-coloured "Sil" (with "Geri al").
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
  return showNokSheet<void>(
    context,
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
        Haptics.reject();
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
    final note = tx.note?.trim() ?? '';
    final perspective = widget.perspectiveAccountId;
    final isTransfer = tx.kind == 'transfer';
    final incoming = isTransfer &&
        perspective != null &&
        tx.relatedAccount?.id == perspective;
    final outgoing =
        isTransfer && perspective != null && tx.account.id == perspective;
    final route = tx.relatedAccount == null
        ? tx.account.name
        : '${tx.account.name} → ${tx.relatedAccount!.name}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: TxRow.describe(l, tx).title,
          entityTitle: true,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: Gap.lg),
                _MetaRow(label: l.txFormAccount, value: route),
                _MetaRow(
                  label: l.txFormCategory,
                  value: isTransfer
                      ? l.financeTransfer
                      : (tx.category?.name ?? l.financeUncategorized),
                ),
                _MetaRow(
                  label: l.txFormDate,
                  value: formatDate(tx.date, withYear: true),
                ),
                if (note.isNotEmpty) _MetaRow(label: l.txFormNote, value: note),
                if (linked != null) ...[
                  const SizedBox(height: Gap.lg),
                  _LinkedSection(linked: linked),
                ],
                if (gone) ...[
                  // Deleted on the web or another device: there is nothing
                  // left to edit or delete, and the lists are refetched
                  // already.
                  const SizedBox(height: Gap.xxl),
                  Semantics(
                    liveRegion: true,
                    child: Text(l.txGone, style: text.titleSmall),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    l.errRecordGoneBody,
                    style: text.bodySmall!.copyWith(color: c.inkMid),
                  ),
                  const SizedBox(height: Gap.lg),
                ],
              ],
            ),
          ),
        ),
        if (!gone)
          SheetActions(
            primary: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                editTransaction(widget.host, tx, onSaved: widget.onSaved);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.actionEdit),
            ),
            destructive: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton.icon(
                  onPressed: _deleting ? null : () => _delete(tx, detail),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(Hit.min),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
            ),
          )
        else
          const SafeArea(top: false, child: SizedBox.shrink()),
      ],
    );
  }
}

/// One line of the sheet's table: the [label] in inkMid, the [value]
/// after it; the value wraps rather than being cut.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96),
                child: Text(
                  label,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: text.bodyMedium!.copyWith(color: c.inkHi),
                ),
              ),
            ],
          ),
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
