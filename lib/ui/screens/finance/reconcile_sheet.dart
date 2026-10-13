import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';

/// The opening balance that makes [account]'s balance read [actual]
/// (design-analysis §7.6): the balance is the opening balance plus every
/// transaction, so moving the opening balance by the difference moves the
/// balance — today's and every past one — by exactly that much. Contract
/// §4.2 `PATCH /accounts/:id {initial_balance_cents}`; no transaction is
/// written.
int reconciledInitialBalance(Account account, int actual) =>
    account.initialBalanceCents + (actual - account.balanceCents);

/// What a reconcile sends: [account] as it is, with [initialBalanceCents]
/// — the edit's body is then that one key ([AccountInput.changesFrom]).
AccountInput reconcileInput(Account account, int initialBalanceCents) =>
    AccountInput(
      name: account.name,
      accountType: account.accountType,
      currency: account.currency,
      initialBalanceCents: initialBalanceCents,
      color: account.color,
    );

/// "Bakiyeyi eşitle": the "Gerçek bakiye" sheet. The real balance on the
/// keypad, the current one and the difference under it; "Kaydet" moves the
/// opening balance by the difference, confirms, and says "Bakiye eşitlendi"
/// with "Geri al" — which puts the old opening balance back.
///
/// [context] is the account screen's: the snackbar outlives the sheet.
///
/// The balance is squared against what the server holds once every write
/// before it has landed: a delete still waiting out its "Geri al" window
/// is sent now (its snackbar goes — the undo could no longer be offered
/// once the balance has been squared around it), and "Kaydet" works from
/// the account as the server has it then, not as it was when the chip was
/// tapped.
Future<void> showReconcileSheet(
  BuildContext context,
  WidgetRef ref,
  Account account,
) {
  final l = context.l10n;
  final deletes = ref.read(deferredDeletesProvider.notifier);
  Future<void>? settling;
  if (deletes.hasWaiting) {
    settling = deletes.commitAll();
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }
  return showNokSheet<void>(
    context,
    title: l.reconcileTitle,
    showClose: true,
    builder: (_) => _ReconcileSheet(
      account: account,
      host: context,
      settling: settling,
    ),
  );
}

class _ReconcileSheet extends ConsumerStatefulWidget {
  final Account account;
  final BuildContext host;

  /// The deletes sent as the sheet opened, until the server has them.
  final Future<void>? settling;

  const _ReconcileSheet({
    required this.account,
    required this.host,
    this.settling,
  });

  @override
  ConsumerState<_ReconcileSheet> createState() => _ReconcileSheetState();
}

class _ReconcileSheetState extends ConsumerState<_ReconcileSheet> {
  AmountDraft _draft = const AmountDraft();
  late bool _debt = widget.account.balanceCents < 0;
  bool _atLimit = false;
  bool _saving = false;
  String? _error;

  /// Counts refused digits; each one shakes the amount once.
  int _refused = 0;

  /// The account as the account list has it now — a refetch while the
  /// sheet is open (a delete landing, a web edit) moves "Şu anki" with it.
  Account get _account {
    final accounts = ref.watch(accountsProvider).value?.data;
    for (final a in accounts ?? const <Account>[]) {
      if (a.id == widget.account.id) return a;
    }
    return widget.account;
  }
  int get _subunit => widget.account.subunitToUnit;

  int? get _actual {
    if (_draft.isEmpty) return null;
    final cents = _draft.minorUnits(_subunit);
    return _debt ? -cents : cents;
  }

  void _digit(String d) {
    final limit = _draft.wouldPassLimit(d, _subunit);
    if (limit) Haptics.reject();
    setState(() {
      _atLimit = limit;
      if (limit) _refused++;
      _draft = _draft.withDigit(d, _subunit);
      _error = null;
    });
  }

  Future<void> _save() async {
    final actual = _actual;
    if (actual == null || _saving) return;
    final l = context.l10n;
    final host = widget.host;
    final repo = ref.read(repositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    Account saved;
    int before;
    try {
      // The difference is taken from the balance the server has once the
      // deletes sent as the sheet opened have landed — never from the copy
      // the chip was tapped with.
      await widget.settling;
      final account = (await repo.fetchAccount(widget.account.id)).account;
      if (!mounted) return;
      if (actual == account.balanceCents) {
        Navigator.of(context).pop();
        return;
      }
      before = account.initialBalanceCents;
      saved = await repo.updateAccount(
        account,
        reconcileInput(account, reconciledInitialBalance(account, actual)),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      setState(() {
        _saving = false;
        _error = failureMessage(e, l, fallback: l.reconcileFailed);
      });
      return;
    }
    Haptics.confirm();
    if (mounted) Navigator.of(context).pop();
    if (!host.mounted) return;
    showAppSnack(
      host,
      l.reconcileDone,
      actionLabel: l.actionUndo,
      onAction: () async {
        try {
          await repo.updateAccount(saved, reconcileInput(saved, before));
        } catch (_) {
          if (host.mounted) {
            showAppSnack(host, l.reconcileUndoFailed, isError: true);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final account = _account;
    final actual = _actual;
    final now = formatMoney(
      account.balanceCents,
      account.currency,
      _subunit,
    );
    final difference = actual == null
        ? null
        : formatMoney(
            actual - account.balanceCents,
            account.currency,
            _subunit,
            sign: MoneySign.always,
          );
    final error = _error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          0,
          Insets.sheetH,
          Gap.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Everything above "Kaydet" scrolls when the keypad does not
            // fit (landscape, large text); the button stays in reach.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: RejectShake(
                        trigger: _refused,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _draft.display(account.currency, negative: _debt),
                            style: text.displayLarge!.copyWith(
                              color: _draft.isEmpty ? c.inkLow : c.inkHi,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      l.reconcileNowAndDifference(now, difference),
                      textAlign: TextAlign.center,
                      style: text.bodySmall!.copyWith(color: c.inkMid),
                    ),
                    if (_atLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.xs),
                        child: Text(
                          l.amountTooLarge(formatMoney(
                            AmountDraft.maxMinorUnits,
                            account.currency,
                            _subunit,
                          )),
                          textAlign: TextAlign.center,
                          style: text.bodySmall!.copyWith(color: c.warning),
                        ),
                      ),
                    const SizedBox(height: Gap.sm),
                    SwitchListTile.adaptive(
                      value: _debt,
                      onChanged: (v) {
                        Haptics.tick();
                        setState(() => _debt = v);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.accountFormDebt, style: text.titleSmall),
                    ),
                    AmountKeypad(
                      onDigit: _digit,
                      onDot: () => setState(
                          () => _draft = _draft.withDecimalMark(_subunit)),
                      onBackspace: () => setState(() {
                        _atLimit = false;
                        _draft = _draft.backspace();
                      }),
                      onClear: () => setState(() {
                        _atLimit = false;
                        _draft = const AmountDraft();
                      }),
                      showDecimal: decimalsFor(_subunit) > 0,
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: text.bodyMedium!.copyWith(color: c.error),
                  ),
                ),
              ),
            const SizedBox(height: Gap.md),
            PrimaryButton(
              label: l.actionSave,
              loading: _saving,
              onPressed: actual == null ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
