import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/finance_category.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/sync_hint.dart';
import 'category_sheet.dart';
import 'finance_utils.dart';

/// What the category picker answered.
sealed class CategoryChoice {
  const CategoryChoice();
}

/// "Tüm kategoriler": no category filter.
final class AnyCategory extends CategoryChoice {
  const AnyCategory();
}

/// "Kategorisiz": no category.
final class NoCategory extends CategoryChoice {
  const NoCategory();
}

final class OneCategory extends CategoryChoice {
  final TxCategory category;
  const OneCategory(this.category);
}

/// The categories of [kind] a new transaction most likely takes, for the
/// transaction form's chips (design-analysis §7.7, D28): the ones [recent]
/// transactions of that kind used most (the latest use breaking a tie),
/// then the rest in list order (`position`), [count] at most. [recent] is
/// newest first; [categories] is every category there is — one not among
/// them (deleted since) is skipped.
List<TxCategory> frequentCategories({
  required List<Transaction> recent,
  required List<TxCategory> categories,
  required String kind,
  int count = 6,
}) {
  final byId = {
    for (final category in categories)
      if (category.kind == kind) category.id: category,
  };
  final uses = <int, int>{};
  final latest = <int, int>{};
  for (var i = 0; i < recent.length; i++) {
    final tx = recent[i];
    final id = tx.category?.id;
    if (tx.kind != kind || id == null || !byId.containsKey(id)) continue;
    uses[id] = (uses[id] ?? 0) + 1;
    latest.putIfAbsent(id, () => i);
  }
  final ranked = uses.keys.toList()
    ..sort((a, b) {
      final byUses = uses[b]!.compareTo(uses[a]!);
      return byUses != 0 ? byUses : latest[a]!.compareTo(latest[b]!);
    });
  final out = [for (final id in ranked.take(count)) byId[id]!];
  for (final entry in categoryTree(byId.values, kind: kind)) {
    if (out.length >= count) break;
    if (!out.any((c) => c.id == entry.category.id)) out.add(entry.category);
  }
  return out;
}

/// The category picker: "Kategorisiz", then the categories of [kind] (both
/// kinds, under their own headings, when null) with their subcategories
/// indented, and "+ Yeni kategori" at the end, which turns the sheet into
/// the category form — in the same sheet, never a sheet on a sheet (the
/// step slides in along the horizontal axis) — and picks the category it
/// creates.
///
/// [selected] marks the current choice. [allowAny] adds "Tüm kategoriler"
/// (the transactions filter); [allowNone] "Kategorisiz"; [allowCreate] the
/// new-category row. Resolves to null when dismissed.
Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  required String title,
  String? kind,
  CategoryChoice? selected,
  bool allowAny = false,
  bool allowNone = true,
  bool allowCreate = true,
}) {
  return showNokSheet<CategoryChoice>(
    context,
    builder: (_) => _CategoryPicker(
      title: title,
      kind: kind,
      selected: selected,
      allowAny: allowAny,
      allowNone: allowNone,
      allowCreate: allowCreate,
    ),
  );
}

class _CategoryPicker extends ConsumerStatefulWidget {
  final String title;
  final String? kind;
  final CategoryChoice? selected;
  final bool allowAny;
  final bool allowNone;
  final bool allowCreate;

  const _CategoryPicker({
    required this.title,
    required this.kind,
    required this.selected,
    required this.allowAny,
    required this.allowNone,
    required this.allowCreate,
  });

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  /// The sheet shows the new-category form instead of the list.
  bool _creating = false;

  bool _isSelected(CategoryChoice choice) => switch ((widget.selected, choice)) {
        (AnyCategory(), AnyCategory()) => true,
        (NoCategory(), NoCategory()) => true,
        (OneCategory(category: final a), OneCategory(category: final b)) =>
          a.id == b.id,
        _ => false,
      };

