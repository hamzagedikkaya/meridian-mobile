import 'date_utils.dart';

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
        id: json['id'] as int,
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
  final DateTime? dueAt;
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
    required this.overdue,
    required this.position,
    this.todoList,
    required this.subtaskCount,
    this.completedAt,
  });

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as int,
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        priority: (json['priority'] as String?) ?? 'medium',
        dueAt: parseDateTime(json['due_at']),
        overdue: (json['overdue'] as bool?) ?? false,
        position: (json['position'] as num?)?.toInt() ?? 0,
        todoList: json['todo_list'] == null
            ? null
            : TodoListRef.fromJson(json['todo_list'] as Map<String, dynamic>),
        subtaskCount: (json['subtask_count'] as num?)?.toInt() ?? 0,
        completedAt: parseDateTime(json['completed_at']),
      );

  /// PATCH /todos/:id/toggle returns only {id, status, completed_at}.
  factory Todo.fromToggle(Map<String, dynamic> json) => Todo(
        id: json['id'] as int,
        title: (json['title'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        priority: (json['priority'] as String?) ?? 'medium',
        overdue: (json['overdue'] as bool?) ?? false,
        position: (json['position'] as num?)?.toInt() ?? 0,
        subtaskCount: (json['subtask_count'] as num?)?.toInt() ?? 0,
        completedAt: parseDateTime(json['completed_at']),
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
      openCount: (meta['open_count'] as num?)?.toInt() ?? 0,
      overdueCount: (meta['overdue_count'] as num?)?.toInt() ?? 0,
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
