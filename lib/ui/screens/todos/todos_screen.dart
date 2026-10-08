import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../today/widgets/today_common.dart';
import '../today/widgets/todo_row.dart';
import 'todo_flows.dart';
import 'todo_sheet.dart';

/// The filters the screen offers, in chip order (contract §9).
const todoScreenFilters = [
  'open',
  'today',
  'upcoming',
  'overdue',
  'undated',
  'done',
];

/// Every todo, by the server's filters — today, the next seven days,
/// overdue, without a date, finished — and by list (or in none).
///
/// A row's checkbox or a swipe to the right ticks it off (or reopens a
/// finished one: an explicit state, never a flip); a swipe to the left
/// deletes it, with "Geri al"; a tap edits it and a long press offers all
/// of these. Screen readers get each as an action of the row.
class TodosScreen extends ConsumerStatefulWidget {
  final String initialFilter;
  final int? initialListId;
  final bool initialUnlisted;

  const TodosScreen({
    super.key,
    this.initialFilter = 'open',
    this.initialListId,
    this.initialUnlisted = false,
  });

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  late TodoQuery _query = TodoQuery(
    filter: todoScreenFilters.contains(widget.initialFilter)
        ? widget.initialFilter
        : 'open',
    listId: widget.initialListId,
    unlisted: widget.initialUnlisted,
  );

  /// The chips' counts as last fetched — kept while another filter's first
  /// load is on its way, so the badges do not blink out.
  Map<String, int> _counts = const {};

