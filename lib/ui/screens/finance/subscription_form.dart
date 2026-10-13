import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/subscription.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/slide_up_route.dart';
import 'account_form.dart';
import 'category_picker.dart';
import 'finance_utils.dart';
import 'subscriptions_screen.dart' show firstChargeAfter, nextChargeAfter;

/// The longest subscription name the server takes.
const subscriptionNameMaxLength = 60;

/// Opens the subscription form — a new one, or [existing] to edit — as a
/// full-screen modal. Resolves to the subscription saved, or null.
///
/// [context] is the screen's: a delete from the form and its "Geri al"
/// outlive the form, and the undo window ends when that screen is left.
Future<Subscription?> openSubscriptionForm(
  BuildContext context, {
  Subscription? existing,
}) {
  return Navigator.of(context, rootNavigator: true).push<Subscription>(
    slideUpModalRoute(
      (_) => SubscriptionFormScreen(existing: existing, host: context),
    ),
  );
}

const _newAccount = -1;

class SubscriptionFormScreen extends ConsumerStatefulWidget {
  final Subscription? existing;

  /// The screen the form was opened from: a delete's snackbar and undo
  /// window belong to it. Without one, the form's navigator.
  final BuildContext? host;

  const SubscriptionFormScreen({super.key, this.existing, this.host});

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
  late DateTime? _start = widget.existing?.startDate;
  late DateTime? _end = widget.existing?.endDate;

  /// The start or end was changed here: only then are they sent.
  bool _periodTouched = false;
  String? _color;

  /// Set once the user picks one; until then the existing subscription's,
  /// or for a new one the only (or first) active account.
  Account? _account;
  late bool _more = widget.existing?.vendor != null ||
      widget.existing?.note != null ||
      widget.existing?.endDate != null;

  bool _saving = false;
  bool _toggling = false;

  /// A new subscription's answer was lost: the list as it was then.
  /// "Kaydet" waits until a newer one is in (see [_save]).
  Fetched<SubscriptionsBundle>? _unsureOver;
  final _nameKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _nextKey = GlobalKey();
  final _accountKey = GlobalKey();
  final _categoryKey = GlobalKey();
  final _endKey = GlobalKey();
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