  void _pick(CategoryChoice choice) {
    Haptics.tick();
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
              child: Row(
                children: [
                  if (_creating)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: l.actionBack,
                      onPressed: () => setState(() => _creating = false),
                    )
                  else
                    const SizedBox(width: Gap.md),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        _creating ? l.categoryFormNewTitle : widget.title,
                        style: text.titleLarge,
                      ),
                    ),
                  ),
                  // The form takes input: it can always be closed (§4.15).
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: l.actionClose,
                    icon: Icon(Icons.close_rounded, size: 24, color: c.inkMid),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SheetStepSwitcher(
                reverse: !_creating,
                // Each step on its own (clear) Material: the switch paints
                // surface3 under it, which would hide the rows' ripples.
                child: Material(
                  key: ValueKey(_creating),
                  type: MaterialType.transparency,
                  child: _creating ? _form() : _list(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() => SingleChildScrollView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: CategoryForm(
          kind: widget.kind ?? 'expense',
          kindEditable: widget.kind == null,
          onSaved: (created) => _pick(OneCategory(created)),
        ),
      );

  Widget _list(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(categoriesProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final all = withoutDeleted(
      async.value?.data ?? const <TxCategory>[],
      hidden,
      DataScope.categories,
      (cat) => cat.id,
    );
    final rows = <Widget>[];
    if (widget.allowAny) {
      rows.add(_row(
        choice: const AnyCategory(),
        label: l.txFilterAllCategories,
        icon: Icons.all_inclusive,
      ));
    }
    if (widget.allowNone) {
      rows.add(_row(
        choice: const NoCategory(),
        label: l.financeUncategorized,
        icon: Icons.label_off_outlined,
      ));
    }
    final kinds =
        widget.kind == null ? categoryKinds : <String>[widget.kind!];
    for (final kind in kinds) {
      final tree = categoryTree(all, kind: kind);
      if (tree.isEmpty) continue;
      if (widget.kind == null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            kind == 'income' ? l.txFilterGroupIncome : l.txFilterGroupExpense,
            style: text.labelMedium!.copyWith(color: c.inkMid),
          ),
        ));
      }
      for (final entry in tree) {
        rows.add(_row(
          choice: OneCategory(entry.category),
          label: entry.category.name,
          color: hexColor(entry.category.color),
          indent: entry.child,
        ));
      }
    }
    if (async.isFirstLoad) {
      rows.add(const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ));
    } else if (async.hasFailed) {
      rows.add(ListTile(
        leading: Icon(Icons.cloud_off, color: c.inkMid),
        title: Text(l.errServerUnreachable, style: text.bodyMedium),
        trailing: TextButton(
          onPressed: () =>
              ref.read(dataSyncProvider).refresh([categoriesProvider]),
          child: Text(l.actionRetry),
        ),
      ));
    }
    if (widget.allowCreate) {
      rows.add(ListTile(
        leading: Icon(Icons.add, color: c.gold),
        title: Text(
          l.categoryNew,
          style: text.titleMedium!.copyWith(color: c.gold),
        ),
        onTap: () {
          Haptics.tick();
          setState(() => _creating = true);
        },
      ));
    }
    return ListView(
      key: const ValueKey('list'),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: rows,
    );
  }

  Widget _row({
    required CategoryChoice choice,
    required String label,
    Color? color,
    IconData? icon,
    bool indent = false,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final selected = _isSelected(choice);
    return ListTile(
      selected: selected,
      contentPadding: EdgeInsetsDirectional.only(
        start: indent ? 44 : Insets.sheetH,
        end: Insets.sheetH,
      ),
      leading: icon != null
          ? Icon(icon, color: c.inkMid)
          : Container(
              width: indent ? 16 : 24,
              height: indent ? 16 : 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
      title: Text(label, style: indent ? text.bodyLarge : text.titleMedium),
      trailing:
          selected ? Icon(Icons.check_rounded, color: c.gold, size: 20) : null,
      onTap: () => _pick(choice),
    );
  }
}
