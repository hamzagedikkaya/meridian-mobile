import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sync_hint.dart';
import '../today/widgets/today_common.dart';
import 'todo_sheet.dart';

/// The todo lists: each with its open and total todos. A tap opens the
/// list's todos; the pencil renames, recolours or deletes it; "Liste"
/// makes a new one.
class TodoListsScreen extends ConsumerWidget {
  const TodoListsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(dataSyncProvider).refresh([todoListsProvider]);
    await settleRefresh(
      [refetchLanded(ref, todoListsProvider)],
      minimum: const Duration(milliseconds: 500),
    );
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
      final lists = withoutDeleted(
        fetched.data.lists,
        hidden,
        DataScope.todoLists,
        (list) => list.id,
      );
      body = Column(
        children: [
          if (async.refreshFailed)
            OfflineBanner(
              lastUpdated: fetched.at,
              onRetry: () =>
                  ref.read(dataSyncProvider).refresh([todoListsProvider]),
            ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              onRefresh: () => _refresh(ref),
              child: lists.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: EmptyState(
                            icon: Icons.format_list_bulleted,
                            title: l.todoListsEmpty,
                            actionLabel: l.todoListNew,
                            onAction: () => openTodoListSheet(context),
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                      children: [
                        NokturnCard(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              for (final list in lists)
                                NokturnRow(
                                  key: ValueKey('todo-list-${list.id}'),
                                  leading: Container(
                                    width: 14,
                                    height: 14,
                                    margin: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: hexColor(list.color,
                                          fallback: c.inkLow),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  title: list.name,
                                  meta: l.todoListCounts(
                                      list.openCount, list.todosCount),
                                  onTap: () => context
                                      .go('/agenda?list=${list.id}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: l.todoListEdit,
                                    onPressed: () => openTodoListSheet(
                                      context,
                                      existing: list,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: l.errServerUnreachable,
        subtitle: l.errCheckWifi,
        actionLabel: l.actionRetry,
        onAction: () => ref.read(dataSyncProvider).refresh([todoListsProvider]),
      );
    } else {
      body = const Center(child: CircularProgressIndicator.adaptive());
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(l.todoListsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => openTodoListSheet(context),
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        icon: const Icon(Icons.add),
        label: Text(l.todoListNew),
      ),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }
}

/// Opens the list sheet — a new list, or [existing] to rename, recolour or
/// delete — and resolves to the list as saved, or null.
Future<TodoList?> openTodoListSheet(BuildContext context, {TodoList? existing}) {
  return showModalBottomSheet<TodoList>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    showDragHandle: false,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _TodoListSheet(existing: existing),
  );
}

class _TodoListSheet extends ConsumerStatefulWidget {
  final TodoList? existing;

  const _TodoListSheet({this.existing});

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
      Haptics.danger();
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
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.todoListCreated(saved.name) : l.todoListUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final nameError =
          e is ApiException ? e.fieldMessage(l, 'name') : null;
      setState(() {
        _saving = false;
        _nameError = nameError;
        _formError = nameError != null
            ? null
            : failureMessage(e, l, fallback: l.todoListSaveFailed);
      });
    }
  }

  /// Deleting asks what becomes of the list's todos, with their count: they
  /// go with it, or stay in no list. An empty list just goes, with undo.
  Future<void> _delete() async {
    final existing = widget.existing!;
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    final record = (scope: DataScope.todoLists, id: existing.id);
    final navigator = Navigator.of(context);
    if (existing.todosCount == 0) {
      navigator.pop();
      deleteWithUndo(
        context,
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
    deleteNow(
      context,
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
    return PopScope<Object?>(
      canPop: !_dirty(color),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(color);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => _close(color),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _isEdit ? l.todoListEdit : l.todoListNew,
                        style: text.titleLarge,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      FormLabel(l.todoListColor),
                      ColorSwatchRow(
                        selected: color,
                        onChanged: (hex) => setState(() => _color = hex),
                      ),
                      if (_formError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _formError!,
                              style:
                                  text.bodyMedium!.copyWith(color: c.error),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: l.actionSave,
                        loading: _saving,
                        onPressed: () => _save(color),
                      ),
                      if (_isEdit) ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _saving ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: c.error,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(l.actionDelete),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks what becomes of [list]'s todos when it is deleted, naming how many
/// there are: true keeps them (in no list), false deletes them with it,
/// null cancels.
Future<bool?> showTodoListDeleteDialog(BuildContext context, TodoList list) {
  final l = context.l10n;
  final c = context.nok;
  return showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.todoListDeleteTitle(list.name)),
      content: Text(l.todoListDeleteBody(list.todosCount)),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: Text(l.actionCancel),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l.todoListDeleteKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: c.error,
            foregroundColor: c.bg,
          ),
          child: Text(l.todoListDeleteAll),
        ),
      ],
    ),
  );
}
