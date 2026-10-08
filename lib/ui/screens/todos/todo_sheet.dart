import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/goal.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../today/widgets/today_common.dart';

/// The longest todo title the server takes.
const todoTitleMaxLength = 200;

/// The longest todo list name the server takes.
const todoListNameMaxLength = 60;

/// Opens the todo sheet — a new todo, or [existing] to edit — and resolves
/// to the todo as the server saved it (the last one, after "Kaydet ve
/// yeni"), or null when it was closed without saving.
///
/// A new todo starts due on [due] (none: no date) and in [listId], so it
/// lands where it was added: Today's "Görev ekle" makes it due today, the
/// Todos screen's button follows its filter and list.
Future<Todo?> openTodoSheet(
  BuildContext context, {
  Todo? existing,
  DateTime? due,
  int? listId,
}) {
  return showModalBottomSheet<Todo>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // A drag would close it past the unsaved-changes question: closing goes
    // through the X, the back gesture or the scrim, which all ask.
    enableDrag: false,
    showDragHandle: false,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => TodoSheet(existing: existing, due: due, listId: listId),
  );
}

class TodoSheet extends ConsumerStatefulWidget {
  final Todo? existing;
  final DateTime? due;
  final int? listId;

  const TodoSheet({super.key, this.existing, this.due, this.listId});

  @override
  ConsumerState<TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends ConsumerState<TodoSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _notes = TextEditingController(text: widget.existing?.body);
  final _titleFocus = FocusNode();

  late DateTime? _day = widget.existing == null
      ? (widget.due == null ? null : dateOnly(widget.due!))
      : widget.existing!.dueDay;
  late String? _time = widget.existing?.dueTime;
  late String _priority = widget.existing?.priority ?? 'medium';
  late int? _listId = widget.existing?.todoList?.id ?? widget.listId;
  late int? _goalId = widget.existing?.goalId;

  /// Lists made from this sheet, until the lists refetch names them.
  final _madeLists = <TodoList>[];

  /// The last todo saved by "Kaydet ve yeni", returned when the sheet
  /// closes.
  Todo? _savedAndNew;

  bool _saving = false;
  String? _titleError;
  String? _dueError;
  String? _formError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Every keystroke can make the sheet dirty, which decides whether
    // leaving asks first.
    _title.addListener(() => setState(() => _titleError = null));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  DateTime get _today => dateOnly(
      ref.read(homeProvider).value?.data.today ??
      ref.read<DateTime>(currentDayProvider));

  TodoInput get _input => TodoInput(
        title: _title.text,
        body: _notes.text,
        priority: _priority,
        dueDate: _day,
        dueTime: _day == null ? null : _time,
        listId: _listId,
        goalId: _goalId,
      );

  bool get _dirty {
    final existing = widget.existing;
    if (existing != null) return _input.changesFrom(existing).isNotEmpty;
    return _title.text.trim().isNotEmpty || _notes.text.trim().isNotEmpty;
  }

