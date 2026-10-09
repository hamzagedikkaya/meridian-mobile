import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/slide_up_route.dart';
import 'account_form.dart';
import 'category_picker.dart';
import 'finance_utils.dart';

/// Pushes the full-screen İşlem Ekle/Düzenle modal on the root navigator via
/// the §5 400/300ms slide-up modal route. Resolves to the transaction as the
/// server saved it, or null when the form was closed without saving.
///
/// [initialAccountId] starts a new transaction on that account (an
/// account's own screen); otherwise it starts on the account the last one
/// was saved on, or the only one there is. [initialKind],
/// [initialAmountCents] (in the account currency's minor units) and
/// [initialDescription] fill a new one in (quick add, a shortcut).
Future<Transaction?> openTransactionForm(
  BuildContext context, {
  Transaction? existing,
  int? initialAccountId,
  String? initialKind,
  int? initialAmountCents,
  String? initialDescription,
}) {
  return Navigator.of(context, rootNavigator: true).push<Transaction>(
    slideUpModalRoute(
      (_) => TransactionFormScreen(
        existing: existing,
        initialAccountId: initialAccountId,
        initialKind: initialKind,
        initialAmountCents: initialAmountCents,
        initialDescription: initialDescription,
      ),
    ),
  );
}

/// A sentinel picker value: open the account form.
const _newAccount = -1;

class TransactionFormScreen extends ConsumerStatefulWidget {
  final Transaction? existing;
  final int? initialAccountId;

  /// A new transaction's kind (`expense`, `income`, `transfer`), amount in
  /// the account currency's minor units, and description; an edit ignores
  /// them.
  final String? initialKind;
  final int? initialAmountCents;
  final String? initialDescription;

  const TransactionFormScreen({
    super.key,
    this.existing,
    this.initialAccountId,
    this.initialKind,
    this.initialAmountCents,
    this.initialDescription,
  });

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late String _kind;
  AmountDraft _amount = const AmountDraft();

  /// The amount handed in ([TransactionFormScreen.initialAmountCents]), as
  /// first read — until the user types over it.
  AmountDraft? _prefilled;
  Account? _account;
  Account? _relatedAccount;

  /// Null is "Kategorisiz": an income or expense may have no category.
  TxCategory? _category;
  late DateTime _date;
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  bool _seeded = false;

  /// The last digit was refused: the amount would not fit the server.
  bool _atLimit = false;

  /// Where a refusal points, by field: amount, account, target, category,
  /// date; anything else goes under the form ([_error]).
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    final kind = widget.initialKind;
    _kind = ex?.kind ??
        (const {'expense', 'income', 'transfer'}.contains(kind)
            ? kind!
            : 'expense');
    final cents = widget.initialAmountCents;
    if (ex == null && cents != null && cents > 0) {
      // Read again in the account's currency once it is known (_seed).
      _amount = _prefilled = AmountDraft.fromMinorUnits(cents, _subunit);
    }
    // The account's today — the day the server files "today" under — not
    // necessarily this phone's date (see data/current_day.dart).
    _date = ex?.date ?? ref.read(currentDayProvider);
    _category = ex?.category;
    _descCtrl.text = ex?.description ?? widget.initialDescription ?? '';
    _noteCtrl.text = ex?.note ?? '';
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// The accounts a transaction can be put on: the active ones (not one
  /// that was just deleted and waits out its undo).
  List<Account> get _accounts => withoutDeleted(
        (ref.read(accountsProvider).value?.data ?? const <Account>[])
            .where((a) => !a.archived),
        ref.read(deferredDeletesProvider),
        DataScope.accounts,
        (a) => a.id,
      );

  /// Why the account row has no account: none picked, none at all yet — or
  /// the list itself, still loading or failed (never "make your first
  /// account" then: see [accountListProblem]).
  String _accountMissing(AppL10n l) =>
      accountListProblem(l, ref.read(accountsProvider)) ??
      (_accounts.isEmpty ? l.txFormNeedAccount : l.txFormSelectAccount);

  int get _subunit => _account?.subunitToUnit ?? 100;
  String get _currency => _account?.currency ?? 'TRY';
  int get _cents => _amount.minorUnits(_subunit);

