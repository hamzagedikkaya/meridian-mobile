/// The Agenda's rows (design-analysis §7.4, §4.6, §4.28): a todo with its
/// swipes — → "Tamamla", ← "Yarın" — that moves only when this device just
/// changed it, and an inbox todo with its "Bugün" / "Yarın" chips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_scope.dart';
import '../../../data/recent_changes.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/agenda_rows.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/row_motion.dart';
import '../../widgets/swipe_action.dart';
import 'agenda_days.dart';
import 'todo_flows.dart';
import 'todo_sheet.dart';

/// The Agenda screen as its rows' actions need it: a context that outlives
/// a row — a row moved to tomorrow is rebuilt elsewhere, its own context
/// gone before the server answers — under the capture bar (so snackbars
/// float above it), and the screen's [ref].
class AgendaHost extends InheritedWidget {
  final BuildContext hostContext;
  final WidgetRef ref;

  const AgendaHost({
    super.key,
    required this.hostContext,
    required this.ref,
    required super.child,
  });

  static AgendaHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AgendaHost>();

  @override
  bool updateShouldNotify(AgendaHost old) => false;
}

/// A todo row of the Agenda.
///
/// * The checkbox ticks it off (an explicit state, with "Geri al") — or
///   reopens it: in the "Tamamlanan" view ([finishedView]) with "Geri al"
///   too.
/// * A tap opens its sheet; a long press its menu.
/// * → "Tamamla": the row slides back and its box fills; it then lingers,
///   struck through, with the rest of the ones just finished. On a done
///   todo → is "Yeniden aç".
/// * ← "Yarın": it moves to tomorrow (keeping its time) and leaves its place,
///   with "Geri al"; a move that fails slides it back. Not offered for a
///   todo already due tomorrow, nor a done one.
/// * [collapsing]: it lingered long enough, and folds away with the others.
///
/// [index] is its place in the flat list on screen: "Geri al" of a tick
/// puts it back there. [today] is the account's.
class AgendaTodoTile extends ConsumerWidget {
  final Todo todo;
  final int index;
  final DateTime today;
  final bool showList;
  final bool finishedView;
  final bool collapsing;

  /// Extra actions for screen readers (the inbox's day chips).
  final Map<String, VoidCallback> actions;

  /// Controls at the end of the row, or under it — they swipe with it.
  final Widget? trailing;
  final Widget? below;

  const AgendaTodoTile({
    super.key,
    required this.todo,
    required this.index,
    required this.today,
    this.showList = true,
    this.finishedView = false,
    this.collapsing = false,
    this.actions = const {},
    this.trailing,
    this.below,
  });

  @override
  Widget build(BuildContext rowContext, WidgetRef rowRef) {
    final c = rowContext.nok;
    final l = rowContext.l10n;
    final done = todo.isDone;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    // What the row starts outlives the row.
    final host = AgendaHost.maybeOf(rowContext);
    final context = host?.hostContext ?? rowContext;
    final ref = host?.ref ?? rowRef;

    void toggle() {
      if (finishedView && done) {
        reopenTodo(context, ref, todo);
      } else {
        setTodoDone(context, ref, todo, done: !done, index: index);
      }
    }

    final Widget line = TodoRow(
      key: ValueKey('todo-${todo.id}'),
      todo: todo,
      done: done,
      showList: showList,
      onToggle: toggle,
      onTap: () => openTodoSheet(context, existing: todo),
      onLongPress: () =>
          showTodoMenu(context, ref, todo, done: done, index: index),
      actions: {
        ...actions,
        l.actionDelete: () => deleteTodoWithUndo(context, ref, todo),
      },
    );
    final trailing = this.trailing;
    final below = this.below;
    // A swiped row carries its own background — the card's colour — so the
    // swipe's colour shows only where the row has moved away.
    // The wash paints on it, so it goes inside.
    final row = Material(
      color: c.surface1,
      child: RowMotion(
        record: (scope: DataScope.todos, id: todo.id),
        child: trailing != null
            ? Row(
                children: [
                  Expanded(child: line),
                  trailing,
                ],
              )
            : below != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [line, below],
              )
            : line,
      ),
    );

