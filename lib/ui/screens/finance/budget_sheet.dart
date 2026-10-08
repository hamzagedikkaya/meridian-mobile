import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/budget.dart';
import '../../../models/finance_dashboard.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sync_hint.dart';
import 'category_sheet.dart';
import 'finance_utils.dart';

/// The budget sheet: a new monthly limit on an expense category, or
/// [existing]'s limit changed or the budget removed.
///
/// Only what the server takes is offered: expense top-level categories
/// that have no budget yet (`budgetable_category_ids`), a limit above zero
/// in the user's currency. With nothing left to budget, the sheet turns
/// into the category form, and the budget goes on the category it makes.
Future<void> showBudgetSheet(BuildContext context, {BudgetStatus? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _BudgetSheet(existing: existing),
  );
}

class _BudgetSheet extends ConsumerStatefulWidget {
  final BudgetStatus? existing;

  const _BudgetSheet({this.existing});

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  late int? _categoryId = widget.existing?.categoryId;

  /// A category made here, before the lists catch up with it.
  TxCategory? _created;
  AmountDraft? _limit;
  bool _creatingCategory = false;
  bool _saving = false;
  bool _atLimit = false;
  String? _categoryError;
  String? _limitError;
  String? _formError;

  AmountDraft _draft(int subunit) =>
      _limit ??
      (widget.existing == null
          ? const AmountDraft()
          : AmountDraft.fromMinorUnits(widget.existing!.limitCents, subunit));

