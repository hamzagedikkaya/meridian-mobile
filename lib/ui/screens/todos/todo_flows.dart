/// What a todo row can do, the same wherever it is shown — Today's card and
/// the Todos screen: tick it off (with "Geri al"), reopen it, move it to
/// tomorrow, delete it (with "Geri al"), and the long-press menu that holds
/// all of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/actions.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import 'todo_sheet.dart';

/// Ticks [todo] off ([done]) or reopens it, on every screen at once (see
/// `TodoActions`), and sends that state. A finished todo leaves the lists
/// of open todos with the refetch that follows; the snackbar's "Geri al"
/// reopens it and puts it back at [index], where it was.
///
/// [restore] is set when this call is itself the undo.
Future<void> setTodoDone(
  BuildContext context,
  WidgetRef ref,
  Todo todo, {
  required bool done,
  int index = 0,
  TodoPlace? restore,
}) async {
  final l = context.l10n;
  final actions = ref.read(todoActionsProvider);
  if (done) {
    final place = (todo: todo, index: index);
    // Up for 6 s, then gone — on every tab, since they share the messenger —
    // or until dismissed while a screen reader is on (see [showAppSnack]).
    showAppSnack(
      context,
      l.todayTodoDone(todo.title),
      actionLabel: l.actionUndo,
      onAction: () {
        if (context.mounted) {
          setTodoDone(context, ref, todo, done: false, restore: place);
        } else {
          // The snackbar outlived the screen: the undo still goes through,
          // with nothing left to show it on.
          actions
              .setDone(todo.id, done: false, restore: place)
              .then((_) {}, onError: (Object _) {});
        }
      },
    );
  }
  try {
    await actions.setDone(todo.id, done: done, restore: restore);
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.todayTodoUpdateFailed),
      isError: true,
    );
  }
}

/// Deletes [todo] the forgiving way: it leaves every list at once, and the
/// delete is sent once "Geri al" has run out (design-research §4.3).
void deleteTodoWithUndo(BuildContext context, WidgetRef ref, Todo todo) {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  deleteWithUndo(
    context,
    ref.read(deferredDeletesProvider.notifier),
    record: (scope: DataScope.todos, id: todo.id),
    message: l.todoDeleted(todo.title),
    send: () => repo.deleteTodo(todo.id),
    failedMessage: l.todoDeleteFailed,
  );
}

/// Moves [todo] to tomorrow — the account's tomorrow — keeping its time of
/// day and everything else about it.
Future<void> postponeTodo(BuildContext context, WidgetRef ref, Todo todo) async {
  final l = context.l10n;
  final today =
      ref.read(homeProvider).value?.data.today ??
      ref.read<DateTime>(currentDayProvider);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  Haptics.tick();
  try {
    await ref.read(repositoryProvider).postponeTodo(todo.id, tomorrow);
    if (!context.mounted) return;
    showAppSnack(context, l.todoPostponed(todo.title));
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.todoSaveFailed),
      isError: true,
    );
  }
}

/// The long-press menu of a todo row: edit, tick off or reopen, move to
/// tomorrow (an open todo), delete. [done] is the checked state on screen;
/// [index] its place in the list it was pressed in.
Future<void> showTodoMenu(
  BuildContext context,
  WidgetRef ref,
  Todo todo, {
  required bool done,
  int index = 0,
}) async {
  final l = context.l10n;
  final c = context.nok;
  final text = Theme.of(context).textTheme;
  Haptics.tick();
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              todo.title,
              style: text.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.actionEdit),
            onTap: () => Navigator.of(sheet).pop('edit'),
          ),
          ListTile(
            leading: Icon(done ? Icons.undo : Icons.check_circle_outline),
            title: Text(done ? l.todoReopen : l.todoComplete),
            onTap: () => Navigator.of(sheet).pop('toggle'),
          ),
          if (!done)
            ListTile(
              leading: const Icon(Icons.next_plan_outlined),
              title: Text(l.todoPostpone),
              onTap: () => Navigator.of(sheet).pop('postpone'),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: c.error),
            title: Text(l.actionDelete, style: TextStyle(color: c.error)),
            onTap: () => Navigator.of(sheet).pop('delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'edit':
      await openTodoSheet(context, existing: todo);
    case 'toggle':
      await setTodoDone(context, ref, todo, done: !done, index: index);
    case 'postpone':
      await postponeTodo(context, ref, todo);
    case 'delete':
      deleteTodoWithUndo(context, ref, todo);
  }
}
