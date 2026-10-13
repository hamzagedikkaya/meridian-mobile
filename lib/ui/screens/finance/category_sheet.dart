import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../core/turkish_case.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart' show CategoryMoveFailed;
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/finance_category.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';
import 'finance_utils.dart';

/// The longest category name the server takes.
const categoryNameMaxLength = 60;

/// The fields of a category — name, type, parent, colour — and its save
/// button, as one block: the create/edit sheet of the Kategoriler page, the
/// "+ Yeni kategori" of the category picker and the budget sheet all show
/// it, so a category is made the same way everywhere.
///
/// The fields scroll; the button (and [footer]) stay pinned under them, in
/// the sheet's action area (§4.15) — above the keyboard, which the sheet
/// makes room for (§0.3 #9). So the form needs a bounded height: a sheet's
/// body, never inside another scroll view. The keyboard's ✓ only puts the
/// keyboard away, showing the type, parent and colour still to choose; it
/// never saves.
///
/// The server's rules hold here before it is asked: a parent is a
/// top-level category of the same type (so a category with subcategories
/// cannot get one), and the type of a category in use cannot change. A
/// refusal it still sends (a name already taken under that parent, a parent
/// that has a budget) lands under the field it is about.
///
/// An existing category always shows its type: to change while nothing is
/// filed under it, locked — saying why — once something is. Should the
/// server refuse a type change all the same (`kind_locked`: something was
/// filed under it since the form learnt otherwise), the type goes back to
/// the category's own and stays locked, so the next save sends the rest of
/// the edit without it.
class CategoryForm extends ConsumerStatefulWidget {
  /// The category to edit; null for a new one.
  final TxCategory? existing;

  /// A new category's type.
  final String kind;

  /// Whether the type can be chosen: a new category on the Kategoriler
  /// page, or one not in use yet. The picker's inline form keeps the type
  /// of the transaction.
  final bool kindEditable;

  /// [existing] is in use — transactions, subcategories, a budget or
  /// subscriptions are filed under it — so its type cannot change.
  final bool kindInUse;

  /// Whether a parent can be chosen (the budget sheet makes top-level
  /// categories only).
  final bool allowParent;

  /// Whether the category has subcategories: it then cannot get a parent.
  final bool hasChildren;

  /// The parent a new category starts under.
  final int? initialParentId;

  /// Gets the category as the server saved it — or, when the edit changed
  /// nothing, [existing] itself, the same instance (nothing was sent).
  final ValueChanged<TxCategory> onSaved;

  /// 24 dp under the save button (§4.15): the edit sheet's delete.
  final Widget? footer;

  const CategoryForm({
    super.key,
    this.existing,
    required this.kind,
    this.kindEditable = false,
    this.kindInUse = false,
    this.allowParent = true,
    this.hasChildren = false,
    this.initialParentId,
    required this.onSaved,
    this.footer,
  });

  @override
  ConsumerState<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<CategoryForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late String _kind = widget.existing?.kind ?? widget.kind;
  late int? _parentId = widget.existing?.parentId ?? widget.initialParentId;
  String? _color;
  bool _saving = false;

  /// [CategoryForm.onSaved] has been called: the form is on its way out,
  /// and nothing more is sent or handed back.
  bool _done = false;
  String? _nameError;
  String? _kindError;
  String? _parentError;
  String? _formError;

