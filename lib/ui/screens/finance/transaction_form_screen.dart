import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/slide_up_route.dart';
import 'finance_utils.dart';

/// Pushes the full-screen İşlem Ekle/Düzenle modal on the root navigator via
/// the §5 400/300ms slide-up modal route. Resolves to `true` after a
/// successful create/update.
Future<bool?> openTransactionForm(
  BuildContext context, {
  Transaction? existing,
  int? initialAccountId,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    slideUpModalRoute(
      (_) => TransactionFormScreen(
        existing: existing,
        initialAccountId: initialAccountId,
      ),
    ),
  );
}

class TransactionFormScreen extends ConsumerStatefulWidget {
  final Transaction? existing;
  final int? initialAccountId;

  const TransactionFormScreen({
    super.key,
    this.existing,
    this.initialAccountId,
  });

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late String _kind;
  String _amount = '';
  Account? _account;
  Account? _relatedAccount;
  TxCategory? _category;
  late DateTime _date;
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _seeded = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _kind = ex?.kind ?? 'expense';
    _date = ex?.date ?? DateTime.now();
    _category = ex?.category;
    if (ex?.description != null) _descCtrl.text = ex!.description!;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  List<Account> get _accounts =>
      ref.read(accountsProvider).value?.data
          .where((a) => !a.archived)
          .toList() ??
      const [];

  List<TxCategory> get _categories =>
      ref.read(categoriesProvider).value?.data ?? const [];

  int get _subunit => _account?.subunitToUnit ?? 100;
  String get _currency => _account?.currency ?? 'TRY';
  bool get _showDecimal => _subunit != 1;

  /// Seed the full [Account] objects once the accounts list is available
  /// (edit mode maps AccountRef → Account for subunit/currency).
  void _seedFromExisting() {
    if (_seeded) return;
    // Wait for the first accounts load; an all-archived list is still a value.
    final all = ref.read(accountsProvider).value?.data;
    if (all == null) return;
    final ex = widget.existing;
    Account? byId(int? id) {
      if (id == null) return null;
      for (final a in all) {
        if (a.id == id) return a;
      }
      return null;
    }

    _account = byId(ex?.account.id) ?? byId(widget.initialAccountId);
    // Editing a tx whose account is archived (absent from the picker list):
    // synthesize an Account from the embedded ref so the field is not blank
    // and subunit/currency seed correctly (GAU subunit 1).
    if (_account == null && ex != null) {
      _account = _accountFromRef(ex.account);
    }
    _relatedAccount = byId(ex?.relatedAccount?.id) ??
        (ex?.relatedAccount != null
            ? _accountFromRef(ex!.relatedAccount!)
            : null);
    if (ex != null) {
      _amount = _centsToInput(ex.amountCents, _account?.subunitToUnit ?? 100);
    }
    _seeded = true;
  }

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

  static String _centsToInput(int cents, int subunit) {
    if (subunit == 1) return cents.toString();
    final major = cents / subunit;
    var s = major.toStringAsFixed(2);
    if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
    return s.replaceAll('.', ',');
  }

  int get _cents => amountStringToCents(_amount, _subunit);

  // --- keypad handlers -------------------------------------------------------

  void _onDigit(String d) {
    final parts = _amount.split(',');
    if (parts.length == 2 && parts[1].length >= 2) return; // max 2 decimals
    if (parts[0].replaceAll('.', '').length >= 12 && parts.length == 1) return;
    setState(() => _amount = _amount + d);
  }

  void _onDot() {
    if (!_showDecimal || _amount.contains(',')) return;
    setState(() => _amount = _amount.isEmpty ? '0,' : '$_amount,');
  }