  /// The account the last transaction was saved on, as stored on this
  /// device; null when none is (or the store is not there, as in tests).
  int? _lastAccountId() {
    try {
      return ref.read(sharedPrefsProvider).getInt(PrefKeys.lastAccountId);
    } catch (_) {
      return null;
    }
  }

  void _rememberAccount(int id) {
    try {
      ref.read(sharedPrefsProvider).setInt(PrefKeys.lastAccountId, id);
    } catch (_) {
      // No store (tests): nothing to remember with.
    }
  }

  /// Fills the account fields in once the accounts are known: an edit's
  /// own (archived ones too), else the one asked for, the last used, or the
  /// only one.
  void _seed() {
    if (_seeded) return;
    final accounts = ref.read(accountsProvider);
    final ex = widget.existing;
    // Wait for the accounts (an all-archived list is still a value). Should
    // they fail, an edit still fills in from what the transaction itself
    // says about its accounts; a new one waits for the reload a tap on the
    // account row starts, and is filled in when that lands.
    if (!accounts.hasValue && (ex == null || !accounts.hasError)) return;
    final all = accounts.value?.data ?? const <Account>[];
    Account? byId(int? id) {
      if (id == null) return null;
      for (final a in all) {
        if (a.id == id) return a;
      }
      return null;
    }

    if (ex != null) {
      _account = byId(ex.account.id) ?? _accountFromRef(ex.account);
      _relatedAccount = byId(ex.relatedAccount?.id) ??
          (ex.relatedAccount != null
              ? _accountFromRef(ex.relatedAccount!)
              : null);
      _amount = AmountDraft.fromMinorUnits(ex.amountCents, _subunit);
    } else {
      // Only an account the picker offers: an active one, and not one whose
      // delete waits out its undo — a transaction saved on it would make
      // that delete fail.
      final offered = _accounts;
      Account? usable(int? id) {
        for (final a in offered) {
          if (a.id == id) return a;
        }
        return null;
      }

      final picked = usable(widget.initialAccountId) ??
          usable(_lastAccountId()) ??
          (offered.length == 1 ? offered.single : null);
      if (picked != null) {
        final cents = widget.initialAmountCents;
        if (cents != null && cents > 0 && identical(_amount, _prefilled)) {
          // The amount handed in is in this account's minor units.
          _amount = AmountDraft.fromMinorUnits(cents, picked.subunitToUnit);
        } else if (picked.subunitToUnit != _subunit) {
          // An amount typed before the list came in is read in the
          // account's currency (gram gold has no decimals).
          _amount = _amount.forCurrency(picked.subunitToUnit);
        }
        _account = picked;
      }
    }
    _seeded = true;
  }

  /// An account the list does not have (deleted on the web meanwhile), as
  /// far as the transaction names it: the field is not blank, and the
  /// amount is read in its currency (GAU has no decimals).
  static Account _accountFromRef(AccountRef a) => Account(
        id: a.id,
        name: a.name,
        accountType: 'cash',
        currency: a.currency,
        subunitToUnit: a.subunitToUnit,
        color: a.color ?? '#B8860B',
        initialBalanceCents: 0,
        balanceCents: 0,
        archived: true,
      );

  // --- keypad handlers -------------------------------------------------------

  void _onDigit(String d) {
    final limit = _amount.wouldPassLimit(d, _subunit);
    setState(() {
      _atLimit = limit;
      _amount = _amount.withDigit(d, _subunit);
      _fieldErrors = const {};
    });
  }

  void _onDot() =>
      setState(() => _amount = _amount.withDecimalMark(_subunit));

  void _onBackspace() => setState(() {
        _atLimit = false;
        _amount = _amount.backspace();
      });

  // --- pickers ---------------------------------------------------------------

  /// A new account from the account form, picked for [related] or the
  /// source; false when the form was closed.
  Future<Account?> _createAccount() async {
    final created = await openAccountForm(context);
    if (created == null || !mounted) return null;
    return created;
  }