  void _setQuery(TodoQuery query) {
    if (query == _query) return;
    Haptics.tick();
    setState(() => _query = query);
  }

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([todosProvider, todoListsProvider]);
    await settleRefresh(
      [refetchLanded(ref, todosProvider(_query))],
      minimum: const Duration(milliseconds: 500),
    );
  }

  void _retry() => ref.read(dataSyncProvider).refresh([todosProvider(_query)]);

  static bool _isNotFound(Object? error) =>
      error is ApiException && error.kind == ApiErrorKind.notFound;

  DateTime get _today => dateOnly(ref.read(homeProvider).value?.data.today ??
      ref.read<DateTime>(currentDayProvider));

  /// A new todo lands where it was added: due today or tomorrow under those
  /// filters, in the list shown.
  Future<void> _add() async {
    final today = _today;
    final due = switch (_query.filter) {
      'today' || 'overdue' => today,
      'upcoming' => DateTime(today.year, today.month, today.day + 1),
      _ => null,
    };
    await openTodoSheet(context, due: due, listId: _query.listId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final hidden = ref.watch(deferredDeletesProvider);
    final listsAsync = ref.watch(todoListsProvider);
    final fetchedLists = listsAsync.value?.data;
    // A list being deleted (its "Geri al" still up) is offered no more.
    final lists = fetchedLists == null
        ? null
        : TodoListsBundle(
            lists: withoutDeleted(
              fetchedLists.lists,
              hidden,
              DataScope.todoLists,
              (list) => list.id,
            ),
            unlistedOpenCount: fetchedLists.unlistedOpenCount,
          );
    // The list filtered by was deleted — on the lists page, or elsewhere
    // (the server then answers 404): back to every list, never an offline
    // banner over the deleted list's rows.
    final listId = _query.listId;
    if (listId != null &&
        lists != null &&
        !listsAsync.isLoading &&
        !lists.lists.any((list) => list.id == listId)) {
      _query = TodoQuery(filter: _query.filter);
    }
    var async = ref.watch(todosProvider(_query));
    if (_query.listId != null && _isNotFound(async.error)) {
      _query = TodoQuery(filter: _query.filter);
      async = ref.watch(todosProvider(_query));
    }
    final fetched = async.value;
    if (fetched != null && fetched.data.counts.isNotEmpty) {
      _counts = fetched.data.counts;
    }

    Widget body;
    if (fetched != null) {
      final todos = withoutDeleted(
        fetched.data.todos,
        hidden,
        DataScope.todos,
        (t) => t.id,
      );
      body = Column(
        children: [
          if (async.refreshFailed)
            OfflineBanner(lastUpdated: fetched.at, onRetry: _retry),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              onRefresh: _refresh,
              child: todos.isEmpty
                  ? _empty(context)
                  : _list(context, todos),
            ),
          ),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: l.todayTodosFailed,
        subtitle: l.errCheckWifi,
        actionLabel: l.actionRetry,
        onAction: _retry,
      );
    } else {
      body = const _TodosSkeleton();
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l.titleTodos),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: l.todoListsManage,
            onPressed: () => context.push('/todos/lists'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _add,
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        icon: const Icon(Icons.add),
        label: Text(l.todoAdd),
      ),
      body: Column(
        children: [
          _FilterBar(
            query: _query,
            counts: _counts,
            onChanged: (filter) => _setQuery(TodoQuery(
              filter: filter,
              listId: _query.listId,
              unlisted: _query.unlisted,
            )),
          ),
          if (lists != null &&
              (lists.lists.isNotEmpty || _query.listId != null))
            _ListBar(
              query: _query,
              lists: lists,
              onChanged: (listId, unlisted) => _setQuery(TodoQuery(
                filter: _query.filter,
                listId: listId,
                unlisted: unlisted,
              )),
            ),
          Expanded(
            child: SyncHint.over(active: async.isRefetching, child: body),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final l = context.l10n;
    // Scrollable, so pull-to-refresh still works on an empty list.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: EmptyState(
            icon: Icons.task_alt,
            title: l.todoFilterEmpty(_query.filter),
            actionLabel: _query.filter == 'done' ? null : l.todoAddInline,
            onAction: _add,
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<Todo> todos) {
    final groups = _groups(context.l10n, todos);
    final showList = _query.listId == null && !_query.unlisted;
    var index = 0;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_GroupHeader(group.label, overdue: group.overdue));
      final rows = <Widget>[];
      for (final todo in group.todos) {
        final at = index++;
        rows.add(_SwipeTodo(
          key: ValueKey('swipe-todo-${todo.id}'),
          todo: todo,
          index: at,
          showList: showList,
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: NokturnCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(children: _divided(context, rows)),
          ),
        ),
      ));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: children,
    );
  }

  List<Widget> _divided(BuildContext context, List<Widget> rows) {
    final c = context.nok;
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0)
          Divider(
            height: 1,
            thickness: 1,
            indent: 20,
            endIndent: 20,
            color: c.divider,
          ),
        rows[i],
      ],
    ];
  }

  /// The rows under day headings: overdue first, then each day, then those
  /// without a date; finished ones by the day they were finished.
  List<_Group> _groups(AppL10n l, List<Todo> todos) {
    final today = _today;
    if (_query.filter == 'done' || _query.filter == 'cancelled') {
      final byDay = <DateTime?, List<Todo>>{};
      for (final todo in todos) {
        final at = todo.completedAt;
        byDay.putIfAbsent(at == null ? null : dateOnly(at), () => []).add(todo);
      }
      return [
        for (final MapEntry(key: day, value: rows) in byDay.entries)
          _Group(day == null ? l.todoFilter(_query.filter) : dayHeading(l, day, today), rows),
      ];
    }
    final overdue = <Todo>[];
    final undated = <Todo>[];
    final byDay = <DateTime, List<Todo>>{};
    for (final todo in todos) {
      final day = todo.dueDay;
      // The server's flag, not the status: a row ticked off stays put
      // until the refetch drops it (only open todos are ever overdue).
      if (todo.overdue) {
        overdue.add(todo);
      } else if (day == null) {
        undated.add(todo);
      } else {
        byDay.putIfAbsent(day, () => []).add(todo);
      }
    }
    final days = byDay.keys.toList()..sort();
    return [
      if (overdue.isNotEmpty) _Group(l.todoGroupOverdue, overdue, overdue: true),
      for (final day in days) _Group(dayHeading(l, day, today), byDay[day]!),
      if (undated.isNotEmpty) _Group(l.todoGroupUndated, undated),
    ];
  }
}

/// "Bugün · 4 Ekim", "Yarın · 5 Ekim", "Salı · 6 Ekim" — a day's heading in
/// a list of todos or events.
String dayHeading(AppL10n l, DateTime day, DateTime today) {
  final withYear = day.year != today.year;
  final date = formatDate(day, withYear: withYear);
  final delta = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  if (delta >= -1 && delta <= 1) return '${l.relativeDay(day)} · $date';
  return '${formatWeekday(day)} · $date';
}

class _Group {
  final String label;
  final List<Todo> todos;
  final bool overdue;

  _Group(this.label, this.todos, {this.overdue = false});
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final bool overdue;

