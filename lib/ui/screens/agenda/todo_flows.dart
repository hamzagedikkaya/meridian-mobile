/// What a todo row can do, the same wherever it is shown — Today's card and
/// the Agenda (design-analysis §6.4): tick it off (with "Geri al"), reopen
/// it, move it to another day (with "Geri al"), delete it (with "Geri al"),
/// and the long-press menu that holds all of them.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../data/actions.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/agenda_rows.dart' show todoPriorityColor;
import '../../widgets/app_snackbar.dart';
import '../../widgets/nok_sheet.dart';
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

/// Reopens finished [todo] — the Agenda's "Tamamlanan" view — saying so,
/// with "Geri al", which finishes it again.
Future<void> reopenTodo(BuildContext context, WidgetRef ref, Todo todo) async {
  final l = context.l10n;
  final actions = ref.read(todoActionsProvider);
  showAppSnack(
    context,
    l.todoReopened(todo.title),
    actionLabel: l.actionUndo,
    onAction: () => actions
        .setDone(todo.id, done: true)
        .then((_) {}, onError: (Object _) {}),
  );
  try {
    await actions.setDone(todo.id, done: false);
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

/// The account's today: `/home`'s, else the device's.
DateTime accountToday(WidgetRef ref) => dateOnly(
  ref.read(homeProvider).value?.data.today ??
      ref.read<DateTime>(currentDayProvider),
);

/// Moves [todo] to tomorrow — the account's tomorrow — keeping its time of
/// day and everything else about it, with "Geri al" (the long-press menu's
/// "Yarına ertele", the swipe to the left).
Future<void> postponeTodo(BuildContext context, WidgetRef ref, Todo todo) {
  final today = accountToday(ref);
  return moveTodos(
    context,
    ref,
    [todo],
    day: DateTime(today.year, today.month, today.day + 1),
    message: context.l10n.todoPostponed(todo.title),
  );
}

/// Where a moved todo lands: [day] at its own time of day ([_Landing.keep])
/// — unless that time is already past on [day] ([now]), then on the day
/// alone — or no date at all.
typedef _Landing = ({DateTime? day, String? time, bool keep});

_Landing _landing(Todo todo, DateTime? day, DateTime now) {
  if (day == null) return (day: null, time: null, keep: false);
  final time = parseDueTime(todo.dueTime);
  if (time == null) return (day: day, time: null, keep: true);
  final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  return at.isAfter(now)
      ? (day: day, time: todo.dueTime, keep: true)
      : (day: day, time: null, keep: false);
}

/// [todo] due on [day] at [time] (or undated), as the server will have it:
/// `overdue` once that moment is past [now].
Todo _withDue(Todo todo, DateTime? day, String? time, DateTime now) {
  final t = parseDueTime(time);
  final dueAt = day == null
      ? null
      : t == null
      ? DateTime(day.year, day.month, day.day, 23, 59, 59)
      : DateTime(day.year, day.month, day.day, t.hour, t.minute);
  return Todo(
    id: todo.id,
    title: todo.title,
    body: todo.body,
    status: todo.status,
    priority: todo.priority,
    dueAt: dueAt,
    dueDate: day,
    dueTime: day == null ? null : time,
    overdue: todo.isOpen && dueAt != null && dueAt.isBefore(now),
    position: todo.position,
    todoList: todo.todoList,
    subtaskCount: todo.subtaskCount,
    completedAt: todo.completedAt,
    goalId: todo.goalId,
  );
}

/// [bundle] (read for [query]) with [moved] in place of the todos it
/// lists: each kept where it is when [query] still takes it, else taken
/// out — the inbox loses a todo given a date — and every filter's count
/// moved with it.
TodosBundle _movedIn(
  TodosBundle bundle,
  TodoQuery query,
  Map<int, Todo> moved,
  DateTime today,
) {
  final counts = {...bundle.counts};
  var overdue = bundle.overdueCount;
  final out = <Todo>[];
  for (final todo in bundle.todos) {
    final to = moved[todo.id];
    if (to == null) {
      out.add(todo);
      continue;
    }
    if (todo.isOpen) {
      for (final filter in counts.keys.toList()) {
        final q = TodoQuery(
          filter: filter,
          listId: query.listId,
          unlisted: query.unlisted,
        );
        final was = q.admitsOpen(todo, today);
        final now = q.admitsOpen(to, today);
        if (was != now) {
          counts[filter] = math.max(0, counts[filter]! + (now ? 1 : -1));
        }
      }
      if (todo.overdue != to.overdue) overdue += to.overdue ? 1 : -1;
    }
    final finished = query.filter == 'done' || query.filter == 'cancelled';
    if (finished || !todo.isOpen || query.admitsOpen(to, today)) out.add(to);
  }
  return TodosBundle(
    todos: out,
    openCount: bundle.openCount,
    overdueCount: overdue < 0 ? 0 : overdue,
    totalCount: bundle.totalCount,
    counts: counts,
  );
}

/// Shows [moved] on every todo list on screen at once (the Agenda's views
/// and their chip counts) until the writes are answered and refetched.
List<PendingEdit<TodosBundle>> _showMoved(
  ProviderContainer container,
  Map<int, Todo> moved,
  DateTime today,
) {
  final edits = <PendingEdit<TodosBundle>>[];
  for (final instance
      in container.allProviders(family: todosProvider).toList()) {
    final query = instance.provider.argument;
    if (query is! TodoQuery) continue;
    final model = todosProvider(query);
    if (!container.exists(model)) continue;
    final listed = container.read(model).value?.data.todos ?? const <Todo>[];
    if (!listed.any((t) => moved.containsKey(t.id))) continue;
    edits.add(
      container
          .read(model.notifier)
          .patch((b) => _movedIn(b, query, moved, today)),
    );
  }
  return edits;
}

/// Moves [todos] to [day] (null: takes their dates away) — "Yarın" and
/// "Bugün" on a row, the swipe to the left, "Hepsini bugüne al" — on screen
/// at once, then sends each (`PATCH /todos/:id` with `due_date` and
/// `due_time`). Each keeps its time of day, unless that time is already
/// past on [day]: then it is due on the day alone, so moving an overdue
/// todo to today does not leave it overdue.
///
/// The snackbar says [message] and offers "Geri al", one for them all, which
/// writes back the day and time each had. Should a write fail, every todo
/// goes back where it was and the snackbar says why. With [ghost], the rows
/// leaving a list collapse where they were (a chip, a menu); a swipe folds
/// its row itself — it awaits the result: true once saved, false when the
/// write failed (the row then slides back).
Future<bool> moveTodos(
  BuildContext context,
  WidgetRef ref,
  List<Todo> todos, {
  required DateTime? day,
  required String message,
  bool ghost = false,
}) async {
  if (todos.isEmpty) return true;
  final l = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = ref.read(repositoryProvider);
  final sync = ref.read(dataSyncProvider);
  final now = ref.read(clockProvider)();
  final today = accountToday(ref);
  final target = day == null ? null : dateOnly(day);
  final landings = {for (final t in todos) t.id: _landing(t, target, now)};
  final moved = {
    for (final t in todos)
      t.id: _withDue(t, landings[t.id]!.day, landings[t.id]!.time, now),
  };
  if (ghost) {
    for (final t in todos) {
      sync.noteChange(DataScope.todos, t.id, ChangeKind.removed);
    }
  }
  final edits = _showMoved(container, moved, today);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Future.wait([
      for (final t in todos)
        repo.rescheduleTodo(
          t.id,
          landings[t.id]!.day,
          time: landings[t.id]!.time,
          keepTime: landings[t.id]!.keep,
        ),
    ]);
    for (final edit in edits) {
      edit.confirm();
    }
    for (final t in todos) {
      sync.noteChange(DataScope.todos, t.id, ChangeKind.updated);
    }
    if (!context.mounted) return true;
    showAppSnack(
      context,
      message,
      actionLabel: l.actionUndo,
      onAction: () => _moveBack(container, ref, messenger, l, todos, now),
    );
    return true;
  } catch (e) {
    for (final edit in edits) {
      edit.rollback();
    }
    if (!context.mounted) return false;
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.todoSaveFailed),
      isError: true,
    );
    return false;
  }
}

