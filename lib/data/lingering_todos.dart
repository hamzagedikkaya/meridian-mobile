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
typedef LingeringTodo = ({Todo todo, int index, DateTime at});

/// What is lingering, whether it is collapsing now, and how many collapsed
/// last time (the summary row's count).
final class LingeringState {
  const LingeringState({
    this.todos = const {},
    this.collapsing = false,
    this.finished = 0,
  });

  final Map<int, LingeringTodo> todos;
  final bool collapsing;
  final int finished;

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

  /// [todo] was just checked off; it was at [index] in the list on screen.
  /// Restarts the one linger timer.
  void add(Todo todo, int index) {
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
        ),
      },
      finished: state.finished,
    );
    _linger?.cancel();
    _linger = Timer(Motion.linger, _startCollapse);
  }

  /// [id] was reopened: it leaves the lingering set at once.
  void remove(int id) {
    if (!state.todos.containsKey(id)) return;
    final rest = {...state.todos}..remove(id);
    if (rest.isEmpty) _cancel();
    state = LingeringState(
      todos: rest,
      collapsing: state.collapsing && rest.isNotEmpty,
      finished: state.finished,
    );
  }

  void _startCollapse() {
    _linger = null;
    if (state.todos.isEmpty) return;
    state = LingeringState(
      todos: state.todos,
      collapsing: true,
      finished: state.finished,
    );
    _collapse = Timer(Motion.collapse, _finish);
  }

  void _finish() {
    _collapse = null;
    state = LingeringState(finished: state.finished + state.todos.length);
  }

  /// The screen was left: everything goes, without motion; the summary
  /// count resets too.
  void clear() {
    _cancel();
    if (state.isEmpty && state.finished == 0) return;
    state = const LingeringState();
  }
}

/// [rows] (the server's open todos) with [lingering] put back where they
/// were, done — rows the server still lists are left as they are.
List<Todo> mergeInto(List<Todo> rows, LingeringState lingering) {
  if (lingering.isEmpty) return rows;
  final listed = {for (final t in rows) t.id};
  final out = [...rows];
  final missing =
      lingering.todos.values.where((l) => !listed.contains(l.todo.id)).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  for (final l in missing) {
    out.insert(l.index.clamp(0, out.length), l.todo);
  }
  return out;
}