  /// The server refused a type change (`kind_locked`). The type is locked
  /// here from then on, whatever the category's usage says — before its
  /// refetch lands, or should that fail.
  bool _kindRefused = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(String color) async {
    // One save at a time, and none after it landed: a second answer would
    // pop the route under the sheet as well.
    if (_saving || _done) return;
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      Haptics.reject();
      setState(() => _nameError = l.categoryFormNameRequired);
      return;
    }
    final input = CategoryInput(
      name: name,
      kind: _kind,
      parentId: _parentId,
      color: color,
    );
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      _done = true;
      widget.onSaved(existing);
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createCategory(input)
          : await repo.updateCategory(existing, input);
      if (!mounted) return;
      Haptics.confirm();
      setState(() => _saving = false);
      _done = true;
      widget.onSaved(saved);
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      final refusal = e is ApiException ? e : null;
      final kindLocked = refusal?.code == 'kind_locked';
      final nameError = refusal?.fieldMessage(l, 'name');
      final kindError =
          kindLocked ? l.errKindLocked : refusal?.fieldMessage(l, 'kind');
      final parentError = refusal?.fieldMessage(l, 'parent_id');
      final placed =
          nameError != null || kindError != null || parentError != null;
      setState(() {
        _saving = false;
        if (kindLocked && existing != null) {
          // Back to its own type — and its own parent, which is of that
          // type — so the next save sends the rest of the edit without it.
          _kindRefused = true;
          _kind = existing.kind;
          _parentId = existing.parentId;
        }
        _nameError = nameError;
        _kindError = kindError;
        _parentError = parentError;
        _formError = placed
            ? null
            : failureMessage(e, l, fallback: l.categorySaveFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final all = ref.watch(categoriesProvider).value?.data ?? const [];
    final existing = widget.existing;
    // A new category's colour follows the ones already there.
    final color = _color ?? existing?.color ?? rotatingSwatch(all.length);
    // Not a category whose delete waits out its undo: the server would
    // delete a subcategory filed under it along with it.
    final offered = withoutDeleted(
      all,
      ref.watch(deferredDeletesProvider),
      DataScope.categories,
      (category) => category.id,
    );
    final parents = [
      for (final category in offered)
        if (category.parentId == null &&
            category.kind == _kind &&
            category.id != existing?.id)
          category,
    ]..sort((a, b) => a.position != b.position
        ? a.position.compareTo(b.position)
        : a.name.compareTo(b.name));
    final parentLocked = widget.hasChildren;
    final kindLocked = widget.kindInUse || _kindRefused;
    final kindEditable = widget.kindEditable && !kindLocked;

    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          autofocus: existing == null,
          maxLength: categoryNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          // ✓ puts the keyboard away: the type, parent and colour are
          // still to see (and "Ekle" is in reach above the keyboard anyway).
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
          decoration: InputDecoration(
            labelText: l.categoryFormName,
            errorText: _nameError,
          ),
        ),
        // A new category in the picker or the budget sheet keeps the type
        // it is made for; an existing one always shows its own.
        if (kindEditable || existing != null) ...[
          const SizedBox(height: 4),
          FormLabel(l.categoryFormKind),
          ChoiceWrap<String>(
            choices: [
              Choice('expense', l.financeExpense),
              Choice('income', l.financeIncome),
            ],
            selected: _kind,
            // Locked — or not known yet to be free — it shows but does not
            // change.
            onChanged: kindEditable
                ? (kind) => setState(() {
                      _kind = kind;
                      _kindError = null;
                      // A parent is of the same type.
                      _parentId = null;
                    })
                : null,
          ),
          if (_kindError != null)
            _error(text, c, _kindError!)
          else if (kindLocked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.categoryFormKindLocked,
                style: text.bodySmall!.copyWith(color: c.inkLow),
              ),
            ),
        ],
        if (widget.allowParent) ...[
          const SizedBox(height: 12),
          FormLabel(l.categoryFormParent),
          if (parentLocked)
            Text(
              l.categoryFormParentLocked,
              style: text.bodySmall!.copyWith(color: c.inkLow),
            )
          else
            ChoiceWrap<int?>(
              choices: [
                Choice<int?>(null, l.categoryFormNoParent),
                for (final parent in parents)
                  Choice<int?>(parent.id, parent.name,
                      color: hexColor(parent.color)),
              ],
              selected: _parentId,
              onChanged: (id) => setState(() {
                _parentId = id;
                _parentError = null;
              }),
            ),
          if (_parentError != null) _error(text, c, _parentError!),
        ],
        const SizedBox(height: 12),
        FormLabel(l.categoryFormColor),
        ColorSwatchRow(
          selected: color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
        if (_formError != null)
          Semantics(
            liveRegion: true,
            child: _error(text, c, _formError!),
          ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
            child: fields,
          ),
        ),
        SheetActions(
          primary: PrimaryButton(
            label: existing == null ? l.actionAdd : l.actionSave,
            loading: _saving,
            onPressed: () => _save(color),
          ),
          destructive: widget.footer,
        ),
      ],
    );
  }

  Widget _error(TextTheme text, NokturnColors c, String message) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(message, style: text.bodySmall!.copyWith(color: c.error)),
      );
}

