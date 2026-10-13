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
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rolling_number.dart';
import '../../widgets/segmented_pill.dart';
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

/// The transaction form, laid out bottom-up (design-analysis §7.7, IA-10):
/// what the thumb does most sits lowest, right above "Kaydet".
///
/// From the top: the kind (Gider · Gelir · Transfer); the amount in the
/// account's currency, rolling in as it is typed; a row of chips for the
/// account, the day and the description; the keypad; the six categories
/// of the kind used most lately and "Tümü…" (a transfer has its two
/// accounts there instead, as cards that say each balance after it); then
/// "Kaydet". With the keyboard down nothing scrolls: an expense on the
/// usual account is digits, one chip and "Kaydet".
///
/// "Açıklama" swaps the keypad for the description (and, under "Daha
/// fazla", the note) — the keyboard comes up and "Kaydet" rides on it; a tap
/// on the amount brings the keypad back.
///
/// An edit opens filled in and sends only what changed.
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

  /// How many categories the chip row offers before "Tümü…".
  static const categoryChips = 6;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

/// The amount as typed, and what the keypad last refused.
@immutable
class _Amount {
  final AmountDraft draft;

  /// The last digit was refused: the amount would not fit the server.
  final bool atLimit;

  /// How many digits were refused so far: each one shakes the amount.
  final int refusals;

  const _Amount([
    this.draft = const AmountDraft(),
    this.atLimit = false,
    this.refusals = 0,
  ]);
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late String _kind;

  /// The amount lives outside the form's state: a key press rebuilds the
  /// amount (and a transfer's "sonra" lines), nothing else.
  final _amount = ValueNotifier(const _Amount());

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

  /// A new transaction's answer was lost (a send or receive timeout): the
  /// server may have saved it — POST /transactions is not safe to repeat
  /// (contract §1.8). "Kaydet" waits until the account list this was
  /// noted against has been refetched (the write reported itself, so the
  /// balances reload), and the form says to check first.
  Fetched<List<Account>>? _unsureOver;
  bool _seeded = false;

  /// The keypad has made way for the description (and the note).
  bool _textMode = false;

  /// The note is open under the description.
  bool _moreOpen = false;

  /// Whether the form counted as changed when it was last built — the
  /// amount changes without a rebuild, so its listener rebuilds when this
  /// no longer holds.
  bool _builtDirty = false;

  /// [build] is running: what it changes it also shows.
  bool _building = false;

  /// The latest transactions the app had on hand when the form opened:
  /// what the category chips are ranked by.
  List<Transaction> _recent = const [];

  /// Where a refusal points, by field: amount, account, target, category,
  /// date; anything else goes under the form ([_error]).
  Map<String, String> _fieldErrors = const {};
  String? _error;

  bool get _isEdit => widget.existing != null;

  AmountDraft get _draft => _amount.value.draft;