  void _useAccount(Account picked) {
    setState(() {
      final subunitChanged = picked.subunitToUnit != _subunit;
      _account = picked;
      if (subunitChanged) _amount = _amount.forCurrency(picked.subunitToUnit);
      // A transfer stays within one currency.
      final target = _relatedAccount;
      if (target != null &&
          (target.id == picked.id || !_sameCurrency(target, picked))) {
        _relatedAccount = null;
      }
      _fieldErrors = const {};
    });
  }

  static bool _sameCurrency(Account a, Account b) =>
      a.currency.toUpperCase() == b.currency.toUpperCase();

  Future<void> _pickAccount() async {
    final l = context.l10n;
    if (reloadAccountsIfMissing(ref)) return;
    final accounts = _accounts;
    if (accounts.isEmpty) {
      // Nothing to pick from: make one.
      final created = await _createAccount();
      if (created != null) _useAccount(created);
      return;
    }
    final id = await showPickerSheet<int>(
      context,
      title: l.txFormAccount,
      selected: _account?.id,
      options: [
        for (final a in accounts)
          PickerOption<int>(
            value: a.id,
            label: a.name,
            color: hexColor(a.color),
            trailing: formatMoney(a.balanceCents, a.currency, a.subunitToUnit),
          ),
        PickerOption<int>(
          value: _newAccount,
          label: l.accountNew,
          icon: Icons.add,
        ),
      ],
    );
    if (id == null || !mounted) return;
    if (id == _newAccount) {
      final created = await _createAccount();
      if (created != null) _useAccount(created);
      return;
    }
    _useAccount(accounts.firstWhere((a) => a.id == id));
  }

  Future<void> _pickTarget() async {
    final l = context.l10n;
    final source = _account;
    if (source == null) {
      setState(() => _fieldErrors = {'account': _accountMissing(l)});
      return;
    }
    if (reloadAccountsIfMissing(ref)) return;
    // Only another account in the same currency: the server credits the
    // target with the source's minor units as they are.
    final targets = [
      for (final a in _accounts)
        if (a.id != source.id && _sameCurrency(a, source)) a,
    ];
    final id = await showPickerSheet<int>(
      context,
      title: l.txFormTargetAccount,
      selected: _relatedAccount?.id,
      note: targets.isEmpty
          ? '${l.txFormNoTransferTarget}. ${l.txFormTransferSameCurrency}'
          : l.txFormTransferSameCurrency,
      options: [
        for (final a in targets)
          PickerOption<int>(
            value: a.id,
            label: a.name,
            color: hexColor(a.color),
            trailing: formatMoney(a.balanceCents, a.currency, a.subunitToUnit),
          ),
        PickerOption<int>(
          value: _newAccount,
          label: l.accountNew,
          icon: Icons.add,
        ),
      ],
    );
    if (id == null || !mounted) return;
    Account? picked;
    if (id == _newAccount) {
      picked = await _createAccount();
      if (picked == null) return;
      if (!_sameCurrency(picked, source) || picked.id == source.id) {
        setState(() => _fieldErrors = {'target': l.txFormTransferSameCurrency});
        return;
      }
    } else {
      picked = targets.firstWhere((a) => a.id == id);
    }
    setState(() {
      _relatedAccount = picked;
      _fieldErrors = const {};
    });
  }