/// "Geri al" of [moveTodos]: each of [before] back on the day and at the
/// time it had — on screen at once, then sent.
Future<void> _moveBack(
  ProviderContainer container,
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppL10n l,
  List<Todo> before,
  DateTime now,
) async {
  final repo = container.read(repositoryProvider);
  final sync = container.read(dataSyncProvider);
  final today = dateOnly(
    container.read(homeProvider).value?.data.today ??
        container.read<DateTime>(currentDayProvider),
  );
  final back = {
    for (final t in before) t.id: _withDue(t, t.dueDay, t.dueTime, now),
  };
  final edits = _showMoved(container, back, today);
  try {
    await Future.wait([
      for (final t in before)
        repo.rescheduleTodo(t.id, t.dueDay, time: t.dueTime),
    ]);
    for (final edit in edits) {
      edit.confirm();
    }
    for (final t in before) {
      sync.noteChange(DataScope.todos, t.id, ChangeKind.restored);
    }
  } catch (e) {
    for (final edit in edits) {
      edit.rollback();
    }
    if (messenger.mounted) {
      showAppSnack(
        messenger.context,
        failureMessage(e, l, fallback: l.todoSaveFailed),
        isError: true,
      );
    }
  }
}

/// Asks for a day (the date picker) and moves [todo] there, with "Geri al".
Future<void> pickTodoDay(BuildContext context, WidgetRef ref, Todo todo) async {
  final today = accountToday(ref);
  final picked = await showDatePicker(
    context: context,
    initialDate: todo.dueDay ?? today,
    firstDate: DateTime(today.year - 5),
    lastDate: DateTime(today.year + 10),
  );
  if (picked == null || !context.mounted) return;
  final l = context.l10n;
  final day = dateOnly(picked);
  await moveTodos(
    context,
    ref,
    [todo],
    day: day,
    message: day == today
        ? l.todoMovedToday(todo.title)
        : l.todoMovedOn(
            todo.title,
            formatDate(day, withYear: day.year != today.year),
          ),
    ghost: true,
  );
}