  set _draft(AmountDraft draft) =>
      _amount.value = _Amount(draft, false, _amount.value.refusals);

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
      _draft = _prefilled = AmountDraft.fromMinorUnits(cents, _subunit);
    }
    // The account's today — the day the server files "today" under — not
    // necessarily this phone's date (see data/current_day.dart).
    _date = ex?.date ?? ref.read(currentDayProvider);
    _category = ex?.category;
    _descCtrl.text = ex?.description ?? widget.initialDescription ?? '';
    _noteCtrl.text = ex?.note ?? '';
    _moreOpen = _noteCtrl.text.trim().isNotEmpty;
    _recent = loadedRecentTransactions(
      ProviderScope.containerOf(context, listen: false),
    );
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount
      ..removeListener(_onAmountChanged)
      ..dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// The amount changed: rebuild the form only when that changes whether
  /// leaving it asks first, or clears what a save said about the amount.
  void _onAmountChanged() {
    // Filled in while building (_seed): the build that runs reads it.
    if (!mounted || _building) return;
    if (_dirty != _builtDirty || _fieldErrors.containsKey('amount')) {
      setState(() {
        if (_fieldErrors.containsKey('amount')) {
          _fieldErrors = {..._fieldErrors}..remove('amount');
        }
      });
    }
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
  int get _cents => _draft.minorUnits(_subunit);

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
    // account chip starts, and is filled in when that lands.
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
      _draft = AmountDraft.fromMinorUnits(ex.amountCents, _subunit);
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

      // The account asked for, else the user's default, else the last one
      // used — the first of them still offered.
      Account? preferred() {
        for (final id in preferredAccountIds(ref)) {
          final a = usable(id);
          if (a != null) return a;
        }
        return null;
      }

      final picked = usable(widget.initialAccountId) ??
          preferred() ??
          (offered.length == 1 ? offered.single : null);
      if (picked != null) {
        final cents = widget.initialAmountCents;
        if (cents != null && cents > 0 && identical(_draft, _prefilled)) {
          // The amount handed in is in this account's minor units.
          _draft = AmountDraft.fromMinorUnits(cents, picked.subunitToUnit);
        } else if (picked.subunitToUnit != _subunit) {
          // An amount typed before the list came in is read in the
          // account's currency (gram gold has no decimals).
          _draft = _draft.forCurrency(picked.subunitToUnit);
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
    final now = _amount.value;
    if (now.draft.wouldPassLimit(d, _subunit)) {
      // Refused: the amount shakes and says where it stops (§4.11).
      Haptics.reject();
      _amount.value = _Amount(now.draft, true, now.refusals + 1);
      return;
    }
    _amount.value = _Amount(now.draft.withDigit(d, _subunit), false,
        now.refusals);
  }

  void _onDot() => _draft = _draft.withDecimalMark(_subunit);

  void _onBackspace() => _draft = _draft.backspace();

  void _onClear() => _draft = const AmountDraft();

  // --- text mode -------------------------------------------------------------

  void _enterTextMode() => setState(() => _textMode = true);

  void _leaveTextMode() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _textMode = false);
  }

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
      if (subunitChanged) _draft = _draft.forCurrency(picked.subunitToUnit);
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
      title: _kind == 'transfer' ? l.txFormSource : l.txFormAccount,
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
          icon: Icons.add_rounded,
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
          icon: Icons.add_rounded,
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

  /// The transfer's two accounts trade places.
  void _swapAccounts() {
    final source = _account;
    final target = _relatedAccount;
    if (source == null || target == null) return;
    Haptics.tick();
    setState(() {
      _account = target;
      _relatedAccount = source;
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

  /// A category chip: picks it — or, tapped again, leaves the transaction
  /// without one.
  void _toggleCategory(TxCategory category) {
    setState(() {
      _category = _category?.id == category.id ? null : category;
      _fieldErrors = const {};
    });
  }

  /// The day: today, yesterday, or one from the calendar.
  Future<void> _pickDate() async {
    final l = context.l10n;
    final today = ref.read(currentDayProvider);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final key = await showPickerSheet<String>(
      context,
      title: l.txFormDate,
      selected: same(_date, today)
          ? 'today'
          : (same(_date, yesterday) ? 'yesterday' : 'pick'),
      options: [
        PickerOption(
            value: 'today', label: l.dayToday, icon: Icons.today_rounded),
        PickerOption(
            value: 'yesterday',
            label: l.dayYesterday,
            icon: Icons.history_rounded),
        PickerOption(
            value: 'pick',
            label: l.txFormPickDate,
            icon: Icons.calendar_month_rounded),
      ],
    );
    if (key == null || !mounted) return;
    if (key != 'pick') {
      setState(() {
        _date = key == 'today' ? today : yesterday;
        _fieldErrors = const {};
      });
      return;
    }
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
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      if (kind == 'transfer') {
        _category = null;
      } else if (_category != null && _category!.kind != kind) {
        _category = null;
      }
      _fieldErrors = const {};
    });
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
      return !_draft.isEmpty ||
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
      Haptics.reject();
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
      Haptics.confirm();
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
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
      final maybe = existing == null &&
          refusal != null &&
          refusal.isNetwork &&
          refusal.mayHaveArrived;
      setState(() {
        _saving = false;
        _fieldErrors = placed;
        if (maybe) _unsureOver = ref.read(accountsProvider).value;
        _error = placed.isNotEmpty
            ? null
            : (maybe
                ? l.txSaveMaybe
                : failureMessage(e, l, fallback: l.txSaveFailed));
      });
    }
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Rebuild once accounts arrive so seeding and the pickers have data; the
    // categories are fetched now so the chips and the picker have them.
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider).value?.data ??
        const <TxCategory>[];
    ref.watch(deferredDeletesProvider);
    // What a save said while the list was not here (loading, or failed) no
    // longer holds once it is: the chip then shows the account filled in,
    // or that there is none to pick yet.
    ref.listen(accountsProvider, (previous, next) {
      if (next.hasValue &&
          !(previous?.hasValue ?? false) &&
          _fieldErrors.containsKey('account')) {
        setState(() => _fieldErrors = {..._fieldErrors}..remove('account'));
      }
    });
    _building = true;
    try {
      _seed();
    } finally {
      _building = false;
    }
    final l = context.l10n;
    final transfer = _kind == 'transfer';
    // The account list not here yet: loading, or failed (a tap on the chip
    // loads it again) — never "make your first account".
    final accountsLoading = !accounts.hasValue && accounts.isLoading;
    final accountsFailed = !accounts.hasValue && !accounts.isLoading;
    final noAccounts = accounts.hasValue && _accounts.isEmpty;
    final dirty = _builtDirty = _dirty;
    final accountError = _fieldErrors['account'] ??
        (accountsFailed ? l.txFormAccountsFailed : null);
    final reduced = Motion.reduced(context);

    // The chip rows run from edge to edge; everything else keeps the
    // form's 20 dp sides.
    Widget side(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.formH),
          child: child,
        );
    // The kind on top; everything the thumb works with gathers above
    // "Kaydet": the amount, its chips, the keypad and the categories.
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.sm),
        Center(
          // One row whatever the text size: larger text scales the pill
          // down to the width there is, so every kind stays in reach.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedPill<String>(
              options: [
                ('expense', l.financeExpense),
                ('income', l.financeIncome),
                ('transfer', l.financeTransfer),
              ],
              selected: _kind,
              onChanged: _setKind,
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
      ],
    );

    // The category chips — or a transfer's two accounts — change places in
    // 150 ms, and the height follows (§7.7).
    final lowerSwitch = AnimatedSwitcher(
      duration: Motion.orInstant(context, Motion.pressOut),
      child: transfer
          ? KeyedSubtree(
              key: const ValueKey('accounts'),
              child: side(_transferCards(context, accountError: accountError)),
            )
          : KeyedSubtree(
              key: ValueKey('categories-$_kind'),
              child: _categoryChips(context, categories),
            ),
    );
    final bottom = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        side(_amountView(context)),
        _metaChips(
          context,
          accountsLoading: accountsLoading,
          noAccounts: noAccounts,
          accountError: accountError,
        ),
        side(FormInlineError(
          transfer
              ? _fieldErrors['date']
              : (accountError ?? _fieldErrors['date']),
          gap: 0,
        )),
        const SizedBox(height: Gap.sm),
        side(_textMode
            ? _textFields(context)
            : AmountKeypad(
                onDigit: _onDigit,
                onDot: _onDot,
                onBackspace: _onBackspace,
                onClear: _onClear,
                showDecimal: decimalsFor(_subunit) > 0,
              )),
        const SizedBox(height: Gap.sm),
        if (reduced)
          lowerSwitch
        else
          AnimatedSize(
            duration: Motion.pressOut,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: lowerSwitch,
          ),
        side(FormInlineError(
          transfer
              // The source's error (none picked, the list not loaded, what
              // the server said of it) and the target's, as they come.
              ? _joined([accountError, _fieldErrors['target']])
              : _fieldErrors['category'],
          gap: 0,
        )),
        const SizedBox(height: Gap.xs),
      ],
    );

    return _BottomUpFormFrame(
      title: _isEdit ? l.txFormEditTitle : l.txFormNewTitle,
      actionLabel: _isEdit ? l.actionUpdate : l.actionSave,
      busy: _saving,
      dirty: dirty,
      // Held while a lost answer may still turn out to have been saved.
      onAction: _unsureOver != null && identical(accounts.value, _unsureOver)
          ? null
          : _submit,
      errorText: _error,
      top: top,
      bottom: bottom,
    );
  }

  /// [messages] that are there, one per line — or null for none.
  static String? _joined(List<String?> messages) {
    final present = messages.nonNulls;
    return present.isEmpty ? null : present.join('\n');
  }

  /// The amount, big, in the account's currency — "₺0" in inkLow until a
  /// digit is typed — and under it the line kept free for what the keypad
  /// refused or a save said about the amount. Only this rebuilds on a key.
  Widget _amountView(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return ValueListenableBuilder<_Amount>(
      valueListenable: _amount,
      builder: (context, amount, _) {
        final empty = amount.draft.isEmpty;
        final shown = amount.draft.display(_currency);
        final error = _fieldErrors['amount'];
        final note = error ??
            (amount.atLimit
                ? l.amountTooLarge(formatMoney(
                    AmountDraft.maxMinorUnits, _currency, _subunit))
                : null);
        final number = Semantics(
          label: l.txFormAmount,
          value: shown,
          liveRegion: true,
          button: _textMode,
          hint: _textMode ? l.txFormEditAmount : null,
          onTap: _textMode ? _leaveTextMode : null,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _textMode ? _leaveTextMode : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Center(
                child: RejectShake(
                  trigger: amount.refusals,
                  // Its rolling frames repaint the amount alone (§5.10).
                  child: RepaintBoundary(
                    child: RollingNumber(
                      text: shown,
                      cause: NumberCause.typing,
                      fractionScale: 1,
                      semanticsLabel: shown,
                      style: text.displayLarge!.copyWith(
                        color: empty ? c.inkLow : c.inkHi,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            number,
            // Kept free (§4.11): the note never pushes the keypad down.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 18),
              child: note == null
                  ? null
                  : Semantics(
                      liveRegion: true,
                      child: Text(
                        note,
                        textAlign: TextAlign.center,
                        style: text.bodySmall!.copyWith(
                          color: error != null ? c.error : c.warning,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// [Hesap: Cüzdan ▾] [Bugün ▾] [+ Açıklama], sideways if they run long. A
  /// transfer names its accounts in its cards instead.
  Widget _metaChips(
    BuildContext context, {
    required bool accountsLoading,
    required bool noAccounts,
    required String? accountError,
  }) {
    final l = context.l10n;
    final account = _account;
    final description = _descCtrl.text.trim();
    final accountLabel = account != null
        ? l.txFormAccountChip(account.name)
        : (noAccounts
            ? l.txFormNeedAccount
            : (accountsLoading ? l.txFormAccountsLoading : l.txFormAccount));
    return _ChipRow(
      children: [
        if (_kind != 'transfer')
          NokChip(
            label: accountLabel,
            dot: account == null ? null : hexColor(account.color),
            icon: account == null
                ? Icons.account_balance_wallet_outlined
                : null,
            dropdown: true,
            onTap: _pickAccount,
          ),
        // Screen readers hear which field a chip is: "Tarih, Bugün".
        Semantics(
          label: l.txFormDate,
          child: NokChip(
            label: l.relativeDay(_date),
            dropdown: true,
            onTap: _pickDate,
          ),
        ),
        if (description.isEmpty)
          NokChip(
            label: l.txFormAddDescription,
            icon: Icons.add_rounded,
            selected: _textMode,
            onTap: _textMode ? _leaveTextMode : _enterTextMode,
          )
        else
          Semantics(
            label: l.txFormDescription,
            child: NokChip(
              label: description,
              icon: Icons.notes_rounded,
              selected: _textMode,
              onTap: _textMode ? _leaveTextMode : _enterTextMode,
            ),
          ),
      ],
    );
  }

  /// The six categories of this kind used most lately, and "Tümü…" for the
  /// rest (and a new one). One not among them that the transaction has
  /// comes first, so the choice always shows.
  Widget _categoryChips(BuildContext context, List<TxCategory> all) {
    final l = context.l10n;
    final selected = _category;
    final frequent = frequentCategories(
      recent: _recent,
      categories: all,
      kind: _kind,
      count: TransactionFormScreen.categoryChips,
    );
    final shown = [
      if (selected != null && !frequent.any((c) => c.id == selected.id))
        selected,
      ...frequent,
    ];
    // All of them in sight — on two lines if need be — so any of the six
    // is one tap, never a swipe away (§7.7).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.formH),
      child: Wrap(
        spacing: Gap.sm,
        children: [
          for (final category in shown)
            NokChip(
              label: category.name,
              dot: hexColor(category.color),
              selected: category.id == selected?.id,
              exclusive: true,
              onTap: () => _toggleCategory(category),
            ),
          NokChip(
            label: l.txFormAllCategories,
            icon: Icons.category_outlined,
            onTap: _pickCategory,
          ),
        ],
      ),
    );
  }

  /// A transfer's two accounts, source over target, each with its balance
  /// and what it will be after this transfer; the swap button beside them.
  Widget _transferCards(BuildContext context, {String? accountError}) {
    final l = context.l10n;
    final source = _account;
    final target = _relatedAccount;
    final existing = widget.existing;
    // What the edited transaction already did to [a] is in its balance —
    // whatever role [a] had in it: taken out before this transfer's own
    // effect goes in.
    int already(Account a) {
      if (existing == null) return 0;
      final amount = existing.amountCents;
      if (existing.account.id == a.id) {
        return existing.kind == 'income' ? amount : -amount;
      }
      if (existing.kind == 'transfer' && existing.relatedAccount?.id == a.id) {
        return amount;
      }
      return 0;
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccountCard(
                role: l.txFormSource,
                account: source,
                placeholder: _accountMissingLabel(l),
                after: source == null
                    ? null
                    : (cents) =>
                        source.balanceCents - already(source) - cents,
                amount: _amount,
                subunit: _subunit,
                error: accountError,
                onTap: _pickAccount,
              ),
              const SizedBox(height: Gap.sm),
              _AccountCard(
                role: l.txFormTarget,
                account: target,
                placeholder: l.txFormSelectTargetAccount,
                after: target == null
                    ? null
                    : (cents) =>
                        target.balanceCents - already(target) + cents,
                amount: _amount,
                subunit: _subunit,
                error: _fieldErrors['target'],
                onTap: _pickTarget,
              ),
            ],
          ),
        ),
        const SizedBox(width: Gap.xs),
        IconButton(
          onPressed: source != null && target != null ? _swapAccounts : null,
          tooltip: l.txFormSwap,
          icon: const Icon(Icons.swap_vert_rounded),
        ),
      ],
    );
  }

  String _accountMissingLabel(AppL10n l) {
    final accounts = ref.read(accountsProvider);
    if (!accounts.hasValue && accounts.isLoading) {
      return l.txFormAccountsLoading;
    }
    if (accounts.hasValue && _accounts.isEmpty) return l.txFormNeedAccount;
    return l.txFormAccount;
  }

  /// In place of the keypad: the description, focused, and under "Daha
  /// fazla" the note.
  Widget _textFields(BuildContext context) {
    final l = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _descCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction:
              _moreOpen ? TextInputAction.next : TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l.txFormDescription),
        ),
        if (_moreOpen) ...[
          const SizedBox(height: Gap.md),
          TextField(
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '${l.txFormNote} (${l.labelOptional})',
            ),
          ),
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _moreOpen = true),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(l.txFormMore),
            ),
          ),
      ],
    );
  }
}

