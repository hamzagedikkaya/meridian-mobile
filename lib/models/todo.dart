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
  });

  bool get isDone => status == 'done';

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
      );
}

class TodosBundle {
  final List<Todo> todos;
  final int openCount;
  final int overdueCount;

  const TodosBundle({
    required this.todos,
    required this.openCount,
    required this.overdueCount,
  });

  factory TodosBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    return TodosBundle(
      todos: ((json['todos'] as List?) ?? const [])
          .map((e) => Todo.fromJson(e as Map<String, dynamic>))
          .toList(),
      openCount: readInt(meta['open_count']),
      overdueCount: readInt(meta['overdue_count']),
    );
  }
}

/// Create/update body for a todo.
class TodoInput {
  final String title;
  final String? body;
  final String priority;
  final DateTime? dueAt;
  final int? listId;

  const TodoInput({
    required this.title,
    this.body,
    this.priority = 'medium',
    this.dueAt,
    this.listId,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'priority': priority,
        'due_at': dueAt?.toIso8601String(),
        'todo_list_id': listId,
      };
}