  const _GroupHeader(this.label, {this.overdue = false});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          label,
          style: text.labelMedium!.copyWith(
            color: overdue ? c.error : c.inkMid,
          ),
        ),
      ),
    );
  }
}

/// A todo row that a swipe to the right ticks off (or reopens) and a swipe
/// to the left deletes, with "Geri al". The swipes are also the row's
/// actions for screen readers, and in its long-press menu.
class _SwipeTodo extends ConsumerWidget {
  final Todo todo;
  final int index;
  final bool showList;

  const _SwipeTodo({
    required super.key,
    required this.todo,
    required this.index,
    required this.showList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final done = todo.isDone;
    void toggle() => setTodoDone(context, ref, todo, done: !done, index: index);
    void delete() => deleteTodoWithUndo(context, ref, todo);

    Widget background({
      required Color color,
      required IconData icon,
      required String label,
      required Alignment alignment,
    }) =>
        Container(
          color: color,
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c.bg),
              const SizedBox(width: 8),
              Text(label, style: text.labelLarge!.copyWith(color: c.bg)),
            ],
          ),
        );

    return Dismissible(
      key: key!,
      background: background(
        color: c.income,
        icon: done ? Icons.undo : Icons.check,
        label: done ? l.todoReopen : l.todoComplete,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: background(
        color: c.error,
        icon: Icons.delete_outline,
        label: l.actionDelete,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // The row stays, checked, until the refetch drops it.
          toggle();
          return false;
        }
        return true;
      },
      onDismissed: (_) => delete(),
      child: TodoRow(
        key: ValueKey('todo-${todo.id}'),
        todo: todo,
        done: done,
        showList: showList,
        onToggle: toggle,
        onTap: () => openTodoSheet(context, existing: todo),
        onLongPress: () =>
            showTodoMenu(context, ref, todo, done: done, index: index),
        actions: {
          if (!done) l.todoPostpone: () => postponeTodo(context, ref, todo),
          l.actionDelete: delete,
        },
      ),
    );
  }
}

/// The filter chips, each with how many todos it lists.
class _FilterBar extends StatelessWidget {
  final TodoQuery query;
  final Map<String, int> counts;
  final ValueChanged<String> onChanged;

  const _FilterBar({
    required this.query,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _ChipRow(
      children: [
        for (final filter in todoScreenFilters)
          _Chip(
            label: l.todoFilter(filter),
            count: filter == 'done' ? null : counts[filter],
            selected: query.filter == filter,
            alert: filter == 'overdue' && (counts[filter] ?? 0) > 0,
            onTap: () => onChanged(filter),
          ),
      ],
    );
  }
}

/// The list chips: every list, the todos in no list, and each list.
class _ListBar extends StatelessWidget {
  final TodoQuery query;
  final TodoListsBundle lists;
  final void Function(int? listId, bool unlisted) onChanged;

  const _ListBar({
    required this.query,
    required this.lists,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.nok;
    return _ChipRow(
      children: [
        _Chip(
          label: l.todoAllLists,
          selected: query.listId == null && !query.unlisted,
          onTap: () => onChanged(null, false),
        ),
        _Chip(
          label: l.todoNoList,
          count: lists.unlistedOpenCount,
          selected: query.unlisted,
          onTap: () => onChanged(null, true),
        ),
        for (final list in lists.lists)
          _Chip(
            label: list.name,
            count: list.openCount,
            color: hexColor(list.color, fallback: c.inkLow),
            selected: !query.unlisted && query.listId == list.id,
            onTap: () => onChanged(list.id, false),
          ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> children;

  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) {
    // Full width, so a short row starts at the edge rather than centred.
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: children),
      ),
    );
  }
}

/// A selectable pill with a count; a 48 dp target.
class _Chip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final bool alert;
  final Color? color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    this.count,
    required this.selected,
    this.alert = false,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final count = this.count;
    final fg = selected ? c.onGoldContainer : c.inkMid;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      // The InkWell's own tap is excluded with its semantics: the node
      // carries it, so switch access can change the filter too.
      onTap: selected ? null : onTap,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? c.goldContainer : c.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? c.goldContainer : c.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (color != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(label, style: text.labelLarge!.copyWith(color: fg)),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: text.labelSmall!.copyWith(
                          color: alert ? c.error : fg,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodosSkeleton extends StatelessWidget {
  const _TodosSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        children: [
          for (var i = 0; i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: c.skeletonBone,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.skeletonBone,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
