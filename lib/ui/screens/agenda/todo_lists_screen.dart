import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/row_motion.dart';
import '../../widgets/sync_hint.dart';
import 'todo_sheet.dart' show todoListNameMaxLength;

/// The todo lists page (`/agenda/lists`, design-analysis §7.4): each list
/// with its colour and open todos; a tap renames, recolours, archives or
/// deletes it in a sheet; "Yeni liste" in the app bar makes one. The
/// archived lists wait under "Arşivlenmiş".
class TodoListsScreen extends ConsumerWidget {
  const TodoListsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(dataSyncProvider).refresh([todoListsProvider]);
    await settleRefresh([
      refetchLanded(ref, todoListsProvider),
    ], minimum: Motion.refreshMinimum);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(todoListsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final fetched = async.value;

    Widget body;
    if (fetched != null) {
      List<TodoList> shown(List<TodoList> lists) =>
          withoutDeleted(lists, hidden, DataScope.todoLists, (list) => list.id);
      final lists = shown(fetched.data.lists);
      final archived = shown(fetched.data.archived);
      body = Column(
        children: [
          OfflineBannerSlot(
            banner: async.refreshFailed
                ? OfflineBanner(
                    lastUpdated: fetched.at,
                    onRetry: () =>
                        ref.read(dataSyncProvider).refresh([todoListsProvider]),
                  )
                : null,
          ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              onRefresh: () => _refresh(ref),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (lists.isEmpty && archived.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      // The app bar's "Yeni liste" is the one way to add
                      // (§6.5): no second button here.
                      child: EmptyState(
                        icon: Icons.format_list_bulleted_rounded,
                        title: l.todoListsEmpty,
                      ),
                    )
                  else ...[
                    if (lists.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Insets.gutter,
                          Gap.md,
                          Insets.gutter,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: NokturnCard(
                            variant: NokCardVariant.list,
                            child: RemovalAwareList<TodoList>(
                              items: lists,
                              recordOf: (list) =>
                                  (scope: DataScope.todoLists, id: list.id),
                              itemBuilder: (context, list) => RowMotion(
                                record: (
                                  scope: DataScope.todoLists,
                                  id: list.id,
                                ),
                                child: _ListRow(list: list),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (archived.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: Gap.lg),
                          child: ExpansionTile(
                            key: const ValueKey('archived-lists'),
                            title: Text(
                              '${l.todoListsArchived} · ${archived.length}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Insets.gutter,
                                ),
                                child: NokturnCard(
                                  variant: NokCardVariant.list,
                                  child: Column(
                                    children: [
                                      for (final list in archived)
                                        _ListRow(list: list),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: Gap.x5 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState.error(
        onRetry: () => ref.read(dataSyncProvider).refresh([todoListsProvider]),
      );
    } else {
      body = const SizedBox.expand();
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l.todoListsTitle),
        actions: [
          TextButton.icon(
            onPressed: () => openTodoListSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(l.todoListNew),
          ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }
}

/// A list: its colour, its name, its open and total todos, and how many
/// are open on the right. A tap opens its sheet.
class _ListRow extends StatelessWidget {
  final TodoList list;

  const _ListRow({required this.list});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(list.color, c);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          key: ValueKey('todo-list-${list.id}'),
          onTap: () => openTodoListSheet(context, existing: list),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.rowH,
                vertical: Gap.sm,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: tone.fill,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(list.name, style: text.titleMedium),
                        Text(
                          l.todoListCounts(list.openCount, list.todosCount),
                          style: text.bodySmall!.copyWith(color: c.inkMid),
                        ),
                      ],
                    ),
                  ),
                  if (list.openCount > 0) ...[
                    const SizedBox(width: Gap.md),
                    ExcludeSemantics(
                      child: Text(
                        '${list.openCount}',
                        style: context.nokText.numMeta.copyWith(
                          color: c.inkMid,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: Gap.xs),
                  Icon(Icons.chevron_right_rounded, color: c.inkLow),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the list sheet — a new list, or [existing] to rename, recolour,
/// archive (or restore) or delete — and resolves to the list as saved, or
/// null. [context] is the screen's: a delete or an archive says so there.
Future<TodoList?> openTodoListSheet(
  BuildContext context, {
  TodoList? existing,
}) {
  return showNokSheet<TodoList>(
    context,
    enableDrag: false,
    builder: (_) => _TodoListSheet(existing: existing, host: context),
  );
}

class _TodoListSheet extends ConsumerStatefulWidget {
  final TodoList? existing;
  final BuildContext host;

  const _TodoListSheet({this.existing, required this.host});

  @override
  ConsumerState<_TodoListSheet> createState() => _TodoListSheetState();
}

class _TodoListSheetState extends ConsumerState<_TodoListSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  String? _color;
  bool _saving = false;
  String? _nameError;
  String? _formError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _nameError = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  TodoListInput _input(String color) =>
      TodoListInput(name: _name.text, color: color);

  bool _dirty(String color) {
    final existing = widget.existing;
    if (existing == null) return _name.text.trim().isNotEmpty;
    return _input(color).changesFrom(existing).isNotEmpty;
  }

  Future<void> _close(String color) async {
    if (!_dirty(color) || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save(String color) async {
    final l = context.l10n;
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      Haptics.reject();
      setState(() => _nameError = l.todoListNameRequired);
      return;
    }
    final existing = widget.existing;
    final input = _input(color);
    if (existing != null && input.changesFrom(existing).isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createTodoList(input)
          : await repo.updateTodoList(existing, input);
      ref
          .read(dataSyncProvider)
          .noteChange(
            DataScope.todoLists,
            saved.id,
            existing == null ? ChangeKind.inserted : ChangeKind.updated,
          );
      if (!mounted) return;
      Haptics.confirm();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.todoListCreated(saved.name) : l.todoListUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      final nameError = e is ApiException ? e.fieldMessage(l, 'name') : null;
      setState(() {
        _saving = false;
        _nameError = nameError;
        _formError = nameError != null
            ? null
            : failureMessage(e, l, fallback: l.todoListSaveFailed);
      });
    }
  }

  /// Archives the list (or brings an archived one back), with "Geri al".
  Future<void> _archive() async {
    final existing = widget.existing!;
    final l = context.l10n;
    final host = widget.host;
    final repo = ref.read(repositoryProvider);
    final archiving = !existing.archived;
    Navigator.of(context).pop();
    Future<void> set(bool archived) =>
        repo.setTodoListArchived(existing.id, archived: archived);
    try {
      await set(archiving);
      if (!host.mounted) return;
      showAppSnack(
        host,
        archiving
            ? l.todoListArchived(existing.name)
            : l.todoListRestored(existing.name),
        actionLabel: l.actionUndo,
        onAction: () => set(!archiving).then((_) {}, onError: (Object _) {}),
      );
    } catch (e) {
      if (!host.mounted) return;
      showAppSnack(
        host,
        failureMessage(e, l, fallback: l.todoListSaveFailed),
        isError: true,
      );
    }
  }

  /// Deleting asks what becomes of the list's todos, with their count: they
  /// stay in no list (the default, §2.6-8) or go with it. An empty list
  /// just goes, with "Geri al".
  Future<void> _delete() async {
    final existing = widget.existing!;
    final l = context.l10n;
    final host = widget.host;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    final record = (scope: DataScope.todoLists, id: existing.id);
    final navigator = Navigator.of(context);
    if (existing.todosCount == 0) {
      navigator.pop();
      if (!host.mounted) return;
      deleteWithUndo(
        host,
        deletes,
        record: record,
        message: l.todoListDeleted(existing.name),
        send: () => repo.deleteTodoList(existing.id, keepTodos: true),
        failedMessage: l.todoListDeleteFailed,
      );
      return;
    }
    final keep = await showTodoListDeleteDialog(context, existing);
    if (keep == null || !mounted) return;
    navigator.pop();
    if (!host.mounted) return;
    deleteNow(
      host,
      deletes,
      record: record,
      message: l.todoListDeleted(existing.name),
      send: () => repo.deleteTodoList(existing.id, keepTodos: keep),
      failedMessage: l.todoListDeleteFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final count = ref.watch(todoListsProvider).value?.data.lists.length ?? 0;
    final color = _color ?? widget.existing?.color ?? rotatingSwatch(count);
    final existing = widget.existing;
    return PopScope<Object?>(
      canPop: !_dirty(color),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(color);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: _isEdit ? l.todoListEdit : l.todoListNew,
              showClose: true,
              onClose: () => _close(color),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Insets.sheetH,
                  Gap.sm,
                  Insets.sheetH,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      autofocus: !_isEdit,
                      maxLength: todoListNameMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(color),
                      decoration: InputDecoration(
                        labelText: l.todoListName,
                        errorText: _nameError,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    FormLabel(l.todoListColor),
                    ColorSwatchRow(
                      selected: color,
                      onChanged: (hex) => setState(() => _color = hex),
                    ),
                    if (_formError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _formError!,
                            style: text.bodyMedium!.copyWith(color: c.error),
                          ),
                        ),
                      ),
                    if (existing != null) ...[
                      const SizedBox(height: Gap.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _archive,
                          icon: Icon(
                            existing.archived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            size: 20,
                          ),
                          label: Text(
                            existing.archived
                                ? l.actionRestore
                                : l.actionArchive,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SheetActions(
              primary: PrimaryButton(
                label: l.actionSave,
                loading: _saving,
                onPressed: () => _save(color),
              ),
              destructive: existing == null
                  ? null
                  : TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(Hit.min),
                      ),
                      child: Text(l.actionDelete),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks what becomes of [list]'s todos when it is deleted, naming how many
/// there are (§4.16, case 3): "Görevleri listesiz bırak" — the default, the
/// filled button — keeps them in no list (true); "Görevlerle birlikte sil"
/// deletes them with it (false); "Vazgeç" cancels (null).
Future<bool?> showTodoListDeleteDialog(BuildContext context, TodoList list) {
  final l = context.l10n;
  final c = context.nok;
  return showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.todoListDeleteTitle(list.name)),
      content: Text(l.todoListDeleteBody(list.todosCount)),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: Gap.sm,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(64, Hit.min)),
          child: Text(l.todoListDeleteKeep),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: c.error,
            minimumSize: const Size(64, Hit.min),
          ),
          child: Text(l.todoListDeleteAll),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          style: TextButton.styleFrom(
            foregroundColor: c.inkHi,
            minimumSize: const Size(64, Hit.min),
          ),
          child: Text(l.actionCancel),
        ),
      ],
    ),
  );
}