/// Chips in one row from edge to edge, 20 dp in at either end, that
/// scrolls sideways when they run past the screen — its last 24 dp then
/// fade out, so it shows there is more (as İşlemler's filter row does).
class _ChipRow extends StatefulWidget {
  final List<Widget> children;

  const _ChipRow({required this.children});

  @override
  State<_ChipRow> createState() => _ChipRowState();
}

class _ChipRowState extends State<_ChipRow> {
  bool _more = false;

  bool _onMetrics(ScrollMetricsNotification n) {
    final more = n.metrics.extentAfter > 0.5;
    if (more != _more) {
      // Reported during layout: change the fade on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && more != _more) setState(() => _more = more);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    Widget row = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.formH),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: Gap.sm),
              children[i],
            ],
          ],
        ),
      ),
    );
    if (_more) {
      row = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, rect.width <= 24 ? 0 : 1 - 24 / rect.width, 1],
        ).createShader(rect),
        child: row,
      );
    }
    return row;
  }
}

/// One account of a transfer, at least 48 dp: its role ("Kaynak",
/// "Hedef") over its name, its colour and balance, and, once there is an
/// amount, the balance after this transfer ("sonra: ₺2.750"). [after] turns
/// the amount into that balance; only that line rebuilds as the amount is
/// typed. A money amount never ends in "…" (§8.3): at large text sizes the
/// balance moves under the name and both amounts wrap. [error] reddens the
/// edge and is read with the card.
class _AccountCard extends StatelessWidget {
  final String role;
  final Account? account;
  final String placeholder;
  final int Function(int cents)? after;
  final ValueNotifier<_Amount> amount;
  final int subunit;
  final String? error;
  final VoidCallback onTap;