  void _onBackspace() {
    if (_amount.isEmpty) return;
    setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  /// The typed amount, grouped for the active locale. Internally the decimal
  /// marker is always ',' (see [amountStringToCents]); only the display uses
  /// the locale's separator, so English shows "1,234.56" for the same input.
  String get _displayAmount {
    final symbol = currencySymbol(_currency);
    final format = NumberFormat('#,##0');
    final decimalSep = format.symbols.DECIMAL_SEP;
    if (_amount.isEmpty) return '0 $symbol';
    final parts = _amount.split(',');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final grouped = format.format(int.tryParse(intPart) ?? 0);
    final frac = parts.length == 2
        ? '$decimalSep${parts[1]}'
        : (_amount.endsWith(',') ? decimalSep : '');
    return '$grouped$frac $symbol';
  }

  // --- pickers ---------------------------------------------------------------

  Future<void> _pickAccount({required bool related}) async {
    final l = context.l10n;
    final options = [
      for (final a in _accounts)
        if (!related || a.id != _account?.id)
          PickerOption<int>(
            value: a.id,
            label: a.name,
            color: hexColor(a.color),
            trailing:
                formatMoney(a.balanceCents, a.currency, a.subunitToUnit),
          ),
    ];
    if (options.isEmpty) return;
    final id = await showPickerSheet<int>(
      context,
      title: related ? l.txFormTargetAccount : l.txFormAccount,
      options: options,
      selected: related ? _relatedAccount?.id : _account?.id,
    );
    if (id == null) return;
    final picked = _accounts.firstWhere((a) => a.id == id);
    setState(() {
      if (related) {
        _relatedAccount = picked;
      } else {
        _account = picked;
        if (!_showDecimal) _amount = _amount.split(',').first;
      }
    });
  }

  Future<void> _pickCategory() async {
    final l = context.l10n;
    final roots = _categories
        .where((c) => c.kind == _kind && c.parentId == null)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final options = <PickerOption<int>>[];
    for (final root in roots) {
      options.add(PickerOption<int>(
        value: root.id,
        label: root.name,
        color: hexColor(root.color),
      ));
      final children = _categories
          .where((c) => c.parentId == root.id)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      for (final child in children) {
        options.add(PickerOption<int>(
          value: child.id,
          label: '   ${child.name}',
          color: hexColor(child.color),
        ));
      }
    }
    if (options.isEmpty) return;
    final id = await showPickerSheet<int>(
      context,
      title: l.txFormCategory,
      options: options,
      selected: _category?.id,
    );
    if (id == null) return;
    setState(() =>
        _category = _categories.firstWhere((c) => c.id == id));
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

  String? _validate(AppL10n l) {
    if (_cents <= 0) return l.txFormEnterAmount;
    if (_account == null) return l.txFormSelectAccount;
    if (_kind == 'transfer') {
      if (_relatedAccount == null) return l.txFormSelectTargetAccount;
      if (_relatedAccount!.id == _account!.id) {
        return l.txFormAccountsMustDiffer;
      }
    } else if (_category == null) {
      return l.txFormSelectCategory;
    }
    return null;
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final err = _validate(l);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = TransactionInput(
      kind: _kind,
      amountCents: _cents,
      date: _date,
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      accountId: _account!.id,
      financeCategoryId: _kind == 'transfer' ? null : _category?.id,
      relatedAccountId: _kind == 'transfer' ? _relatedAccount?.id : null,
    );
    // Capture the container before the await so provider access never touches
    // a disposed `ref` after the form pops.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repo = ref.read(repositoryProvider);
      if (_isEdit) {
        await repo.updateTransaction(widget.existing!.id, input);
      } else {
        await repo.createTransaction(input);
      }
      if (!mounted) return;
      container.invalidate(financeDashboardProvider);
      container.invalidate(accountsProvider);
      container.invalidate(transactionsProvider);
      Haptics.success();
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.localized(l);
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = l.txSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild once accounts/categories arrive so seeding + pickers have data.
    ref.watch(accountsProvider);
    ref.watch(categoriesProvider);
    _seedFromExisting();
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(_isEdit ? l.txFormEditTitle : l.txFormNewTitle),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: PrimaryButton(
          label: _isEdit ? l.actionUpdate : l.actionSave,
          loading: _saving,
          onPressed: _submit,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _KindPill(
                kind: _kind,
                onChanged: (k) => setState(() {
                  _kind = k;
                  if (k == 'transfer') {
                    _category = null;
                  } else if (_category != null && _category!.kind != k) {
                    _category = null;
                  }
                }),
              ),
            ),
            const SizedBox(height: 24),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _displayAmount,
                style: text.displayLarge!.copyWith(
                  fontFeatures: tabularFigures,
                  color: _amount.isEmpty ? c.inkLow : c.inkHi,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AmountKeypad(
              onDigit: _onDigit,
              onDot: _onDot,
              onBackspace: _onBackspace,
              onClear: () => setState(() => _amount = ''),
              showDecimal: _showDecimal,
            ),
            const SizedBox(height: 16),
            _row(
              icon: Icons.account_balance_wallet_outlined,
              label: l.txFormAccount,
              value: _account?.name,
              color: _account == null ? null : hexColor(_account!.color),
              onTap: () => _pickAccount(related: false),
            ),
            const SizedBox(height: 8),
            if (_kind == 'transfer')
              _row(
                icon: Icons.swap_horiz,
                label: l.txFormTargetAccount,
                value: _relatedAccount?.name,
                color: _relatedAccount == null
                    ? null
                    : hexColor(_relatedAccount!.color),
                onTap: () => _pickAccount(related: true),
              )
            else
              _row(
                icon: Icons.category_outlined,
                label: l.txFormCategory,
                value: _category?.name,
                color: _category == null ? null : hexColor(_category!.color),
                onTap: _pickCategory,
              ),
            const SizedBox(height: 8),
            _row(
              icon: Icons.calendar_today_outlined,
              label: l.txFormDate,
              value: l.relativeDay(_date),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.txFormDescription),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: text.bodySmall!.copyWith(color: c.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? value,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (color != null)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 12),
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(icon, size: 20, color: c.inkMid),
                ),
              Text(label, style: text.bodyMedium!.copyWith(color: c.inkMid)),
              const Spacer(),
              Text(
                value ?? context.l10n.actionSelect,
                style: text.titleSmall!.copyWith(
                  color: value == null ? c.inkLow : c.inkHi,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: c.inkLow),
            ],
          ),
        ),
      ),
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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in options)
            GestureDetector(
              onTap: () {
                if (value != kind) {
                  Haptics.tick();
                  onChanged(value);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: value == kind ? c.goldContainer : Colors.transparent,
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
        ],
      ),
    );
  }
}