/// Sets [todo]'s priority (the long-press menu's "Öncelik").
Future<void> setTodoPriority(
  BuildContext context,
  WidgetRef ref,
  Todo todo,
  String priority,
) async {
  if (priority == todo.priority) return;
  final l = context.l10n;
  try {
    await ref
        .read(repositoryProvider)
        .updateTodo(
          todo,
          TodoInput(
            title: todo.title,
            body: todo.body,
            priority: priority,
            dueDate: todo.dueDay,
            dueTime: todo.dueTime,
            listId: todo.todoList?.id,
            goalId: todo.goalId,
          ),
        );
    ref
        .read(dataSyncProvider)
        .noteChange(DataScope.todos, todo.id, ChangeKind.updated);
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.todoSaveFailed),
      isError: true,
    );
  }
}

/// The long-press menu of a todo row (§6.4): edit, tick off or reopen,
/// move to tomorrow, pick a day, set the priority (a step inside this
/// sheet, never a sheet over it), delete. [done] is the checked state on
/// screen; [index] its place in the list it was pressed in.
Future<void> showTodoMenu(
  BuildContext context,
  WidgetRef ref,
  Todo todo, {
  required bool done,
  int index = 0,
}) async {
  final choice = await showNokSheet<_MenuChoice>(
    context,
    builder: (_) => _TodoMenu(todo: todo, done: done),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _MenuChoice(action: 'edit'):
      await openTodoSheet(context, existing: todo);
    case _MenuChoice(action: 'toggle'):
      await setTodoDone(context, ref, todo, done: !done, index: index);
    case _MenuChoice(action: 'postpone'):
      await postponeTodo(context, ref, todo);
    case _MenuChoice(action: 'date'):
      await pickTodoDay(context, ref, todo);
    case _MenuChoice(action: 'priority', :final priority?):
      await setTodoPriority(context, ref, todo, priority);
    case _MenuChoice(action: 'delete'):
      deleteTodoWithUndo(context, ref, todo);
    default:
      break;
  }
}

/// What was picked in [_TodoMenu].
typedef _MenuChoice = ({String action, String? priority});

class _TodoMenu extends StatefulWidget {
  final Todo todo;
  final bool done;

  const _TodoMenu({required this.todo, required this.done});

  @override
  State<_TodoMenu> createState() => _TodoMenuState();
}

class _TodoMenuState extends State<_TodoMenu> {
  bool _priorities = false;

  void _pick(String action, {String? priority}) => Navigator.of(
    context,
  ).pop<_MenuChoice>((action: action, priority: priority));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final todo = widget.todo;
    final done = widget.done;

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
      Widget? trailing,
    }) => ListTile(
      leading: Icon(icon, color: color ?? c.inkMid),
      title: Text(label, style: color == null ? null : TextStyle(color: color)),
      trailing: trailing,
      onTap: onTap,
    );

    final main = Column(
      key: const ValueKey('menu'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: todo.title),
        item(Icons.edit_outlined, l.actionEdit, () => _pick('edit')),
        item(
          done ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
          done ? l.todoReopen : l.todoComplete,
          () => _pick('toggle'),
        ),
        if (!done) ...[
          item(Icons.event_rounded, l.todoPostpone, () => _pick('postpone')),
          item(
            Icons.edit_calendar_outlined,
            l.todoDuePick,
            () => _pick('date'),
          ),
          item(
            Icons.flag_outlined,
            l.todoFieldPriority,
            () => setState(() => _priorities = true),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.todoPriority(todo.priority),
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
                Icon(Icons.chevron_right_rounded, color: c.inkMid),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.sm),
        item(
          Icons.delete_outline_rounded,
          l.actionDelete,
          () => _pick('delete'),
          color: c.error,
        ),
        const SizedBox(height: Gap.sm),
      ],
    );

    final priorities = Column(
      key: const ValueKey('priority'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Gap.xs),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => setState(() => _priorities = false),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(l.todoFieldPriority, style: text.titleLarge),
                ),
              ),
            ],
          ),
        ),
        for (final p in todoPriorities.reversed)
          ListTile(
            leading: SizedBox(
              width: 24,
              child: Center(
                child: Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: todoPriorityColor(c, p) ?? c.inkDisabled,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ),
            title: Text(
              l.todoPriority(p),
              style: p == todo.priority ? TextStyle(color: c.gold) : null,
            ),
            trailing: p == todo.priority
                ? Icon(Icons.check_rounded, color: c.gold)
                : null,
            selected: p == todo.priority,
            onTap: () => _pick('priority', priority: p),
          ),
        const SizedBox(height: Gap.sm),
      ],
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: SheetStepSwitcher(
          reverse: !_priorities,
          // The switch's fill paints under the rows: they ink on their own
          // Material.
          child: Material(
            key: ValueKey(_priorities),
            type: MaterialType.transparency,
            child: _priorities ? priorities : main,
          ),
        ),
      ),
    );
  }
}