  const _AccountCard({
    required this.role,
    required this.account,
    required this.placeholder,
    required this.after,
    required this.amount,
    required this.subunit,
    required this.error,
    required this.onTap,
  });

  /// From this text scale on, the balance goes under the name.
  static const stackedFrom = 1.3;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final account = this.account;
    final after = this.after;
    final stacked =
        MediaQuery.textScalerOf(context).scale(10) / 10 >= stackedFrom;
    String money(int cents) => account == null
        ? ''
        : formatMoney(cents, account.currency, account.subunitToUnit,
            decimals: MoneyDecimals.auto);
    final caption = ExcludeSemantics(
      child: Text(
        role,
        style: text.labelSmall!.copyWith(color: c.inkMid),
      ),
    );
    final name = Text(
      account?.name ?? placeholder,
      maxLines: stacked ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: text.titleSmall!.copyWith(
        color: account == null ? c.inkLow : c.inkHi,
      ),
    );
    final balance = account == null
        ? null
        : Text(
            money(account.balanceCents),
            style: context.nokText.numMeta.copyWith(color: c.inkMid),
          );
    final afterLine = after == null || account == null
        ? null
        : ValueListenableBuilder<_Amount>(
            valueListenable: amount,
            builder: (context, a, _) {
              final cents = a.draft.minorUnits(subunit);
              if (cents <= 0) return const SizedBox.shrink();
              return Text(
                l.txFormBalanceAfter(money(after(cents))),
                style: text.bodySmall!.copyWith(
                  color: c.inkMid,
                  fontFeatures: tabularFigures,
                ),
              );
            },
          );
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: account == null ? c.inkDisabled : hexColor(account.color),
        shape: BoxShape.circle,
      ),
    );
    final arrow =
        Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: c.inkLow);
    final Widget content;
    if (stacked) {
      content = Row(
        children: [
          dot,
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption, name, ?balance, ?afterLine],
            ),
          ),
          const SizedBox(width: Gap.xs),
          arrow,
        ],
      );
    } else {
      content = Row(
        children: [
          dot,
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [caption, name, ?afterLine],
            ),
          ),
          if (balance != null) ...[
            const SizedBox(width: Gap.sm),
            balance,
          ],
          const SizedBox(width: Gap.xs),
          arrow,
        ],
      );
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: role,
        hint: error,
        child: Material(
          color: c.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.mdAll,
            side: BorderSide(color: error != null ? c.error : c.inkDisabled),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.xs,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The form's frame (design-analysis §4.31, §7.7): the X and the title on
/// top, "Kaydet" pinned at the bottom — right above the keyboard when it
/// is up — and between them [top] at the top and [bottom] right above the
/// button, the space left over between the two. With the keyboard down
/// the body fits a 360×780 phone and does not scroll; when it does not fit
/// (large text, the keyboard up) it scrolls, and a hairline shows over the
/// button while content runs under it.
///
/// Leaving while [dirty] asks first, as `FormScaffold` does (whose body
/// always scrolls from the top, which is why this form keeps its own).
class _BottomUpFormFrame extends StatefulWidget {
  final String title;
  final String actionLabel;
  final bool busy;
  final bool dirty;
  final VoidCallback? onAction;
  final String? errorText;
  final Widget top;
  final Widget bottom;

  const _BottomUpFormFrame({
    required this.title,
    required this.actionLabel,
    required this.busy,
    required this.dirty,
    required this.onAction,
    required this.errorText,
    required this.top,
    required this.bottom,
  });

  @override
  State<_BottomUpFormFrame> createState() => _BottomUpFormFrameState();
}

class _BottomUpFormFrameState extends State<_BottomUpFormFrame> {
  /// Content runs on under the save bar.
  bool _underBar = false;

  Future<void> _close() async {
    if (!widget.dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) _track(n.metrics);
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0) _track(n.metrics);
    return false;
  }

  void _track(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return;
    final under = m.extentAfter > 0.5;
    if (under != _underBar) setState(() => _underBar = under);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    return PopScope<Object?>(
      canPop: !widget.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: l.actionClose,
            onPressed: _close,
          ),
          title: Text(widget.title),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onMetrics,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          // At least as tall as the screen allows: the
                          // space left goes between top and bottom, so the
                          // keypad sits in the thumb's reach.
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [widget.top, widget.bottom],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: Motion.orInstant(context, Motion.pressOut),
                height: 1,
                color: _underBar ? c.hairline : c.hairline.withValues(alpha: 0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.formH,
                  Gap.sm,
                  Insets.formH,
                  Gap.md,
                ),
                child: PrimaryButton(
                  label: widget.actionLabel,
                  loading: widget.busy,
                  onPressed: widget.onAction,
                  errorText: widget.errorText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
