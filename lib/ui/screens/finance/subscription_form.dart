import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/subscription.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/slide_up_route.dart';
import 'account_form.dart';
import 'category_picker.dart';
import 'finance_utils.dart';

/// The longest subscription name the server takes.
const subscriptionNameMaxLength = 60;

/// Opens the subscription form — a new one, or [existing] to edit — as a
/// full-screen modal. Resolves to the subscription saved, or null.
Future<Subscription?> openSubscriptionForm(
  BuildContext context, {
  Subscription? existing,
}) {
  return Navigator.of(context, rootNavigator: true).push<Subscription>(
    slideUpModalRoute((_) => SubscriptionFormScreen(existing: existing)),
  );
}

const _newAccount = -1;

class SubscriptionFormScreen extends ConsumerStatefulWidget {
  final Subscription? existing;

  const SubscriptionFormScreen({super.key, this.existing});

  @override
  ConsumerState<SubscriptionFormScreen> createState() =>
      _SubscriptionFormScreenState();
}

class _SubscriptionFormScreenState
    extends ConsumerState<SubscriptionFormScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _vendor = TextEditingController(text: widget.existing?.vendor);
  late final _note = TextEditingController(text: widget.existing?.note);
  late int? _amount = widget.existing?.amountCents;
  late String _frequency = widget.existing?.frequency ?? 'monthly';
  late DateTime? _nextChargeOn = widget.existing?.nextChargeOn;
  late TxCategory? _category = widget.existing?.category;
  String? _color;

  /// Set once the user picks one; until then the existing subscription's,
  /// or for a new one the only (or first) active account.
  Account? _account;
  late bool _more = widget.existing?.vendor != null ||
      widget.existing?.note != null;

  bool _saving = false;
  Map<String, String> _errors = const {};
  String? _formError;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _vendor.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Account> get _active => [
        for (final a in ref.read(accountsProvider).value?.data ?? const [])
          if (!a.archived) a,
      ];

  /// The account it is charged to: the one picked, else the existing
  /// subscription's (archived ones too), else the only or first active one.
  Account? _currentAccount(List<Account>? all) {
    if (_account != null) return _account;
    final existing = widget.existing;
    if (existing != null) {
      for (final a in all ?? const <Account>[]) {
        if (a.id == existing.account.id) return a;
      }
      return Account(
        id: existing.account.id,
        name: existing.account.name,
        accountType: 'cash',
        currency: existing.account.currency,
        subunitToUnit: existing.account.subunitToUnit,
        color: existing.account.color ?? '#B8860B',
        initialBalanceCents: 0,
        balanceCents: 0,
        archived: true,
      );
    }
    final active = [for (final a in all ?? const <Account>[]) if (!a.archived) a];
    return active.isEmpty ? null : active.first;
  }

  void _useAccount(Account picked, Account? before) {
    setState(() {
      // The typed amount stays as typed in the new currency.
      final amount = _amount;
      if (amount != null &&
          before != null &&
          before.subunitToUnit != picked.subunitToUnit) {
        _amount = AmountDraft.fromMinorUnits(amount, before.subunitToUnit)
            .forCurrency(picked.subunitToUnit)
            .minorUnits(picked.subunitToUnit);
      }
      _account = picked;
      _errors = {..._errors}..remove('account');
    });
  }

  Future<void> _pickAccount(Account? current) async {
    final l = context.l10n;
    final accounts = _active;
    int? id = _newAccount;
    if (accounts.isNotEmpty) {
      id = await showPickerSheet<int>(
        context,
        title: l.subscriptionFormAccount,
        selected: current?.id,
        options: [
          for (final a in accounts)
            PickerOption<int>(
              value: a.id,
              label: a.name,
              color: hexColor(a.color),
              trailing:
                  formatMoney(a.balanceCents, a.currency, a.subunitToUnit),
            ),
          PickerOption<int>(
            value: _newAccount,
            label: l.accountNew,
            icon: Icons.add,
          ),
        ],
      );
    }
    if (id == null || !mounted) return;
    if (id == _newAccount) {
      final created = await openAccountForm(context);
      if (created != null && mounted) _useAccount(created, current);
      return;
    }
    _useAccount(accounts.firstWhere((a) => a.id == id), current);
  }

  Future<void> _pickCategory() async {
    final l = context.l10n;
    final choice = await showCategoryPicker(
      context,
      title: l.subscriptionFormCategory,
      kind: 'expense',
      selected:
          _category == null ? const NoCategory() : OneCategory(_category!),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _category = switch (choice) {
        OneCategory(:final category) => category,
        _ => null,
      };
      _errors = {..._errors}..remove('category');
    });
  }

  Future<void> _pickDate() async {
    final today = ref.read(currentDayProvider);
    final first = DateTime(2015);
    final last = DateTime(2100);
    final current = _nextChargeOn ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        _nextChargeOn = picked;
        _errors = {..._errors}..remove('next');
      });
    }
  }

  String? _text(TextEditingController ctrl) {
    final value = ctrl.text.trim();
    return value.isEmpty ? null : value;
  }

  SubscriptionInput? _input(Account? account, String color) {
    if (account == null) return null;
    return SubscriptionInput(
      name: _name.text.trim(),
      accountId: account.id,
      amountCents: _amount ?? 0,
      frequency: _frequency,
      nextChargeOn: _nextChargeOn,
      categoryId: _category?.id,
      vendor: _text(_vendor),
      note: _text(_note),
      color: color,
    );
  }

  bool _dirty(Account? account, String color) {
    final existing = widget.existing;
    if (existing == null) {
      return _name.text.trim().isNotEmpty || (_amount ?? 0) != 0;
    }
    final input = _input(account, color);
    return input != null &&
        input
            .changesFrom(existing, accountCurrency: account!.currency)
            .isNotEmpty;
  }

  Future<void> _save(Account? account, String color) async {
    final l = context.l10n;
    final problems = <String, String>{
      if (_name.text.trim().isEmpty) 'name': l.subscriptionFormNameRequired,
      if ((_amount ?? 0) <= 0) 'amount': l.subscriptionFormAmountRequired,
      if (account == null) 'account': l.txFormNeedAccount,
    };
    if (problems.isNotEmpty) {
      Haptics.danger();
      setState(() => _errors = problems);
      return;
    }
    final input = _input(account, color)!;
    final existing = widget.existing;
    if (existing != null &&
        input
            .changesFrom(existing, accountCurrency: account!.currency)
            .isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
      _formError = null;
    });
    try {
      // The repository reports the write: the Subscriptions page, the
      // dashboard's upcoming payments and the account's detail refresh.
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createSubscription(input)
          : await repo.updateSubscription(
              existing,
              input,
              accountCurrency: account!.currency,
            );
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.subscriptionCreated : l.subscriptionUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      String? field(String key) => refusal?.fieldMessage(l, key);
      final dateParam = refusal?.code == 'invalid_date' ? refusal?.param : null;
      final placed = <String, String>{
        'name': ?field('name'),
        'amount': ?(refusal?.code == 'amount_required'
            ? l.errAmountRequired
            : (field('amount_cents') ?? field('amount'))),
        'account': ?(field('account') ?? field('account_id')),
        'category': ?field('finance_category_id'),
        'next': ?(dateParam == 'next_charge_on'
            ? l.errInvalidDate
            : field('next_charge_on')),
      };
      setState(() {
        _saving = false;
        _errors = placed;
        _formError = placed.isEmpty
            ? failureMessage(e, l, fallback: l.subscriptionSaveFailed)
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final accounts = ref.watch(accountsProvider).value?.data;
    ref.watch(categoriesProvider);
    final account = _currentAccount(accounts);
    final existing = widget.existing;
    final color = _color ??
        existing?.color ??
        rotatingSwatch(ref.watch(subscriptionsProvider
                .select((s) => s.value?.data.all.length)) ??
            0);
    final currency = account?.currency ?? 'TRY';
    final subunit = account?.subunitToUnit ?? 100;

    return FormScaffold(
      title: _isEdit ? l.subscriptionFormEditTitle : l.subscriptionFormNewTitle,
      actionLabel: l.actionSave,
      busy: _saving,
      dirty: _dirty(account, color),
      onAction: () => _save(account, color),
      children: [
        TextField(
          controller: _name,
          autofocus: !_isEdit,
          maxLength: subscriptionNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _errors = {..._errors}..remove('name')),
          decoration: InputDecoration(
            labelText: l.subscriptionFormName,
            hintText: l.subscriptionFormNameHint,
            errorText: _errors['name'],
          ),
        ),
        const SizedBox(height: 8),
        AmountField(
          label: l.subscriptionFormAmount,
          minorUnits: _amount,
          currency: currency,
          subunitToUnit: subunit,
          errorText: _errors['amount'],
          onChanged: (value) => setState(() {
            _amount = value;
            _errors = {..._errors}..remove('amount');
          }),
        ),
        const SizedBox(height: 16),
        FormLabel(l.subscriptionFormFrequency),
        ChoiceWrap<String>(
          choices: [
            for (final f in subscriptionFrequencies)
              Choice(f, l.subscriptionFrequency(f)),
          ],
          selected: _frequency,
          onChanged: (f) => setState(() => _frequency = f),
        ),
        const SizedBox(height: 16),
        FormPickerRow(
          icon: Icons.account_balance_wallet_outlined,
          label: l.subscriptionFormAccount,
          value: account?.name,
          color: account == null ? null : hexColor(account.color),
          onTap: () => _pickAccount(account),
          errorText: _errors['account'],
        ),
        const SizedBox(height: 8),
        FormPickerRow(
          icon: Icons.event_repeat,
          label: l.subscriptionFormNextCharge,
          value: _nextChargeOn == null
              ? (_isEdit ? l.subscriptionNoDate : l.subscriptionFormNextChargeAuto)
              : formatDate(_nextChargeOn!, withYear: true),
          onTap: _pickDate,
          errorText: _errors['next'],
        ),
        const SizedBox(height: 8),
        FormPickerRow(
          icon: Icons.category_outlined,
          label: l.subscriptionFormCategory,
          value: _category?.name ?? l.financeUncategorized,
          color: _category == null ? null : hexColor(_category!.color),
          onTap: _pickCategory,
          errorText: _errors['category'],
        ),
        const SizedBox(height: 8),
        if (!_more)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _more = true),
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text(l.subscriptionFormMore),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          TextField(
            controller: _vendor,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '${l.subscriptionFormVendor} (${l.labelOptional})',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '${l.subscriptionFormNote} (${l.labelOptional})',
            ),
          ),
          const SizedBox(height: 16),
          FormLabel(l.subscriptionFormColor),
          ColorSwatchRow(
            selected: color,
            onChanged: (hex) => setState(() => _color = hex),
          ),
        ],
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(_formError!,
                  style: text.bodyMedium!.copyWith(color: c.error)),
            ),
          ),
      ],
    );
  }
}
