import 'date_utils.dart';
import 'json_read.dart';

class TodoListRef {
  final int id;
  final String name;
  final String color;

  const TodoListRef({
    required this.id,
    required this.name,
    required this.color,
  });

  factory TodoListRef.fromJson(Map<String, dynamic> json) => TodoListRef(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#6B8FA0',
      );
}

class Todo {
  final int id;
  final String title;
  final String? body;
  final String status;
  final String priority;

  /// When it is due, as the account's wall clock (see [parseDateTime]).
  final DateTime? dueAt;

  /// The day it is due in the account's zone (`due_date`, G3); from [dueAt]
  /// on a server that does not send it.
  final DateTime? dueDate;

  /// `"HH:MM"` in the account's zone, or null for a todo due on a day
  /// without a time (`due_time`, G3).
  final String? dueTime;
  final bool overdue;
  final int position;
  final TodoListRef? todoList;
  final int subtaskCount;
  final DateTime? completedAt;

  /// The goal it is linked to (`goal_id`, G3); null when it is not.
  final int? goalId;

  const Todo({
    required this.id,
    required this.title,
    this.body,
    required this.status,
    required this.priority,
    this.dueAt,
    this.dueDate,
    this.dueTime,
    required this.overdue,
    required this.position,
    this.todoList,
    required this.subtaskCount,
    this.completedAt,
    this.goalId,
  });

  bool get isDone => status == 'done';

  /// Still to do: `pending` or `in_progress` (contract §9.1).
  bool get isOpen => status == 'pending' || status == 'in_progress';

  /// Due on a day without a time of day. The server keeps such a due at
  /// 23:59:59 of that day, so it is only overdue once the day is over; it is
  /// shown by its day alone, never as "23:59" (contract §9.1).
  bool get isDateOnly => dueDay != null && dueTime == null;

  /// The day it is due, for day labels ("Bugün", "5 Eki").
  DateTime? get dueDay {
    final day = dueDate ?? dueAt;
    return day == null ? null : DateTime(day.year, day.month, day.day);
  }

  /// Every todo payload, and the bare `{id, status, completed_at}` a server
  /// from before G1 answers `PATCH /todos/:id/toggle` with.
  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: readId(json['id']),
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        priority: (json['priority'] as String?) ?? 'medium',
        dueAt: parseDateTime(json['due_at']),
        dueDate: parseDateTime(json['due_date']),
        dueTime: json['due_time'] as String?,
        overdue: readBool(json['overdue']),
        position: readInt(json['position']),
        todoList: json['todo_list'] == null
            ? null
            : TodoListRef.fromJson(json['todo_list'] as Map<String, dynamic>),
        subtaskCount: readInt(json['subtask_count']),
        completedAt: parseDateTime(json['completed_at']),
        goalId: readIntOrNull(json['goal_id']),
      );

  Todo copyWith({String? status}) => Todo(
        id: id,
        title: title,
        body: body,
        status: status ?? this.status,
        priority: priority,
        dueAt: dueAt,
        dueDate: dueDate,
        dueTime: dueTime,
        overdue: overdue,
        position: position,
        todoList: todoList,
        subtaskCount: subtaskCount,
        completedAt: completedAt,
        goalId: goalId,
      );
}

class TodosBundle {
  final List<Todo> todos;
  final int openCount;
  final int overdueCount;

  /// The todos the query matches, across every page (`meta.total_count`).
  final int totalCount;

  /// How many todos each filter would list with the same list and priority
  /// (`meta.counts`, by filter name): the filter chips' badges. Empty from a
  /// server that does not send them.
  final Map<String, int> counts;

  const TodosBundle({
    required this.todos,
    required this.openCount,
    required this.overdueCount,
    this.totalCount = 0,
    this.counts = const {},
  });

  factory TodosBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    final todos = ((json['todos'] as List?) ?? const [])
        .map((e) => Todo.fromJson(e as Map<String, dynamic>))
        .toList();
    final counts = meta['counts'];
    return TodosBundle(
      todos: todos,
      openCount: readInt(meta['open_count']),
      overdueCount: readInt(meta['overdue_count']),
      totalCount: readInt(meta['total_count'], fallback: todos.length),
      counts: counts is Map
          ? {for (final e in counts.entries) '${e.key}': readInt(e.value)}
          : const {},
    );
  }

  TodosBundle _with(List<Todo> todos, {int openStep = 0, int overdueStep = 0}) {
    int moved(int value, int step) => value + step < 0 ? 0 : value + step;
    return TodosBundle(
      todos: todos,
      openCount: moved(openCount, openStep),
      overdueCount: moved(overdueCount, overdueStep),
      totalCount: totalCount,
      counts: counts,
    );
  }

  /// Todo [todoId] set to [status], left where it is listed (checked, until
  /// the refetch drops it from a list of open todos); the open and overdue
  /// counts move with it. Setting rather than toggling: a list that already
  /// has it at [status] is returned as it is. Unchanged when not listed.
  TodosBundle withTodoStatus(int todoId, String status) {
    final index = todos.indexWhere((t) => t.id == todoId);
    if (index < 0) return this;
    final todo = todos[index];
    if (todo.status == status) return this;
    final nowOpen = status == 'pending' || status == 'in_progress';
    final step = nowOpen == todo.isOpen ? 0 : (nowOpen ? 1 : -1);
    return _with(
      [...todos]..[index] = todo.copyWith(status: status),
      openStep: step,
      overdueStep: todo.overdue ? step : 0,
    );
  }

  /// [todo] reopened: set back to open where it is listed, or put back at
  /// [index] when a refetch already dropped it. Unchanged once it is listed
  /// open.
  TodosBundle withTodoReopened(Todo todo, {required int index}) {
    if (todos.any((t) => t.id == todo.id)) {
      return withTodoStatus(todo.id, 'pending');
    }
    return _with(
      [...todos]..insert(index.clamp(0, todos.length), todo.copyWith(status: 'pending')),
      openStep: 1,
      overdueStep: todo.overdue ? 1 : 0,
    );
  }

  /// [saved], as the server answered an edit, in place of the listed copy.
  /// Unchanged when it is not listed.
  TodosBundle withTodo(Todo saved) {
    final index = todos.indexWhere((t) => t.id == saved.id);
    if (index < 0) return this;
    return _with([...todos]..[index] = saved);
  }
}