  Future<void> _save(int subunit) async {
    final l = context.l10n;
    final cents = _draft(subunit).minorUnits(subunit);
    final categoryId = _categoryId;
    final problems = (
      category: categoryId == null ? l.budgetPickCategory : null,
      limit: cents <= 0 ? l.budgetLimitRequired : null,
    );
    if (problems.category != null || problems.limit != null) {
      Haptics.danger();
      setState(() {
        _categoryError = problems.category;
        _limitError = problems.limit;
      });
      return;
    }
    final input =
        BudgetInput(categoryId: categoryId!, monthlyLimitCents: cents);
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      // The repository reports the write: the dashboard's budgets card and
      // the category's detail refresh from that.
      final repo = ref.read(repositoryProvider);
      if (existing == null) {
        await repo.createBudget(input);
      } else {
        await repo.updateBudget(existing, input);
      }
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop();
      showAppSnack(context, existing == null ? l.budgetCreated : l.budgetUpdated);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      final limitError = refusal?.fieldMessage(l, 'monthly_limit_cents') ??
          refusal?.fieldMessage(l, 'monthly_limit');
      final categoryError = refusal?.fieldMessage(l, 'finance_category_id') ??
          refusal?.fieldMessage(l, 'finance_category');
      setState(() {
        _saving = false;
        _limitError = limitError;
        _categoryError = categoryError;
        _formError = limitError == null && categoryError == null
            ? failureMessage(e, l, fallback: l.budgetSaveFailed)
            : null;
      });
    }
  }

  void _remove() {
    final l = context.l10n;
    final existing = widget.existing!;
    final navigator = Navigator.of(context);
    final host = navigator.context;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    navigator.pop();
    deleteWithUndo(
      host,
      deletes,
      record: (scope: DataScope.budgets, id: existing.id),
      message: l.budgetRemoved(existing.categoryName),
      send: () => repo.deleteBudget(existing.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final budgetsAsync = ref.watch(budgetsProvider);
    final bundle = budgetsAsync.value?.data;
    final categories = withoutDeleted(
      ref.watch(categoriesProvider).value?.data ?? const <TxCategory>[],
      ref.watch(deferredDeletesProvider),
      DataScope.categories,
      (cat) => cat.id,
    );
    final user = ref.watch(currentUserProvider);
    // Budgets are kept in the user's currency.
    final currency = bundle?.currency ?? user?.currency ?? 'TRY';
    final subunit = bundle?.subunitToUnit ?? user?.subunitToUnit ?? 100;
    final existing = widget.existing;

    if (_creatingCategory) {
      return _sheet(
        context,
        title: l.categoryFormNewTitle,
        onBack: () => setState(() => _creatingCategory = false),
        children: [
          CategoryForm(
            kind: 'expense',
            allowParent: false,
            onSaved: (created) => setState(() {
              _created = created;
              _categoryId = created.id;
              _categoryError = null;
              _creatingCategory = false;
            }),
          ),
        ],
      );
    }

    final draft = _draft(subunit);
    return _sheet(
      context,
      title: existing == null
          ? l.budgetNewTitle
          : l.budgetEditTitle(existing.categoryName),
      children: [
        if (existing == null) ...[
          FormLabel(l.budgetCategory),
          _categoryChoices(context, bundle, budgetsAsync, categories),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_categoryError!,
                  style: text.bodySmall!.copyWith(color: c.error)),
            ),
          const SizedBox(height: 16),
        ],
        FormLabel(l.budgetLimit),
        Semantics(
          liveRegion: true,
          label: l.budgetLimit,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              draft.display(currency),
              style: text.displayLarge!.copyWith(
                fontFeatures: tabularFigures,
                color: draft.isEmpty ? c.inkLow : c.inkHi,
              ),
            ),
          ),
        ),
        if (_limitError != null || _atLimit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _limitError ??
                  l.amountTooLarge(formatMoney(
                      AmountDraft.maxMinorUnits, currency, subunit)),
              textAlign: TextAlign.center,
              style: text.bodySmall!.copyWith(
                  color: _limitError != null ? c.error : c.warning),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l.budgetCurrencyNote(currency),
            textAlign: TextAlign.center,
            style: text.bodySmall!.copyWith(color: c.inkLow),
          ),
        ),
        const SizedBox(height: 8),
        AmountKeypad(
          onDigit: (d) => setState(() {
            _atLimit = draft.wouldPassLimit(d, subunit);
            _limit = draft.withDigit(d, subunit);
            _limitError = null;
          }),
          onDot: () => setState(() => _limit = draft.withDecimalMark(subunit)),
          onBackspace: () => setState(() {
            _atLimit = false;
            _limit = draft.backspace();
          }),
          onClear: () => setState(() {
            _atLimit = false;
            _limit = const AmountDraft();
          }),
          showDecimal: decimalsFor(subunit) > 0,
        ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(_formError!,
                  style: text.bodySmall!.copyWith(color: c.error)),
            ),
          ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: l.actionSave,
          loading: _saving,
          onPressed: () => _save(subunit),
        ),
        if (existing != null) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _remove,
            style: TextButton.styleFrom(
              foregroundColor: c.error,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l.budgetRemove),
          ),
        ],
      ],
    );
  }

  /// The categories a budget can go on, as pills; a spinner while they
  /// load; and when none is left, a way to make one.
  Widget _categoryChoices(
    BuildContext context,
    BudgetsBundle? bundle,
    AsyncValue<Object?> budgetsAsync,
    List<TxCategory> categories,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    if (bundle == null) {
      if (budgetsAsync.hasFailed) {
        return Text(l.errServerUnreachable,
            style: text.bodySmall!.copyWith(color: c.error));
      }
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final byId = {for (final cat in categories) cat.id: cat};
    final options = [
      for (final id in bundle.budgetableCategoryIds) ?byId[id],
      if (_created != null &&
          !bundle.budgetableCategoryIds.contains(_created!.id))
        _created!,
    ];
    if (options.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.budgetNoCategories,
              style: text.bodyMedium!.copyWith(color: c.inkMid)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _creatingCategory = true),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.categoryNew),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceWrap<int>(
          choices: [
            for (final cat in options)
              Choice(cat.id, cat.name, color: hexColor(cat.color)),
          ],
          selected: _categoryId,
          onChanged: (id) => setState(() {
            _categoryId = id;
            _categoryError = null;
          }),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _creatingCategory = true),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l.categoryNew),
        ),
      ],
    );
  }

  Widget _sheet(
    BuildContext context, {
    required String title,
    VoidCallback? onBack,
    required List<Widget> children,
  }) {
    final text = Theme.of(context).textTheme;
    final refreshing = ref.watch(budgetsProvider).isRefetching;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SyncHint.over(
        active: refreshing,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: context.l10n.actionBack,
                        onPressed: onBack,
                      ),
                    Expanded(child: Text(title, style: text.titleLarge)),
                  ],
                ),
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
