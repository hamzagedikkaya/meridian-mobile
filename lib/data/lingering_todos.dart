/// Todos that stay on screen a moment after they are checked off
/// (design-analysis §4.29, MUST).
///
/// Ticking a todo off refetches the open todos, and the refetch used to tear
/// the row out in the middle of its fill and pop — the list jumped 60 dp.
/// Now `TodoActions.setDone(done: true)` registers the todo here; Today and
/// the Agenda put the lingering ones back among the server's rows
/// ([mergeInto]), at their old place, done (struck through, inkLow).
///
/// [Motion.linger] after the **last** check (one timer) they all collapse
/// together ([LingeringState.collapsing]: 250 ms ease-in plus a 150 ms
/// fade), and then leave; the screen shows "n tamamlandı" in their place
/// ([LingeringState.finished]). Reopening one (a tap, "Geri al") takes it
/// out at once. A screen or tab left behind ([TickerMode] off, `dispose`)
/// calls [LingeringTodos.clear]: the list empties without motion.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/todo.dart';
import '../theme/app_motion.dart';

/// One lingering todo: the todo (done), where it was, when it was checked.
/// [index] is its place in the list it was ticked in; [places] its place in
/// each list on screen, by the list's key ([todayTodoList], or the Agenda's
/// `TodoQuery`): a list filtered by todo list, or the inbox, has its own
/// order, and the row lingers where it was in each.
typedef LingeringTodo = ({
  Todo todo,
  int index,
  DateTime at,
  Map<Object, int> places,
});

/// The key of Today's list (`/home`'s upcoming todos) in
/// [LingeringTodo.places].
const Object todayTodoList = #todayTodoList;

/// What is lingering, whether it is collapsing now, and how many collapsed
/// last time (the summary row's count).
final class LingeringState {
  const LingeringState({
    this.todos = const {},
    this.collapsing = false,
    this.done = const {},
  });

  final Map<int, LingeringTodo> todos;
  final bool collapsing;

  /// The todos that collapsed, finished, by id — what "n tamamlandı"
  /// counts. Reopening one takes it out.
  final Map<int, Todo> done;

  /// How many collapsed, finished, on every screen.
  int get finished => done.length;

  /// How many collapsed of those [admits] takes: a screen counts only what
  /// it would have listed.
  int finishedWhere(bool Function(Todo todo) admits) =>
      done.values.where(admits).length;

  bool get isEmpty => todos.isEmpty;
  bool contains(int id) => todos.containsKey(id);
}

final lingeringTodosProvider = NotifierProvider<LingeringTodos, LingeringState>(
  LingeringTodos.new,
);

final class LingeringTodos extends Notifier<LingeringState> {
  Timer? _linger;
  Timer? _collapse;

  /// Screens showing the lingering todos. With none, nothing lingers (and
  /// no timer runs); when the last one goes, the list empties.
  var _listeners = 0;

  @override
  LingeringState build() {
    ref.onDispose(_cancel);
    ref.onAddListener(() => _listeners++);
    ref.onRemoveListener(() {
      if (--_listeners > 0) return;
      _listeners = 0;
      _cancel();
      // Not while the tree that let go is being torn down.
      scheduleMicrotask(() {
        if (ref.mounted && _listeners == 0) clear();
      });
    });
    return const LingeringState();
  }

  void _cancel() {
    _linger?.cancel();
    _linger = null;
    _collapse?.cancel();
    _collapse = null;
  }

  /// [todo] was just checked off; it was at [index] in the list on screen,
  /// and at [places] in each list by its key. Restarts the one linger timer.
  void add(Todo todo, int index, {Map<Object, int> places = const {}}) {
    if (_listeners == 0) return;
    _collapse?.cancel();
    _collapse = null;
    state = LingeringState(
      todos: {
        ...state.todos,
        todo.id: (
          todo: todo.copyWith(status: 'done'),
          index: index,
          at: DateTime.now(),
          places: places,
        ),
      },
      done: state.done,
    );
    _linger?.cancel();
    _linger = Timer(Motion.linger, _startCollapse);
  }

  /// [id] was reopened: it leaves the lingering set at once — or, folded
  /// already, the finished count.
  void remove(int id) {
    if (!state.todos.containsKey(id)) {
      if (!state.done.containsKey(id)) return;
      state = LingeringState(
        todos: state.todos,
        collapsing: state.collapsing,
        done: {...state.done}..remove(id),
      );
      return;
    }
    final rest = {...state.todos}..remove(id);
    if (rest.isEmpty) _cancel();
    state = LingeringState(
      todos: rest,
      collapsing: state.collapsing && rest.isNotEmpty,
      done: state.done,
    );
  }

  void _startCollapse() {
    _linger = null;
    if (state.todos.isEmpty) return;
    state = LingeringState(
      todos: state.todos,
      collapsing: true,
      done: state.done,
    );
    _collapse = Timer(Motion.collapse, _finish);
  }

  void _finish() {
    _collapse = null;
    state = LingeringState(
      done: {
        ...state.done,
        for (final l in state.todos.values) l.todo.id: l.todo,
      },
    );
  }

  /// The screen was left: everything goes, without motion; the summary
  /// count resets too — unless [keepFinished] (a tab left behind): the
  /// rows lingering fold at once, without motion, into what was finished —
  /// a todo ticked a moment before the tab was left is done all the same —
  /// and that stays the day's, so a day whose every task is done still
  /// says so ("Hepsi tamam", §7.15) when the tab is shown again.
  void clear({bool keepFinished = false}) {
    _cancel();
    if (keepFinished) {
      if (state.isEmpty && !state.collapsing) return;
      _finish();
      return;
    }
    if (state.isEmpty && state.done.isEmpty) return;
    state = const LingeringState();
  }
}

/// [rows] (the server's open todos — of the list keyed [list], see
/// [LingeringTodo.places]) with [lingering] put back where they were in
/// it, done — rows the server still lists are left as they are.
List<Todo> mergeInto(List<Todo> rows, LingeringState lingering, {Object? list}) {
  if (lingering.isEmpty) return rows;
  final listed = {for (final t in rows) t.id};
  final out = [...rows];
  int at(LingeringTodo l) => l.places[list] ?? l.index;
  final missing =
      lingering.todos.values.where((l) => !listed.contains(l.todo.id)).toList()
        ..sort((a, b) => at(a).compareTo(at(b)));
  for (final l in missing) {
    out.insert(at(l).clamp(0, out.length), l.todo);
  }
  return out;
}