/// A todo list (contract §8.1).
class TodoList {
  final int id;
  final String name;
  final String color;
  final int position;
  final bool archived;

  /// Its open (`pending` + `in_progress`) todos.
  final int openCount;

  /// Every todo in it, whatever its status: what deleting the list with its
  /// todos removes.
  final int todosCount;

  const TodoList({
    required this.id,
    required this.name,
    required this.color,
    this.position = 0,
    this.archived = false,
    this.openCount = 0,
    this.todosCount = 0,
  });

  factory TodoList.fromJson(Map<String, dynamic> json) => TodoList(
        id: readId(json['id']),
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#B8860B',
        position: readInt(json['position']),
        archived: readBool(json['archived']),
        openCount: readInt(json['open_count']),
        todosCount: readInt(json['todos_count']),
      );

  TodoListRef get ref => TodoListRef(id: id, name: name, color: color);
}

/// `GET /todo_lists`: the active lists, and how many open todos are in no
/// list (the "Inbox"). Read with `include_archived=true`, the archived ones
/// come apart in [archived] — never in [lists], which the pickers offer.
class TodoListsBundle {
  final List<TodoList> lists;
  final int unlistedOpenCount;
  final List<TodoList> archived;

  const TodoListsBundle({
    required this.lists,
    this.unlistedOpenCount = 0,
    this.archived = const [],
  });

  factory TodoListsBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    final all = ((json['todo_lists'] as List?) ?? const [])
        .map((e) => TodoList.fromJson(e as Map<String, dynamic>))
        .toList();
    return TodoListsBundle(
      lists: [for (final list in all) if (!list.archived) list],
      archived: [for (final list in all) if (list.archived) list],
      unlistedOpenCount: readInt(meta['unlisted_open_count']),
    );
  }
}

/// Create/update body for a todo list.
class TodoListInput {
  final String name;
  final String color;

  const TodoListInput({required this.name, required this.color});

  Map<String, dynamic> toJson() => {'name': name.trim(), 'color': color};

  /// Only what differs from [before] (contract §1.6: PATCH applies every key
  /// sent).
  Map<String, dynamic> changesFrom(TodoList before) => {
        if (name.trim() != before.name) 'name': name.trim(),
        if (color.toUpperCase() != before.color.toUpperCase()) 'color': color,
      };
}

/// Create/update body for a todo.
///
/// The due day and time are sent as `due_date` / `due_time` (contract §9),
/// never as an instant: a day without a time is a date-only due, which the
/// server keeps at the end of that day in the account's zone — so it is not
/// overdue while the day lasts.
class TodoInput {
  final String title;

  /// The notes; blank means none.
  final String? body;
  final String priority;

  /// The due day (its date only), or null for no due date.
  final DateTime? dueDate;

  /// `"HH:MM"` on [dueDate], or null for a date-only due. Ignored without a
  /// [dueDate].
  final String? dueTime;
  final int? listId;
  final int? goalId;

  const TodoInput({
    required this.title,
    this.body,
    this.priority = 'medium',
    this.dueDate,
    this.dueTime,
    this.listId,
    this.goalId,
  });

  String? get _notes {
    final text = body?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? get _time => dueDate == null ? null : dueTime;

  /// The body of `POST /todos`: what is set, nothing else.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        if (_notes != null) 'body': _notes,
        'priority': priority,
        if (dueDate != null) 'due_date': isoDate(dueDate!),
        if (_time != null) 'due_time': _time,
        if (listId != null) 'todo_list_id': listId,
        if (goalId != null) 'goal_id': goalId,
      };

  /// The body of `PATCH /todos/:id`: only what differs from [before], since
  /// the server applies every key sent — a `null` clears (contract §1.6).
  ///
  /// A new day is sent with its time (`null` for none), so the time is what
  /// the form shows rather than the one the todo had; a new time on the same
  /// day goes alone; no day clears both.
  Map<String, dynamic> changesFrom(Todo before) {
    final out = <String, dynamic>{};
    if (title.trim() != before.title) out['title'] = title.trim();
    final beforeNotes = (before.body?.trim().isEmpty ?? true) ? null : before.body;
    if (_notes != beforeNotes?.trim()) out['body'] = _notes;
    if (priority != before.priority) out['priority'] = priority;
    final day = dueDate == null ? null : dateOnly(dueDate!);
    final beforeDay = before.dueDay;
    if (day == null) {
      if (beforeDay != null) out['due_date'] = null;
    } else if (day != beforeDay) {
      out['due_date'] = isoDate(day);
      out['due_time'] = _time;
    } else if (_time != before.dueTime) {
      out['due_time'] = _time;
    }
    if (listId != before.todoList?.id) out['todo_list_id'] = listId;
    if (goalId != before.goalId) out['goal_id'] = goalId;
    return out;
  }
}

/// `"HH:MM"` (24 h, two-digit hour) — the wire format of `due_time`.
String dueTimeOf(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// The hour and minute of a `"HH:MM"` [dueTime]; null when it is not one.
({int hour, int minute})? parseDueTime(String? dueTime) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(dueTime?.trim() ?? '');
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}