  Future<void> _close() async {
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop(_savedAndNew);
    }
  }

  Future<void> _pickDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = dateOnly(picked);
      _dueError = null;
    });
  }

  Future<void> _pickTime() async {
    final current = parseDueTime(_time);
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time = dueTimeOf(picked.hour, picked.minute);
      _dueError = null;
    });
  }

  /// "＋ Yeni liste": a name in a dialog (never a sheet on this sheet); the
  /// colour rotates through the swatches. The new list is chosen.
  Future<void> _newList(int existingLists) async {
    final l = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewListDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final list = await ref.read(repositoryProvider).createTodoList(
            TodoListInput(
              name: name,
              color: rotatingSwatch(existingLists + _madeLists.length),
            ),
          );
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _madeLists.add(list);
        _listId = list.id;
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.todoListSaveFailed),
        isError: true,
      );
    }
  }

  /// Saves; with [andNew], clears the sheet for the next todo (keeping its
  /// day, list and priority) instead of closing it.
  Future<void> _save({bool andNew = false}) async {
    final l = context.l10n;
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      Haptics.danger();
      setState(() => _titleError = l.todoTitleRequired);
      _titleFocus.requestFocus();
      return;
    }
    final input = _input;
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
      _dueError = null;
    });
    try {
      // The repository reports the write: Today, every todo list and the
      // list counts refresh from that, even if this sheet is closed first.
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createTodo(input)
          : await repo.updateTodo(existing, input);
      if (!mounted) return;
      Haptics.success();
      if (andNew) {
        showAppSnack(context, l.todoCreated(saved.title));
        setState(() {
          _saving = false;
          _savedAndNew = saved;
          _title.clear();
          _notes.clear();
          _goalId = null;
        });
        _titleFocus.requestFocus();
        return;
      }
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.todoCreated(saved.title) : l.todoUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      final titleError = refusal?.fieldMessage(l, 'title');
      final dueError = switch (refusal?.param) {
            'due_date' || 'due_time' || 'due_at' => refusal!.localized(l),
            _ => null,
          } ??
          refusal?.fieldMessage(l, 'due_date') ??
          refusal?.fieldMessage(l, 'due_time') ??
          refusal?.fieldMessage(l, 'due_at');
      final placed = titleError != null || dueError != null;
      setState(() {
        _saving = false;
        _titleError = titleError;
        _dueError = dueError;
        _formError =
            placed ? null : failureMessage(e, l, fallback: l.todoSaveFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final today = _today;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final lists = [
      ...?ref.watch(todoListsProvider).value?.data.lists,
      for (final made in _madeLists)
        if (!(ref.read(todoListsProvider).value?.data.lists ?? const [])
            .any((list) => list.id == made.id))
          made,
    ];
    final goals = ref.watch(goalsProvider).value?.data;

    // The due chips: today, tomorrow, another day (its date once picked),
    // none.
    final day = _day;
    final dueChoice = day == null
        ? 'none'
        : day == today
            ? 'today'
            : day == tomorrow
                ? 'tomorrow'
                : 'pick';

    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: _close,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _isEdit ? l.todoEditTitle : l.todoNewTitle,
                        style: text.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _title,
                        focusNode: _titleFocus,
                        autofocus: !_isEdit,
                        maxLength: todoTitleMaxLength,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          labelText: l.todoFieldTitle,
                          errorText: _titleError,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FormLabel(l.todoFieldDue),
                      ChoiceWrap<String>(
                        choices: [
                          Choice('today', l.dayToday),
                          Choice('tomorrow', l.dayTomorrow),
                          Choice(
                            'pick',
                            dueChoice == 'pick'
                                ? formatDate(day!, withYear: day.year != today.year)
                                : l.todoDuePick,
                            icon: Icons.calendar_today_outlined,
                          ),
                          Choice('none', l.labelNone),
                        ],
                        selected: dueChoice,
                        onChanged: (choice) {
                          switch (choice) {
                            case 'today':
                              setState(() => _day = today);
                            case 'tomorrow':
                              setState(() => _day = tomorrow);
                            case 'pick':
                              _pickDate();
                            case 'none':
                              setState(() => _day = null);
                          }
                          if (_dueError != null) {
                            setState(() => _dueError = null);
                          }
                        },
                      ),
                      // Picking "another day" again opens the calendar.
                      if (dueChoice == 'pick')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.edit_calendar_outlined,
                                size: 18),
                            label: Text(l.todoDuePick),
                          ),
                        ),
                      if (day != null) _timeRow(context),
                      if (_dueError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _dueError!,
                            style: text.bodySmall!.copyWith(color: c.error),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FormLabel(l.todoFieldPriority),
                      ChoiceWrap<String>(
                        choices: [
                          for (final p in todoPriorities)
                            Choice(
                              p,
                              l.todoPriority(p),
                              color: p == 'low'
                                  ? c.inkLow
                                  : priorityEdgeColor(c, p),
                            ),
                        ],
                        selected: _priority,
                        onChanged: (p) => setState(() => _priority = p),
                      ),
                      const SizedBox(height: 16),
                      FormLabel(l.todoFieldList),
                      _listChoices(context, lists),
                      if (goals != null &&
                          (goals.active.isNotEmpty || _goalId != null)) ...[
                        const SizedBox(height: 16),
                        FormLabel(l.todoFieldGoal),
                        _goalChoices(context, goals),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: _notes,
                        minLines: 2,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: l.todoFieldNotes,
                          alignLabelWithHint: true,
                        ),
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
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      label: l.actionSave,
                      loading: _saving,
                      onPressed: _save,
                    ),
                    if (!_isEdit)
                      TextButton(
                        onPressed: _saving ? null : () => _save(andNew: true),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(l.todoSaveAndNew),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Saat ekle", or the time with a way to take it off (a date-only due).
  Widget _timeRow(BuildContext context) {
    final l = context.l10n;
    final c = context.nok;
    final time = _time;
    if (time == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(l.todoAddTime),
        ),
      );
    }
    return Row(
      children: [
        TextButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(time),
        ),
        IconButton(
          onPressed: () => setState(() => _time = null),
          tooltip: l.todoRemoveTime,
          icon: Icon(Icons.close, size: 18, color: c.inkMid),
        ),
      ],
    );
  }

  Widget _listChoices(BuildContext context, List<TodoList> lists) {
    final l = context.l10n;
    final c = context.nok;
    final existingRef = widget.existing?.todoList;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceWrap<int>(
          choices: [
            Choice(-1, l.todoNoList),
            for (final list in lists)
              Choice(list.id, list.name,
                  color: hexColor(list.color, fallback: c.inkLow)),
            // An archived list (not offered) the todo is still in.
            if (existingRef != null &&
                !lists.any((list) => list.id == existingRef.id))
              Choice(existingRef.id, existingRef.name,
                  color: hexColor(existingRef.color, fallback: c.inkLow)),
          ],
          selected: _listId ?? -1,
          onChanged: (id) => setState(() => _listId = id < 0 ? null : id),
        ),
        TextButton.icon(
          onPressed: () => _newList(lists.length),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l.todoListNew),
        ),
      ],
    );
  }

  Widget _goalChoices(BuildContext context, GoalsBundle goals) {
    final l = context.l10n;
    final c = context.nok;
    final linked = _goalId;
    final known = [...goals.active, ...goals.achieved, ...goals.abandoned];
    return ChoiceWrap<int>(
      choices: [
        Choice(-1, l.labelNone),
        for (final goal in goals.active)
          Choice(goal.id, goal.name,
              color: hexColor(goal.color, fallback: c.gold)),
        // A goal no longer active (or not listed) it is still linked to.
        if (linked != null && !goals.active.any((g) => g.id == linked))
          Choice(
            linked,
            known.where((g) => g.id == linked).firstOrNull?.name ??
                l.todoGoalLinked,
          ),
      ],
      selected: _goalId ?? -1,
      onChanged: (id) => setState(() => _goalId = id < 0 ? null : id),
    );
  }
}

/// The priorities a todo can have, lowest first.
const todoPriorities = ['low', 'medium', 'high', 'urgent'];

/// Asks for a new list's name.
class _NewListDialog extends StatefulWidget {
  const _NewListDialog();

  @override
  State<_NewListDialog> createState() => _NewListDialogState();
}

class _NewListDialogState extends State<_NewListDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.todoListNameRequired);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.todoListNew),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: todoListNameMaxLength,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l.todoListName,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.actionSave)),
      ],
    );
  }
}