  /// The accounts it can be charged to: the active ones (not one that was
  /// just deleted and waits out its undo).
  List<Account> get _active => withoutDeleted(
        (ref.read(accountsProvider).value?.data ?? const <Account>[])
            .where((a) => !a.archived),
        ref.read(deferredDeletesProvider),
        DataScope.accounts,
        (a) => a.id,
      );

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
    final active = _active;
    return active.isEmpty ? null : active.first;
  }

  void _useAccount(Account picked, Account? before) {
    final existing = widget.existing;
    bool same(String a, String b) => a.toUpperCase() == b.toUpperCase();
    setState(() {
      final amount = _amount;
      if (existing != null &&
          before != null &&
          !same(picked.currency, before.currency)) {
        // A subscription moved to another currency (§7.8, contract
        // `amount_required`): its amount is given again, in that currency —
        // never its old number read in the new one. Back in its own
        // currency, its own amount returns.
        _amount = same(picked.currency, existing.account.currency)
            ? existing.amountCents
            : null;
      } else if (amount != null &&
          before != null &&
          before.subunitToUnit != picked.subunitToUnit) {
        // The typed amount stays as typed in the new currency.
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
    // Not "no accounts yet" before the list is here: a failed one loads
    // again, and no first account is offered meanwhile.
    if (reloadAccountsIfMissing(ref)) return;
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

  /// A date from the calendar, starting at [current] (today without one).
  Future<DateTime?> _calendar(DateTime? current) {
    final today = ref.read(currentDayProvider);
    final first = DateTime(2015);
    final last = DateTime(2100);
    final initial = current ?? today;
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last,
    );
  }

  void _setNext(DateTime? date) => setState(() {
        _nextChargeOn = date;
        _errors = {..._errors}..remove('next');
      });

  Future<void> _pickDate() async {
    final picked = await _calendar(_nextChargeOn);
    if (picked != null && mounted) _setNext(picked);
  }

  Future<void> _pickPeriod({required bool end}) async {
    final picked = await _calendar(end ? (_end ?? _start) : _start);
    if (picked == null || !mounted) return;
    setState(() {
      _periodTouched = true;
      if (end) {
        _end = picked;
      } else {
        _start = picked;
      }
      _errors = {..._errors}..remove(end ? 'end' : 'start');
    });
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
      period: _periodTouched ? (start: _start, end: _end) : null,
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

  /// Whether [account] is in another currency than the subscription's.
  bool _movedCurrency(Account? account) {
    final existing = widget.existing;
    return existing != null &&
        account != null &&
        account.currency.toUpperCase() !=
            existing.account.currency.toUpperCase();
  }

  Future<void> _save(Account? account, String color) async {
    final l = context.l10n;
    final problems = <String, String>{
      if (_name.text.trim().isEmpty) 'name': l.subscriptionFormNameRequired,
      if ((_amount ?? 0) <= 0)
        'amount': _amount == null && _movedCurrency(account)
            ? l.errAmountRequired
            : l.subscriptionFormAmountRequired,
      if (account == null)
        'account': accountListProblem(l, ref.read(accountsProvider)) ??
            l.txFormNeedAccount,
    };
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
      _reveal(problems.keys);
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
      Haptics.confirm();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.subscriptionCreated : l.subscriptionUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
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
        'end': ?(dateParam == 'end_date' || dateParam == 'start_date'
            ? l.errInvalidDate
            : (field('end_date') ?? field('start_date'))),
      };
      setState(() {
        _saving = false;
        _errors = placed;
        if (placed.containsKey('end')) _more = true;
        // A new one whose answer was lost may exist already (POST is not
        // safe to repeat): say so, and hold "Kaydet" until the list —
        // refetched by the write — has come in.
        final maybe = existing == null &&
            refusal != null &&
            refusal.isNetwork &&
            refusal.mayHaveArrived;
        if (maybe) _unsureOver = ref.read(subscriptionsProvider).value;
        _formError = placed.isEmpty
            ? (maybe
                ? l.financeSaveMaybe
                : failureMessage(e, l, fallback: l.subscriptionSaveFailed))
            : null;
      });
      if (placed.isNotEmpty) _reveal(placed.keys);
    }
  }

  /// Brings the first field (in the form's order) of [keys] into view.
  void _reveal(Iterable<String> keys) {
    final order = {
      'name': _nameKey,
      'amount': _amountKey,
      'next': _nextKey,
      'account': _accountKey,
      'category': _categoryKey,
      'end': _endKey,
    };
    for (final entry in order.entries) {
      if (keys.contains(entry.key)) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => FormScaffold.revealInvalid(entry.value));
        return;
      }
    }
    Haptics.reject();
  }

  /// Leaves the form for a pause or a delete; unsaved edits are asked about
  /// first. True when it may go.
  Future<bool> _leave(Account? account, String color) async {
    if (!_dirty(account, color)) return true;
    return confirmDiscard(context);
  }

  /// Pauses or resumes it from the form: says so on the screen and closes.
  Future<void> _toggle(Subscription sub, Account? account, String color) async {
    final l = context.l10n;
    if (!await _leave(account, color) || !mounted) return;
    final host = widget.host;
    final navigator = Navigator.of(context);
    final say = host != null && host.mounted ? host : navigator.context;
    setState(() {
      _toggling = true;
      _formError = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .setSubscriptionActive(sub.id, active: !sub.active);
      if (!mounted) return;
      Haptics.confirm();
      navigator.pop();
      if (!say.mounted) return;
      showAppSnack(
        say,
        sub.active
            ? l.subscriptionPausedDone(sub.name)
            : l.subscriptionResumedDone(sub.name),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      setState(() {
        _toggling = false;
        _formError =
            failureMessage(e, l, fallback: l.subscriptionToggleFailed);
      });
    }
  }

  /// Deletes it with "Geri al", on the screen the form was opened from.
  Future<void> _delete(Subscription sub, Account? account, String color) async {
    final l = context.l10n;
    if (!await _leave(account, color) || !mounted) return;
    final navigator = Navigator.of(context);
    final host = widget.host;
    final on = host != null && host.mounted ? host : navigator.context;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    navigator.pop();
    if (!on.mounted) return;
    deleteWithUndo(
      on,
      deletes,
      record: (scope: DataScope.subscriptions, id: sub.id),
      message: l.subscriptionDeleted(sub.name),
      send: () => repo.deleteSubscription(sub.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.value?.data;
    ref.watch(categoriesProvider);
    ref.watch(deferredDeletesProvider);
    // The list is here at last (it was loading, or failed).
    ref.listen(accountsProvider, (previous, next) {
      if (!next.hasValue || (previous?.hasValue ?? false)) return;
      final amount = _amount;
      final fallsTo = widget.existing == null && _account == null
          ? _currentAccount(next.value?.data)
          : null;
      setState(() {
        // What a save said meanwhile no longer holds: the row shows the
        // account the subscription falls to, or that there is none yet.
        _errors = {..._errors}..remove('account');
        // An amount typed meanwhile was read with two decimals; the
        // account it falls to reads it in its own currency.
        if (amount != null &&
            fallsTo != null &&
            fallsTo.subunitToUnit != 100) {
          _amount = AmountDraft.fromMinorUnits(amount, 100)
              .forCurrency(fallsTo.subunitToUnit)
              .minorUnits(fallsTo.subunitToUnit);
        }
      });
    });
    final account = _currentAccount(accounts);
    // The account list not here yet: loading, or failed (a tap on the row
    // loads it again) — never "make your first account" then.
    final accountsLoading = !accountsAsync.hasValue && accountsAsync.isLoading;
    final accountsFailed = !accountsAsync.hasValue && !accountsAsync.isLoading;
    final noAccounts = accounts != null && _active.isEmpty;
    final existing = widget.existing;
    final color = _color ??
        existing?.color ??
        rotatingSwatch(ref.watch(subscriptionsProvider
                .select((s) => s.value?.data.all.length)) ??
            0);
    final currency = account?.currency ?? 'TRY';
    final subunit = account?.subunitToUnit ?? 100;

    // Moved to an account in another currency: the amount must be given
    // again, in that currency (contract `amount_required`).
    final otherCurrency = _movedCurrency(account);
    final today = ref.watch(currentDayProvider);
    final inWeek = DateTime(today.year, today.month, today.day + 7);
    final inMonth = nextChargeAfter(today, 'monthly');
    bool isDay(DateTime d) =>
        _nextChargeOn != null && dayDelta(_nextChargeOn!, now: d) == 0;
    final custom = _nextChargeOn != null &&
        !isDay(today) &&
        !isDay(inWeek) &&
        !isDay(inMonth);

    return FormScaffold(
      title: _isEdit ? l.subscriptionFormEditTitle : l.subscriptionFormNewTitle,
      actionLabel: l.actionSave,
      busy: _saving,
      dirty: _dirty(account, color),
      onAction: _toggling ||
              (_unsureOver != null &&
                  identical(
                      ref.watch(subscriptionsProvider).value, _unsureOver))
          ? null
          : () => _save(account, color),
      errorText: _formError,
      children: [
        TextField(
          key: _nameKey,
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
        const SizedBox(height: Gap.sm),
        AmountField(
          key: _amountKey,
          label: l.subscriptionFormAmount,
          minorUnits: _amount,
          currency: currency,
          subunitToUnit: subunit,
          errorText: _errors['amount'],
          helperText: otherCurrency ? l.subscriptionFormOtherCurrency : null,
          onChanged: (value) => setState(() {
            _amount = value;
            _errors = {..._errors}..remove('amount');
          }),
        ),
        const SizedBox(height: Gap.lg),
        FormLabel(l.subscriptionFormFrequency),
        SegmentedPill<String>(
          options: [
            for (final f in subscriptionFrequencies)
              (f, l.subscriptionFrequency(f)),
          ],
          selected: _frequency,
          onChanged: (f) => setState(() => _frequency = f),
        ),
        const SizedBox(height: Gap.lg),
        FormLabel(l.subscriptionFormNextCharge),
        Wrap(
          key: _nextKey,
          spacing: Gap.sm,
          children: [
            NokChip(
              label: l.dayToday,
              exclusive: true,
              selected: isDay(today),
              onTap: () => _setNext(today),
            ),
            NokChip(
              label: l.subscriptionFormInWeek,
              exclusive: true,
              selected: isDay(inWeek),
              onTap: () => _setNext(inWeek),
            ),
            NokChip(
              label: l.subscriptionFormInMonth,
              exclusive: true,
              selected: isDay(inMonth),
              onTap: () => _setNext(inMonth),
            ),
            NokChip(
              label: custom
                  ? formatDate(_nextChargeOn!,
                      withYear: _nextChargeOn!.year != today.year)
                  : l.actionSelect,
              icon: Icons.event_rounded,
              exclusive: true,
              selected: custom,
              onTap: _pickDate,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: Gap.xs),
          child: Text(
            _errors['next'] ??
                (_nextChargeOn == null
                    ? (_isEdit
                        ? l.subscriptionNoDate
                        // With a start chosen, the server counts the first
                        // payment from it: the date it will be, not "one
                        // period from now".
                        : (_start != null
                            ? formatDate(
                                firstChargeAfter(_start!, _frequency, today),
                                withYear: true)
                            : l.subscriptionFormNextChargeAuto))
                    : formatDate(_nextChargeOn!, withYear: true)),
            style: text.bodySmall!.copyWith(
                color: _errors['next'] != null ? c.error : c.inkMid),
          ),
        ),
        const SizedBox(height: Gap.lg),
        FormPickerRow(
          key: _accountKey,
          icon: Icons.account_balance_wallet_outlined,
          label: l.subscriptionFormAccount,
          value: account?.name ??
              (noAccounts
                  ? l.txFormNeedAccount
                  : (accountsLoading ? l.txFormAccountsLoading : null)),
          color: account == null ? null : hexColor(account.color),
          busy: accountsLoading,
          onTap: () => _pickAccount(account),
          errorText: _errors['account'] ??
              (accountsFailed ? l.txFormAccountsFailed : null),
        ),
        const SizedBox(height: Gap.sm),
        FormPickerRow(
          key: _categoryKey,
          icon: Icons.category_outlined,
          label: l.subscriptionFormCategory,
          value: _category?.name ?? l.financeUncategorized,
          color: _category == null ? null : hexColor(_category!.color),
          onTap: _pickCategory,
          errorText: _errors['category'],
        ),
        const SizedBox(height: Gap.sm),
        if (!_more)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _more = true),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(l.subscriptionFormMore),
            ),
          )
        else ...[
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _vendor,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '${l.subscriptionFormVendor} (${l.labelOptional})',
            ),
          ),
          const SizedBox(height: Gap.md),
          _dateRow(
            icon: Icons.play_circle_outline_rounded,
            label: l.subscriptionFormStart,
            date: _start,
            onTap: () => _pickPeriod(end: false),
            onClear: () => setState(() {
              _periodTouched = true;
              _start = null;
            }),
          ),
          const SizedBox(height: Gap.sm),
          _dateRow(
            key: _endKey,
            icon: Icons.stop_circle_outlined,
            label: l.subscriptionFormEnd,
            date: _end,
            errorText: _errors['end'],
            onTap: () => _pickPeriod(end: true),
            onClear: () => setState(() {
              _periodTouched = true;
              _end = null;
              _errors = {..._errors}..remove('end');
            }),
          ),
          const SizedBox(height: Gap.lg),
          FormLabel(l.subscriptionFormColor),
          ColorSwatchRow(
            selected: color,
            onChanged: (hex) => setState(() => _color = hex),
          ),
          const SizedBox(height: Gap.lg),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '${l.subscriptionFormNote} (${l.labelOptional})',
            ),
          ),
        ],
        // Editing: pause or resume, and — at least 24 dp further down —
        // delete, with "Geri al".
        if (existing != null) ...[
          const SizedBox(height: Gap.xxl),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving || _toggling
                  ? null
                  : () => _toggle(existing, account, color),
              style: TextButton.styleFrom(foregroundColor: c.inkMid),
              icon: Icon(
                existing.active
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(existing.active
                  ? l.subscriptionPause
                  : l.subscriptionResume),
            ),
          ),
          const SizedBox(height: Gap.xxl),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving || _toggling
                  ? null
                  : () => _delete(existing, account, color),
              style: TextButton.styleFrom(foregroundColor: c.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(l.actionDelete),
            ),
          ),
        ],
      ],
    );
  }

  /// A start or end date of the series: the picker row, and an X that
  /// clears a date that is set.
  Widget _dateRow({
    Key? key,
    required IconData icon,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required VoidCallback onClear,
    String? errorText,
  }) {
    final l = context.l10n;
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FormPickerRow(
            icon: icon,
            label: label,
            value: date == null
                ? l.subscriptionFormNotSet
                : formatDate(date, withYear: true),
            onTap: onTap,
            errorText: errorText,
          ),
        ),
        if (date != null)
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, top: Gap.xxs),
            child: IconButton(
              onPressed: onClear,
              tooltip: l.subscriptionFormClearDate,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
    );
  }
}