    // The same subtree whether the todo is open or done: a tick keeps the
    // row's State, so its box fills and its title strikes through in place
    // (§5.5), and a → swipe slides the row back rather than rebuilding it.
    // Done, → reopens it (as p24's did); ← is only for an open todo.
    final swipeable = SwipeAction(
      key: ValueKey('swipe-todo-${todo.id}'),
      startToEnd: SwipeSpec.complete(
        c,
        label: done ? l.todoReopen : l.todoComplete,
        onSwipe: () async {
          // The row slides back and its box fills (or empties); a todo
          // just finished then lingers.
          toggle();
          return false;
        },
      ),
      endToStart: done || finishedView || todo.dueDay == tomorrow
          ? null
          : SwipeSpec.postpone(
              c,
              label: l.dayTomorrow,
              // The row leaves only once the move is saved; a failed one
              // slides it back (the todo is put back where it was).
              onSwipe: () => moveTodos(
                context,
                ref,
                [todo],
                day: tomorrow,
                message: l.todoPostponed(todo.title),
              ),
            ),
      child: row,
    );

    if (!collapsing) return swipeable;
    return RowExit(onDone: () {}, child: swipeable);
  }
}

/// An inbox todo (no date yet): the row, and its "Bugün" and "Yarın" chips
/// — at the end of the row, or under it past 1.3× text — that give it that
/// day; it then leaves the inbox, folding away (§7.4).
class InboxTodoTile extends ConsumerWidget {
  final Todo todo;
  final int index;
  final DateTime today;
  final bool showList;
  final bool collapsing;

  const InboxTodoTile({
    super.key,
    required this.todo,
    required this.index,
    required this.today,
    this.showList = true,
    this.collapsing = false,
  });

  @override
  Widget build(BuildContext rowContext, WidgetRef rowRef) {
    final host = AgendaHost.maybeOf(rowContext);
    final context = host?.hostContext ?? rowContext;
    final ref = host?.ref ?? rowRef;
    final l = rowContext.l10n;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    void schedule(DateTime day) => moveTodos(
      context,
      ref,
      [todo],
      day: day,
      message: day == today
          ? l.todoMovedToday(todo.title)
          : l.todoPostponed(todo.title),
      ghost: true,
    );

    if (todo.isDone) {
      return AgendaTodoTile(
        todo: todo,
        index: index,
        today: today,
        showList: showList,
        collapsing: collapsing,
      );
    }

    // The row is one stop for a screen reader: the chips are its "Bugün"
    // action and its "Yarın" swipe, not stops of their own.
    Widget chip(String label, DateTime day) => ExcludeSemantics(
      child: NokChip(label: label, onTap: () => schedule(day)),
    );
    final chips = [chip(l.dayToday, today), chip(l.dayTomorrow, tomorrow)];
    // At the end of the row only where the title keeps room beside them
    // (a tablet); on a phone, or past 1.3× text, under the title.
    return LayoutBuilder(
      builder: (rowContext, constraints) => _layout(
        rowContext,
        chips,
        schedule,
        beside:
            constraints.maxWidth >= _besideWidth &&
            MediaQuery.textScalerOf(rowContext).scale(10) <= 13,
      ),
    );
  }

  /// The row width from which the chips sit beside the title.
  static const _besideWidth = 520.0;

  Widget _layout(
    BuildContext rowContext,
    List<Widget> chips,
    void Function(DateTime day) schedule, {
    required bool beside,
  }) {
    final l = rowContext.l10n;
    final large = !beside;
    return AgendaTodoTile(
      todo: todo,
      index: index,
      today: today,
      showList: showList,
      collapsing: collapsing,
      actions: {l.dayToday: () => schedule(today)},
      below: large
          ? Padding(
              padding: const EdgeInsets.fromLTRB(88, 0, Insets.rowH, Gap.xs),
              child: Wrap(spacing: Gap.sm, runSpacing: 0, children: chips),
            )
          : null,
      trailing: large
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  chips[0],
                  const SizedBox(width: Gap.sm),
                  chips[1],
                ],
              ),
            ),
    );
  }
}

/// The record a row of the agenda stands for: a todo by its id; an event
/// by its id and the day of the occurrence (a series shows on many days).
RecordKey agendaRecordOf(AgendaEntry entry) => switch (entry) {
  TodoEntry(:final todo) => (scope: DataScope.todos, id: todo.id),
  EventEntry(:final event, :final day) => (
    scope: DataScope.events,
    // Unique per occurrence; a delete hides the event by its own id.
    id:
        event.id * 100000 +
        DateTime.utc(
              day.year,
              day.month,
              day.day,
            ).difference(DateTime.utc(2000)).inDays %
            100000,
  ),
};