  Future<void> _pickCategory() async {
    final l = context.l10n;
    final choice = await showCategoryPicker(
      context,
      title: l.txFormCategory,
      kind: _kind,
      selected: _category == null
          ? const NoCategory()
          : OneCategory(_category!),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _category = switch (choice) {
        OneCategory(:final category) => category,
        _ => null,
      };
      _fieldErrors = const {};
    });
  }

  Future<void> _pickDate() async {
    final first = DateTime(2015);
    final last = DateTime(2100);
    // A stored tx date outside the picker range would assert; clamp it in.
    final initial =
        _date.isBefore(first) ? first : (_date.isAfter(last) ? last : _date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  // --- submit ----------------------------------------------------------------

  /// What is wrong before the server is asked, by field.
  ///
  /// A transfer's two accounts must differ and share a currency — checked,
  /// as the server checks it, only when the kind or an account is new: an
  /// older transfer that breaks the rule stays editable (contract 4.3), so
  /// a new note or date on it is saved.
  Map<String, String> _validate(AppL10n l) {
    final account = _account;
    final target = _relatedAccount;
    final existing = widget.existing;
    final transferRules = existing == null ||
        existing.kind != _kind ||
        existing.account.id != account?.id ||
        existing.relatedAccount?.id != target?.id;
    return {
      if (_cents <= 0) 'amount': l.txFormEnterAmount,
      if (account == null) 'account': _accountMissing(l),
      if (_kind == 'transfer' && target == null)
        'target': l.txFormSelectTargetAccount,
      if (_kind == 'transfer' &&
          transferRules &&
          account != null &&
          target != null &&
          target.id == account.id)
        'target': l.txFormAccountsMustDiffer,
      if (_kind == 'transfer' &&
          transferRules &&
          account != null &&
          target != null &&
          target.id != account.id &&
          !_sameCurrency(account, target))
        'target': l.txFormTransferSameCurrency,
    };
  }

  String? _text(TextEditingController ctrl) {
    final value = ctrl.text.trim();
    return value.isEmpty ? null : value;
  }

  TransactionInput? _input() {
    final account = _account;
    if (account == null) return null;
    final transfer = _kind == 'transfer';
    return TransactionInput(
      kind: _kind,
      amountCents: _cents,
      date: _date,
      description: _text(_descCtrl),
      note: _text(_noteCtrl),
      accountId: account.id,
      financeCategoryId: transfer ? null : _category?.id,
      relatedAccountId: transfer ? _relatedAccount?.id : null,
    );
  }

  bool get _dirty {
    final existing = widget.existing;
    if (existing == null) {
      return !_amount.isEmpty ||
          _descCtrl.text.trim().isNotEmpty ||
          _noteCtrl.text.trim().isNotEmpty;
    }
    final input = _input();
    return input != null && input.changesFrom(existing).isNotEmpty;
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final problems = _validate(l);
    if (problems.isNotEmpty) {
      Haptics.danger();
      setState(() {
        _fieldErrors = problems;
        _error = null;
      });
      return;
    }
    final input = _input()!;
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      // Nothing changed: nothing to save.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      // The repository reports the write: feeds, balances, the dashboard,
      // budgets, Today and financial goals refresh from that — even when
      // this form is closed before the server answers.
      final repo = ref.read(repositoryProvider);
      final saved = existing != null
          ? await repo.updateTransaction(existing, input)
          : await repo.createTransaction(input);
      if (!mounted) return;
      if (existing == null) _rememberAccount(input.accountId);
      Haptics.success();
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      String? field(String key) => refusal?.fieldMessage(l, key);
      final placed = <String, String>{
        'amount': ?(field('amount_cents') ?? field('amount')),
        'account': ?(field('account') ?? field('account_id')),
        'target': ?field('related_account_id'),
        'category':
            ?(field('finance_category') ?? field('finance_category_id')),
        'date': ?field('date'),
      };
      setState(() {
        _saving = false;
        _fieldErrors = placed;
        _error = placed.isNotEmpty
            ? null
            : failureMessage(e, l, fallback: l.txSaveFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild once accounts arrive so seeding and the pickers have data; the
    // categories are fetched now so the picker opens with them.
    final accounts = ref.watch(accountsProvider);
    ref.watch(categoriesProvider);
    ref.watch(deferredDeletesProvider);
    // What a save said while the list was not here (loading, or failed) no
    // longer holds once it is: the row then shows the account filled in,
    // or that there is none to pick yet.
    ref.listen(accountsProvider, (previous, next) {
      if (next.hasValue &&
          !(previous?.hasValue ?? false) &&
          _fieldErrors.containsKey('account')) {
        setState(() => _fieldErrors = {..._fieldErrors}..remove('account'));
      }
    });
    _seed();
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final transfer = _kind == 'transfer';
    // The account list not here yet: loading, or failed (a tap on the row
    // loads it again) — never "make your first account".
    final accountsLoading = !accounts.hasValue && accounts.isLoading;
    final accountsFailed = !accounts.hasValue && !accounts.isLoading;
    final noAccounts = accounts.hasValue && _accounts.isEmpty;

    return FormScaffold(
      title: _isEdit ? l.txFormEditTitle : l.txFormNewTitle,
      actionLabel: _isEdit ? l.actionUpdate : l.actionSave,
      busy: _saving,
      dirty: _dirty,
      onAction: _submit,
      children: [
        Center(
          // One row whatever the text size: larger text scales the pill down
          // to the width there is instead of running off the screen.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _KindPill(
              kind: _kind,
              onChanged: (k) => setState(() {
                _kind = k;
                if (k == 'transfer') {
                  _category = null;
                } else if (_category != null && _category!.kind != k) {
                  _category = null;
                }
                _fieldErrors = const {};
              }),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: true,
          label: l.txFormAmount,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _amount.display(_currency),
              style: text.displayLarge!.copyWith(
                fontFeatures: tabularFigures,
                color: _amount.isEmpty ? c.inkLow : c.inkHi,
              ),
            ),
          ),
        ),
        if (_atLimit || _fieldErrors['amount'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _fieldErrors['amount'] ??
                  l.amountTooLarge(formatMoney(
                      AmountDraft.maxMinorUnits, _currency, _subunit)),
              textAlign: TextAlign.center,
              style: text.bodySmall!.copyWith(
                color: _fieldErrors['amount'] != null ? c.error : c.warning,
              ),
            ),
          ),
        const SizedBox(height: 8),
        AmountKeypad(
          onDigit: _onDigit,
          onDot: _onDot,
          onBackspace: _onBackspace,
          onClear: () => setState(() {
            _atLimit = false;
            _amount = const AmountDraft();
          }),
          showDecimal: decimalsFor(_subunit) > 0,
        ),
        const SizedBox(height: 16),
        FormPickerRow(
          icon: Icons.account_balance_wallet_outlined,
          label: l.txFormAccount,
          value: _account?.name ??
              (noAccounts
                  ? l.txFormNeedAccount
                  : (accountsLoading ? l.txFormAccountsLoading : null)),
          color: _account == null ? null : hexColor(_account!.color),
          busy: accountsLoading,
          onTap: _pickAccount,
          errorText: _fieldErrors['account'] ??
              (accountsFailed ? l.txFormAccountsFailed : null),
        ),
        const SizedBox(height: 8),
        if (transfer)
          FormPickerRow(
            icon: Icons.swap_horiz,
            label: l.txFormTargetAccount,
            value: _relatedAccount?.name,
            color: _relatedAccount == null
                ? null
                : hexColor(_relatedAccount!.color),
            busy: accountsLoading,
            onTap: _pickTarget,
            errorText: _fieldErrors['target'],
          )
        else
          FormPickerRow(
            icon: Icons.category_outlined,
            label: l.txFormCategory,
            value: _category?.name ?? l.financeUncategorized,
            color: _category == null ? null : hexColor(_category!.color),
            onTap: _pickCategory,
            errorText: _fieldErrors['category'],
          ),
        const SizedBox(height: 8),
        FormPickerRow(
          icon: Icons.calendar_today_outlined,
          label: l.txFormDate,
          value: l.relativeDay(_date),
          onTap: _pickDate,
          errorText: _fieldErrors['date'],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l.txFormDescription),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '${l.txFormNote} (${l.labelOptional})',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: text.bodySmall!.copyWith(color: c.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _KindPill extends StatelessWidget {
  final String kind;
  final ValueChanged<String> onChanged;
  const _KindPill({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final options = [
      ('expense', l.financeExpense),
      ('income', l.financeIncome),
      ('transfer', l.financeTransfer),
    ];
    void select(String value) {
      if (value == kind) return;
      Haptics.tick();
      onChanged(value);
    }

    return Container(
      // No vertical padding: each segment's 48 dp target (design-research
      // §6.2) fills the pill's height, and its 40 dp highlight sits inside.
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            // One stop per segment for a screen reader, saying which one is
            // chosen. Its detector is left out of the tree, so this node
            // answers the double-tap itself (the chosen one has nothing to
            // do).
            Semantics(
              button: true,
              selected: value == kind,
              label: label,
              onTap: value == kind ? null : () => select(value),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => select(value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      constraints: const BoxConstraints(minHeight: 40),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: value == kind
                            ? c.goldContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: text.labelLarge!.copyWith(
                          color: value == kind ? c.onGoldContainer : c.inkMid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
