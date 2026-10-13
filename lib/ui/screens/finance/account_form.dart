import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/currency.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/slide_up_route.dart';
import 'finance_utils.dart';

/// The longest account name the server takes.
const accountNameMaxLength = 60;

/// Opens the account form — a new account, or [existing] to edit — as a
/// full-screen modal. Resolves to the account as the server saved it, or
/// null when the form was closed without saving.
///
/// Every place that needs an account opens this one form: Finance (its
/// first-run card, the "+" by the accounts, the carousel's last card), an
/// account's own screen, the transaction and goal forms' account pickers,
/// and quick capture's "no account" answer.
Future<Account?> openAccountForm(BuildContext context, {Account? existing}) {
  return Navigator.of(context, rootNavigator: true).push<Account>(
    slideUpModalRoute((_) => AccountFormScreen(existing: existing)),
  );
}

/// What a form's account row says while the account list is not here: that
/// it is loading, or that it could not be loaded (a tap tries again) — null
/// once it is here.
///
/// Until then, "no accounts yet" is never concluded from an empty list: the
/// row offers no first account, which a temporary failure would otherwise
/// turn into a duplicate.
String? accountListProblem(AppL10n l, AsyncValue<Object?> accounts) {
  if (accounts.hasValue) return null;
  return accounts.isLoading ? l.txFormAccountsLoading : l.txFormAccountsFailed;
}

/// A tap on a form's account row before the account list is here: loads it
/// again when it failed (a load still running is left to finish). True
/// while the list is not here — the tap then opens nothing (see
/// [accountListProblem]).
bool reloadAccountsIfMissing(WidgetRef ref) {
  final accounts = ref.read(accountsProvider);
  if (accounts.hasValue) return false;
  if (!accounts.isLoading) {
    ref.read(dataSyncProvider).refresh([accountsProvider]);
  }
  return true;
}

class AccountFormScreen extends ConsumerStatefulWidget {
  final Account? existing;

  const AccountFormScreen({super.key, this.existing});

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  late String _type = widget.existing?.accountType ?? accountTypes.first;
  late final _name = TextEditingController(text: widget.existing?.name);

  /// The name the type filled in, while the user has not typed one: picking
  /// another type renames it ("Nakit" → "Banka").
  String? _suggestedName;

  /// Null until the currency list says which one a new account starts in.
  late String? _currency = widget.existing?.currency;
  late int _balance = widget.existing?.initialBalanceCents ?? 0;
  String? _color;

  /// "Varsayılan hesap": new transactions start on it (on this device).
  /// Null until the user flips it: then it is what the device says.
  bool? _isDefault;

  bool _saving = false;

  /// A new account's answer was lost: the account list as it was then.
  /// "Kaydet" waits until a newer one is in (see [_save]).
  Fetched<List<Account>>? _unsureOver;
  String? _nameError;
  String? _currencyError;
  String? _balanceError;
  String? _formError;