/// The create/edit sheet of a category (the Kategoriler page;
/// design-analysis §7.9): its fields, "Kaydet" and — 24 dp further down —
/// "Sil". A new one gets [kind]; resolves to the category saved, or null.
///
/// [context] is the screen's: a delete and its snackbar outlive the sheet,
/// and its undo window ends when that screen is left (see
/// [deleteWithUndo]).
Future<TxCategory?> showCategorySheet(
  BuildContext context, {
  TxCategory? existing,
  required String kind,
}) {
  final l = context.l10n;
  return showNokSheet<TxCategory>(
    context,
    title: existing == null ? l.categoryFormNewTitle : l.categoryFormEditTitle,
    showClose: true,
    builder: (_) =>
        _CategorySheet(host: context, existing: existing, kind: kind),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  final BuildContext host;
  final TxCategory? existing;
  final String kind;

  const _CategorySheet({
    required this.host,
    this.existing,
    required this.kind,
  });

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  /// "Sil" is reading what the delete would touch, or asking: a second tap
  /// waits for it.
  bool _deleting = false;

  /// Why "Sil" deleted nothing: what the category is used for could not be
  /// read. Said in the sheet — a snackbar would be under it.
  String? _deleteError;

  Future<void> _delete(TxCategory category) async {
    final l = context.l10n;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    String? unreadable;
    await deleteCategory(
      context,
      ref,
      category,
      host: widget.host,
      onUnreadable: (error) {
        Haptics.reject();
        unreadable = failureMessage(error, l, fallback: l.categoryLoadFailed);
      },
    );
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _deleteError = unreadable;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final existing = widget.existing;
    // What the category is used for: whether its type can still change,
    // whether it has subcategories (and what a delete would touch).
    final usage = existing == null
        ? null
        : ref.watch(categoryUsageProvider(existing.id)).value?.data;
    final all = ref.watch(categoriesProvider).value?.data ?? const [];
    final hasChildren = existing != null &&
        (usage?.childrenCount ??
                all.where((cat) => cat.parentId == existing.id).length) >
            0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CategoryForm(
        existing: existing,
        kind: widget.kind,
        // A new one may still be either; an existing one only while
        // nothing is filed under it.
        kindEditable: existing == null || (usage?.kindEditable ?? false),
        kindInUse: usage != null && !usage.kindEditable,
        hasChildren: hasChildren,
        onSaved: (saved) {
          Navigator.of(context).pop(saved);
          // Nothing changed (the form hands the category back as it
          // was): nothing was saved, so nothing is said.
          if (identical(saved, existing)) return;
          final host = widget.host;
          if (!host.mounted) return;
          showAppSnack(
            host,
            existing == null
                ? l.categoryCreated(saved.name)
                : l.categoryUpdated,
            tone: SnackTone.success,
          );
        },
        // Never level with "Kaydet": the action area puts it 24 dp
        // below (§4.15).
        footer: existing == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton.icon(
                    onPressed: _deleting ? null : () => _delete(existing),
                    style: TextButton.styleFrom(
                      foregroundColor: c.error,
                      minimumSize: const Size.fromHeight(Hit.min),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18),
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
      ),
    );
  }
}

/// Deletes [category] — from its edit sheet ([context]), which it closes
/// first. [host] is the screen under the sheet: the delete and its snackbar
/// outlive the sheet, and its undo window ends when that screen is left.
///
/// What a delete touches comes from the server (GET
/// /finance_categories/:id). A category nothing is filed under goes at once,
/// with "Geri al". One in use asks first, naming what happens with counts:
/// its subscriptions are left uncategorized, its subcategories and budgets
/// are deleted — none of which an undo could bring back — and its
/// transactions go where the dialog says: uncategorized, or moved to
/// another category of its type first ("Sil ve taşı").
///
/// Should what it is used for not be readable, nothing is deleted, the
/// sheet stays open and [onUnreadable] hears why; the next "Sil" asks again.
Future<void> deleteCategory(
  BuildContext context,
  WidgetRef ref,
  TxCategory category, {
  required BuildContext host,
  required void Function(Object error) onUnreadable,
}) async {
  final l = context.l10n;
  final navigator = Navigator.of(context);
  final record = (scope: DataScope.categories, id: category.id);
  final repo = ref.read(repositoryProvider);
  final deletes = ref.read(deferredDeletesProvider.notifier);
  final detail = categoryUsageProvider(category.id);
  CategoryUsage usage;
  try {
    // A read that failed is not answered from what it left behind: this
    // tap is its retry.
    if (ref.read(detail).hasError) {
      ref.read(dataSyncProvider).refresh([detail]);
    }
    usage = (await ref.read(detail.future)).data;
  } catch (e) {
    onUnreadable(e);
    return;
  }
  if (!context.mounted || !host.mounted) return;
  if (usage.unused) {
    navigator.pop();
    deleteWithUndo(
      host,
      deletes,
      record: record,
      message: l.categoryDeleted(category.name),
      send: () => repo.deleteCategory(category.id),
      failedMessage: l.categoryDeleteFailed,
    );
    return;
  }
  // Where its transactions can go: another category of its type — not
  // itself, nor one of its subcategories (deleted with it), nor one whose
  // own delete waits out its undo.
  final targets = usage.transactionsCount == 0
      ? const <TxCategory>[]
      : [
          for (final entry in categoryTree(
            withoutDeleted(
              ref.read(categoriesProvider).value?.data ?? const <TxCategory>[],
              ref.read(deferredDeletesProvider),
              DataScope.categories,
              (cat) => cat.id,
            ),
            kind: category.kind,
          ))
            if (entry.category.id != category.id &&
                entry.category.parentId != category.id)
              entry.category,
        ];
  final choice = await _askDelete(context, category, usage, targets);
  if (choice == null || !context.mounted || !host.mounted) return;
  final target = choice.target;
  navigator.pop();
  // A move takes a request per transaction: it says it is on its way until
  // the delete's own snackbar replaces it.
  if (target != null) {
    showAppSnack(
      host,
      l.categoryMoving(usage.transactionsCount),
      persist: true,
    );
  }
  deleteNow(
    host,
    deletes,
    record: record,
    message: target == null
        ? l.categoryDeleted(category.name)
        : l.categoryDeletedMoved(category.name, usage.transactionsCount),
    send: () async {
      // Moved first: a delete would leave them uncategorized. A move that
      // fails stops it all; the category stays.
      if (target != null) {
        await repo.moveCategoryTransactions(category.id, target.id);
      }
      await repo.deleteCategory(category.id);
    },
    failedMessage: l.categoryDeleteFailed,
    // Some may have moved before it stopped: say how many.
    explain: (error) => switch (error) {
      CategoryMoveFailed(:final moved, :final total) when moved > 0 =>
        l.categoryMovePartial(moved, total),
      CategoryMoveFailed(:final cause) =>
        failureMessage(cause, l, fallback: l.categoryDeleteFailed),
      _ => null,
    },
  );
}

/// What the in-use delete dialog answered: delete, moving the transactions
/// to [target] first — or, without one, leaving them uncategorized.
typedef _DeleteChoice = ({TxCategory? target});

/// The one dialog a category delete may ask (design-analysis §4.16): the
/// category by name, what goes with counts, and — when it has transactions
/// and another category of its type exists — where they go: "Kategorisiz"
/// or one of [targets], "Diğer" first when there is one. The verb follows:
/// "Sil" or "Sil ve taşı". Null when cancelled.
Future<_DeleteChoice?> _askDelete(
  BuildContext context,
  TxCategory category,
  CategoryUsage usage,
  List<TxCategory> targets,
) {
  final l = context.l10n;
  final other = trLower(l.starterCategories(category.kind).last);
  TxCategory? initial;
  for (final t in targets) {
    if (trLower(t.name.trim()) == other) initial = t;
  }
  return showDialog<_DeleteChoice>(
    context: context,
    builder: (context) => _DeleteDialog(
      category: category,
      usage: usage,
      targets: targets,
      initial: initial,
    ),
  );
}

class _DeleteDialog extends StatefulWidget {
  final TxCategory category;
  final CategoryUsage usage;
  final List<TxCategory> targets;
  final TxCategory? initial;

  const _DeleteDialog({
    required this.category,
    required this.usage,
    required this.targets,
    this.initial,
  });

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  late TxCategory? _target = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final usage = widget.usage;
    final target = _target;
    return AlertDialog(
      title: Text(l.categoryDeleteTitle(widget.category.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.categoryDeleteImpact(
              transactions: usage.transactionsCount,
              subscriptions: usage.subscriptionsCount,
              children: usage.childrenCount,
              budgets: usage.budgetsCount,
              movedTo: target?.name,
            )),
            if (widget.targets.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              Text(l.categoryMoveTo,
                  style: text.bodySmall!.copyWith(color: c.inkMid)),
              const SizedBox(height: Gap.xs),
              DropdownButtonFormField<int?>(
                initialValue: target?.id,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(l.financeUncategorized),
                  ),
                  for (final t in widget.targets)
                    DropdownMenuItem<int?>(
                      value: t.id,
                      child: Row(
                        children: [
                          Icon(Icons.circle,
                              size: 12, color: entityTone(t.color, c).fill),
                          const SizedBox(width: Gap.sm),
                          Flexible(
                            child: Text(
                              t.parentId == null ? t.name : '  ${t.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _target = id == null
                      ? null
                      : widget.targets.firstWhere((t) => t.id == id);
                }),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: c.inkHi),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((target: target)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, Hit.min),
            backgroundColor: c.error,
            foregroundColor: c.onError,
          ),
          child: Text(
              target == null ? l.actionDelete : l.categoryDeleteAndMove),
        ),
      ],
    );
  }
}