  /// The server refused a currency change (`currency_locked`: something was
  /// recorded on the account since this form learnt its currency could
  /// change). The currency is locked here from then on, whatever the
  /// account's detail says — before its refetch lands, or should that fail.
  bool _currencyRefused = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A new account is named after its type until the user names it.
    _suggestName(context.l10n);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_nameError != null) setState(() => _nameError = null);
  }

  void _setType(String type) {
    setState(() => _type = type);
    _suggestName(context.l10n);
  }

  /// Fills the name in from the type, unless the user wrote one.
  void _suggestName(AppL10n l) {
    if (_isEdit) return;
    final current = _name.text.trim();
    if (current.isNotEmpty && current != _suggestedName) return;
    final suggestion = l.accountType(_type);
    _suggestedName = suggestion;
    if (_name.text != suggestion) {
      _name.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
    }
  }

  /// The currencies to offer: the server's list, or — while it cannot be
  /// had — the ones it always offers, plus this account's own.
  List<CurrencyOption> _options(CurrenciesBundle? bundle) {
    final list = [...?bundle?.currencies];
    if (list.isEmpty) list.addAll(CurrencyOption.offered);
    final own = widget.existing?.currency.toUpperCase();
    if (own != null && !list.any((c) => c.code == own)) {
      list.add(CurrencyOption(
        code: own,
        name: own,
        symbol: own,
        subunitToUnit: widget.existing!.subunitToUnit,
      ));
    }
    return list;
  }

  int _subunitOf(String? code, List<CurrencyOption> options) {
    for (final option in options) {
      if (option.code == code) return option.subunitToUnit;
    }
    return widget.existing?.subunitToUnit ?? 100;
  }

  /// A new currency keeps the typed opening balance as typed — 1.250,50
  /// stays 1.250,50, or 1.250 in a currency without decimals. [current] is
  /// the currency shown until now.
  void _setCurrency(
    String code,
    String current,
    List<CurrencyOption> options,
  ) {
    final before = _subunitOf(current, options);
    final after = _subunitOf(code, options);
    final draft = AmountDraft.fromMinorUnits(_balance, before).forCurrency(after);
    final converted = draft.minorUnits(after);
    setState(() {
      _currency = code;
      _currencyError = null;
      _balance = _balance < 0 ? -converted : converted;
    });
  }

  AccountInput _input(String currency, String color) => AccountInput(
        name: _name.text.trim(),
        accountType: _type,
        currency: currency,
        initialBalanceCents: _balance,
        color: color,
      );

  bool _dirty(String currency, String color) {
    final existing = widget.existing;
    if (existing == null) {
      final name = _name.text.trim();
      return (name.isNotEmpty && name != _suggestedName) || _balance != 0;
    }
    return _input(currency, color).changesFrom(existing).isNotEmpty ||
        (_isDefault != null && _isDefault != _wasDefault());
  }

  /// Whether the account is the device's default now.
  bool _wasDefault() {
    final existing = widget.existing;
    return existing != null && defaultAccountId(ref) == existing.id;
  }

  /// Remembers the "Varsayılan hesap" switch for [id], when it was flipped.
  void _applyDefault(int id) {
    final wanted = _isDefault;
    if (wanted == null || wanted == _wasDefault()) return;
    setDefaultAccountId(ref, wanted ? id : null, unless: id);
  }

  Future<void> _save(String currency, String color) async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      Haptics.reject();
      setState(() => _nameError = l.accountFormNameRequired);
      return;
    }
    final input = _input(currency, color);
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      _applyDefault(existing.id);
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      // The repository reports the write: the account lists, and for an
      // edit everything that embeds the account, refresh from that.
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createAccount(input)
          : await repo.updateAccount(existing, input);
      if (!mounted) return;
      _applyDefault(saved.id);
      Haptics.confirm();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.accountCreated(saved.name) : l.accountUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      final refusal = e is ApiException ? e : null;
      final currencyLocked = refusal?.code == 'currency_locked';
      final nameError = refusal?.fieldMessage(l, 'name');
      final currencyError = currencyLocked
          ? l.errCurrencyLocked
          : refusal?.fieldMessage(l, 'currency');
      final balanceError = refusal?.fieldMessage(l, 'initial_balance_cents') ??
          refusal?.fieldMessage(l, 'initial_balance');
      final placed =
          nameError != null || currencyError != null || balanceError != null;
      setState(() {
        _saving = false;
        if (currencyLocked && existing != null) {
          // Back to its own currency, and its own opening balance (the
          // typed one was read in the refused currency), so the next save
          // sends the rest of the edit without them.
          _currencyRefused = true;
          _currency = existing.currency;
          _balance = existing.initialBalanceCents;
        }
        _nameError = nameError;
        _currencyError = currencyError;
        _balanceError = balanceError;
        // A new account whose answer was lost may exist already (POST
        // is not safe to repeat): say so, and hold "Kaydet" until the
        // account list — refetched by the write — has come in.
        final maybe = existing == null &&
            refusal != null &&
            refusal.isNetwork &&
            refusal.mayHaveArrived;
        if (maybe) _unsureOver = ref.read(accountsProvider).value;
        _formError = placed
            ? null
            : (maybe
                ? l.financeSaveMaybe
                : failureMessage(e, l, fallback: l.accountSaveFailed));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final existing = widget.existing;
    final bundle = ref.watch(currenciesProvider).value?.data;
    final options = _options(bundle);
    final accounts = ref.watch(accountsProvider).value?.data;
    // A new account starts in the user's currency.
    final currency = _currency ??
        bundle?.defaultCurrency ??
        ref.watch(currentUserProvider.select((u) => u?.currency)) ??
        options.first.code;
    // A new account's colour rotates through the swatches.
    final color = _color ??
        existing?.color ??
        rotatingSwatch(accounts?.length ?? 0);
    // Whether the currency can still change: always for a new account; for
    // an existing one only while nothing is recorded in it.
    final detail = existing == null
        ? null
        : ref.watch(accountDetailProvider(existing.id)).value?.data;
    final currencyLocked = existing != null &&
        (_currencyRefused || !(detail?.currencyEditable ?? false));
    final subunit = _subunitOf(currency, options);

    return FormScaffold(
      title: _isEdit ? l.accountFormEditTitle : l.accountFormNewTitle,
      actionLabel: _isEdit ? l.actionSave : l.accountFormCreate,
      busy: _saving,
      dirty: _dirty(currency, color),
      onAction: _unsureOver != null &&
              identical(ref.watch(accountsProvider).value, _unsureOver)
          ? null
          : () => _save(currency, color),
      children: [
        FormLabel(l.accountFormType),
        ChoiceWrap<String>(
          choices: [
            for (final type in accountTypes) Choice(type, l.accountType(type)),
          ],
          selected: _type,
          onChanged: _setType,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          // A new account is named after its type; the name is the first
          // thing to make its own.
          autofocus: !_isEdit,
          maxLength: accountNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l.accountFormName,
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: 12),
        FormLabel(l.accountFormCurrency),
        ChoiceWrap<String>(
          choices: [
            for (final option in options)
              Choice(
                option.code,
                option.name == option.code
                    ? option.code
                    : '${option.code} · ${option.name}',
              ),
          ],
          selected: currency,
          onChanged: currencyLocked
              ? null
              : (code) => _setCurrency(code, currency, options),
        ),
        if (_currencyError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _currencyError!,
              style: text.bodySmall!.copyWith(color: c.error),
            ),
          )
        else if (currencyLocked && detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.accountFormCurrencyLocked,
              style: text.bodySmall!.copyWith(color: c.inkLow),
            ),
          ),
        const SizedBox(height: 20),
        AmountField(
          label: l.accountFormOpeningBalance,
          minorUnits: _balance,
          currency: currency,
          subunitToUnit: subunit,
          allowDebt: true,
          // A credit card starts in debt (§7.6).
          debtByDefault: _type == 'credit_card',
          helperText: l.accountFormOpeningBalanceHint,
          errorText: _balanceError,
          onChanged: (value) => setState(() {
            _balance = value;
            _balanceError = null;
          }),
        ),
        const SizedBox(height: 20),
        FormLabel(l.accountFormColor),
        ColorSwatchRow(
          selected: color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: _isDefault ?? _wasDefault(),
          onChanged: (v) => setState(() => _isDefault = v),
          contentPadding: EdgeInsets.zero,
          title: Text(l.accountFormDefault, style: text.titleSmall),
          subtitle: Text(
            l.accountFormDefaultHint,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _formError!,
                style: text.bodyMedium!.copyWith(color: c.error),
              ),
            ),
          ),
      ],
    );
  }
}
