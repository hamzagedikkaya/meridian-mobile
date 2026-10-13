import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/goal.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/agenda_rows.dart' show todoPriorityColor;
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/segmented_pill.dart';
import 'agenda_days.dart' show pickerRange;
import 'todo_flows.dart' show deleteTodoWithUndo;

/// The longest todo title the server takes.
const todoTitleMaxLength = 200;

/// The longest todo list name the server takes.
const todoListNameMaxLength = 60;

/// The priorities a todo can have, lowest first.
const todoPriorities = ['low', 'medium', 'high', 'urgent'];

/// Opens the todo sheet (design-analysis §7.4) — a new todo, or [existing]
/// to edit — and resolves to the todo as the server saved it (the last
/// one, after "Kaydet ve yeni"), or null when it was closed without saving.
///
/// A new todo starts due on [due] (none: no date) and in [listId], so it
/// lands where it was added: Today's "Görev ekle" makes it due today, the
/// Agenda's day headings their day.
///
/// [context] is the screen's: an edit's "Sil" says "Geri al" there once the
/// sheet is closed.
Future<Todo?> openTodoSheet(
  BuildContext context, {
  Todo? existing,
  DateTime? due,
  int? listId,
}) {
  return showNokSheet<Todo>(
    context,
    // A drag would close it past the unsaved-changes question: closing goes
    // through the X, the back gesture or the scrim, which all ask.
    enableDrag: false,
    builder: (_) =>
        TodoSheet(existing: existing, due: due, listId: listId, host: context),
  );
}

/// The steps of the sheet: the todo, and the pickers that replace it while
/// open (never a sheet over this one, §4.15).
enum _Step { todo, list, newList, goal }

class TodoSheet extends ConsumerStatefulWidget {
  final Todo? existing;
  final DateTime? due;
  final int? listId;

  /// The screen the sheet was opened from: where a delete offers "Geri al".
  final BuildContext? host;

  const TodoSheet({super.key, this.existing, this.due, this.listId, this.host});

  @override
  ConsumerState<TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends ConsumerState<TodoSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _notes = TextEditingController(text: widget.existing?.body);
  final _listName = TextEditingController();
  final _titleFocus = FocusNode();

  late DateTime? _day = widget.existing == null
      ? (widget.due == null ? null : dateOnly(widget.due!))
      : widget.existing!.dueDay;
  late String? _time = widget.existing?.dueTime;
  late String _priority = widget.existing?.priority ?? 'medium';
  late int? _listId = widget.existing?.todoList?.id ?? widget.listId;
  late int? _goalId = widget.existing?.goalId;

  /// "Daha fazla" was opened: the notes show. Open from the start when the
  /// todo has some.
  late bool _more = (widget.existing?.body?.trim().isNotEmpty ?? false);

  _Step _step = _Step.todo;

  /// Whether the last step change went back (the slide runs the other way).
  bool _back = false;

  /// Lists made from this sheet, until the lists refetch names them.
  final _madeLists = <TodoList>[];
  String? _newListColor;

  /// The last todo saved by "Kaydet ve yeni", returned when the sheet
  /// closes.
  Todo? _savedAndNew;

  /// The todo step's form: back to its top after "Kaydet ve yeni", where
  /// the title and what was just added are.
  final _formScroll = ScrollController();

  bool _saving = false;
  bool _savingList = false;
  String? _titleError;
  String? _dueError;
  String? _formError;
  String? _listError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Every keystroke can make the sheet dirty, which decides whether
    // leaving asks first.
    _title.addListener(() => setState(() => _titleError = null));
    _listName.addListener(() => setState(() => _listError = null));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _listName.dispose();
    _titleFocus.dispose();
    _formScroll.dispose();
    super.dispose();
  }

  DateTime get _today => dateOnly(
    ref.read(homeProvider).value?.data.today ??
        ref.read<DateTime>(currentDayProvider),
  );

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

  void _go(_Step step) => setState(() {
    _back =
        step == _Step.todo || (step == _Step.list && _step == _Step.newList);
    _step = step;
  });

  Future<void> _close() async {
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop(_savedAndNew);
    }
  }

  Future<void> _pickDate() async {
    final today = _today;
    final initial = _day ?? today;
    final range = pickerRange(initial, today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: range.first,
      lastDate: range.last,
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

  /// "+ Yeni liste", in place of the list picker: a name and a colour (the
  /// next one in turn). The new list is chosen.
  Future<void> _createList(String color) async {
    final l = context.l10n;
    if (_savingList) return;
    if (_listName.text.trim().isEmpty) {
      Haptics.reject();
      setState(() => _listError = l.todoListNameRequired);
      return;
    }
    setState(() => _savingList = true);
    try {
      final list = await ref
          .read(repositoryProvider)
          .createTodoList(TodoListInput(name: _listName.text, color: color));
      if (!mounted) return;
      Haptics.confirm();
      setState(() {
        _savingList = false;
        _madeLists.add(list);
        _listId = list.id;
        _listName.clear();
        _newListColor = null;
      });
      _go(_Step.todo);
    } catch (e) {
      if (!mounted) return;
      final nameError = e is ApiException ? e.fieldMessage(l, 'name') : null;
      setState(() {
        _savingList = false;
        _listError =
            nameError ?? failureMessage(e, l, fallback: l.todoListSaveFailed);
      });
      Haptics.reject();
    }
  }

  /// Saves; with [andNew], clears the sheet for the next todo (keeping its
  /// day, list and priority) instead of closing it.
  Future<void> _save({bool andNew = false}) async {
    final l = context.l10n;
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      Haptics.reject();
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
      // The row grows in (or is washed) where it lands.
      ref
          .read(dataSyncProvider)
          .noteChange(
            DataScope.todos,
            saved.id,
            existing == null ? ChangeKind.inserted : ChangeKind.updated,
          );
      if (!mounted) return;
      Haptics.confirm();
      if (andNew) {
        // Said in the sheet, which stays up: a snackbar would be under it.
        setState(() {
          _saving = false;
          _savedAndNew = saved;
          _title.clear();
          _notes.clear();
          _goalId = null;
        });
        _titleFocus.requestFocus();
        // The form may have been scrolled down to its chips: back up to the
        // title and the line over it.
        if (_formScroll.hasClients) _formScroll.jumpTo(0);
        return;
      }
      // Said on the screen the sheet was opened from, above its capture
      // bar (a sheet's own context sees no bar: see `snackMarginFor`).
      final host = widget.host;
      Navigator.of(context).pop(saved);
      showAppSnack(
        host != null && host.mounted ? host : context,
        existing == null ? l.todoCreated(saved.title) : l.todoUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      final refusal = e is ApiException ? e : null;
      final titleError = refusal?.fieldMessage(l, 'title');
      final dueError =
          switch (refusal?.param) {
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
        _formError = placed
            ? null
            : failureMessage(e, l, fallback: l.todoSaveFailed);
      });
    }
  }

  /// "Sil" (an edit): the sheet closes and the todo goes, with "Geri al" on
  /// the screen it was opened from.
  void _delete() {
    final existing = widget.existing!;
    final host = widget.host;
    Navigator.of(context).pop();
    if (host != null && host.mounted) {
      deleteTodoWithUndo(host, ref, existing);
    }
  }

  List<TodoList> _lists() {
    final fetched = ref.watch(todoListsProvider).value?.data.lists ?? const [];
    return [
      ...fetched,
      for (final made in _madeLists)
        if (!fetched.any((list) => list.id == made.id)) made,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final Widget step = switch (_step) {
      _Step.todo => _todoStep(context),
      _Step.list => _listStep(context),
      _Step.newList => _newListStep(context),
      _Step.goal => _goalStep(context),
    };
    return PopScope<Object?>(
      canPop: _step == _Step.todo && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step != _Step.todo) {
          _go(_step == _Step.newList ? _Step.list : _Step.todo);
        } else {
          _close();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SheetStepSwitcher(
          reverse: _back,
          // The switch's fill paints under the rows: they ink on their own
          // Material.
          child: Material(
            key: ValueKey(_step),
            type: MaterialType.transparency,
            child: step,
          ),
        ),
      ),
    );
  }

  /// The todo itself: title, day and time, priority, list and goal, and —
  /// under "Daha fazla" — the notes; "Kaydet" (and "Kaydet ve yeni" for a
  /// new one, "Sil" for one being edited) at the bottom.
  Widget _todoStep(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final today = _today;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final lists = _lists();
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

    final list = _listId == null
        ? null
        : lists.where((x) => x.id == _listId).firstOrNull?.ref ??
              (widget.existing?.todoList?.id == _listId
                  ? widget.existing?.todoList
                  : null);
    final goalName = _goalId == null
        ? null
        : [
                ...?goals?.active,
                ...?goals?.achieved,
                ...?goals?.abandoned,
              ].where((g) => g.id == _goalId).firstOrNull?.name ??
              l.todoGoalLinked;
    final showGoals =
        goals != null && (goals.active.isNotEmpty || _goalId != null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: _isEdit ? l.todoEditTitle : l.todoNewTitle,
          showClose: true,
          onClose: _close,
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _formScroll,
            // Room above the title field for its floating label.
            padding: const EdgeInsets.fromLTRB(
              Insets.sheetH,
              Gap.sm,
              Insets.sheetH,
              Gap.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_savedAndNew case final added? when _formError == null)
                  // "Kaydet ve yeni": the todo just added, said right over
                  // the title field the focus went back to — in sight with
                  // the keyboard up, where the end of the form is not.
                  Padding(
                    key: const ValueKey('todo-saved-and-new'),
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          Icon(Icons.check_rounded, size: 18, color: c.income),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              l.todoCreated(added.title),
                              style: text.bodyMedium!.copyWith(color: c.inkMid),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                const SizedBox(height: Gap.lg),
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
                if (day != null) _timeRow(context, dueChoice == 'pick'),
                FormInlineError(_dueError, gap: Gap.xs),
                const SizedBox(height: Gap.lg),
                FormLabel(l.todoFieldPriority),
                _priorityPicker(context),
                const SizedBox(height: Gap.lg),
                FormPickerRow(
                  icon: Icons.format_list_bulleted_rounded,
                  label: l.todoFieldList,
                  value: list?.name ?? l.todoNoList,
                  color: list == null ? null : entityTone(list.color, c).fill,
                  onTap: () => _go(_Step.list),
                ),
                if (showGoals) ...[
                  const SizedBox(height: Gap.sm),
                  FormPickerRow(
                    icon: Icons.flag_outlined,
                    label: l.todoFieldGoal,
                    value: goalName ?? l.labelNone,
                    onTap: () => _go(_Step.goal),
                  ),
                ],
                const SizedBox(height: Gap.md),
                if (_more)
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
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _more = true),
                      icon: const Icon(Icons.expand_more_rounded, size: 20),
                      label: Text(l.todoMoreFields),
                    ),
                  ),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _formError!,
                        style: text.bodyMedium!.copyWith(color: c.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SheetActions(
          primary: Column(
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
                    minimumSize: const Size.fromHeight(Hit.min),
                  ),
                  child: Text(l.todoSaveAndNew),
                ),
            ],
          ),
          destructive: !_isEdit
              ? null
              : TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(Hit.min),
                  ),
                  child: Text(l.actionDelete),
                ),
        ),
      ],
    );
  }

  /// The priority: a segmented pill (§7.4) where its four segments fit
  /// the width; else — a phone's 320 dp, larger text — the same choice as
  /// chips that wrap, each with its priority's colour, so no label is cut.
  Widget _priorityPicker(BuildContext context) {
    final l = context.l10n;
    final c = context.nok;
    final options = [for (final p in todoPriorities) (p, l.todoPriority(p))];
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = Theme.of(
          context,
        ).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);
        var widest = 0.0;
        for (final (_, label) in options) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          widest = math.max(widest, painter.width);
          painter.dispose();
        }
        // Each segment is its widest label + 32 dp; the rail adds 8.
        final fits = (widest + 32) * options.length + 8 <= constraints.maxWidth;
        if (fits) {
          return SegmentedPill<String>(
            expand: true,
            options: options,
            selected: _priority,
            onChanged: (p) => setState(() => _priority = p),
          );
        }
        return ChoiceWrap<String>(
          choices: [
            for (final (p, label) in options)
              Choice(p, label, color: todoPriorityColor(c, p) ?? c.inkDisabled),
          ],
          selected: _priority,
          onChanged: (p) => setState(() => _priority = p),
        );
      },
    );
  }

  /// The time chip: "Saat ekle", or the time with a way to take it off (a
  /// date-only due). With [repick], a way to pick another day as well.
  Widget _timeRow(BuildContext context, bool repick) {
    final l = context.l10n;
    final c = context.nok;
    final time = _time;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Wrap(
        spacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          NokChip(
            label: time ?? l.todoAddTime,
            icon: Icons.schedule_rounded,
            selected: time != null,
            onTap: _pickTime,
          ),
          if (time != null)
            IconButton(
              onPressed: () => setState(() => _time = null),
              tooltip: l.todoRemoveTime,
              icon: Icon(Icons.close_rounded, size: 18, color: c.inkMid),
            ),
          // Picking "another day" again opens the calendar.
          if (repick)
            NokChip(
              label: l.todoDuePick,
              icon: Icons.edit_calendar_outlined,
              onTap: _pickDate,
            ),
        ],
      ),
    );
  }

  /// A step's top: back to the todo, and the step's [title].
  Widget _stepHeader(BuildContext context, String title, VoidCallback back) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Insets.sheetH, Gap.sm),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: back,
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: text.titleLarge),
            ),
          ),
        ],
      ),
    );
  }

  /// One choice of a picker step: a colour dot or an icon, the label, an
  /// optional count, and a gold check on the chosen one.
  Widget _option(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? dot,
    IconData? icon,
    String? trailing,
  }) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return ListTile(
      selected: selected,
      selectedColor: c.gold,
      leading: icon != null
          ? Icon(icon, color: c.inkMid)
          : SizedBox(
              width: 24,
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: dot ?? Colors.transparent,
                    shape: BoxShape.circle,
                    border: dot == null
                        ? Border.all(color: c.inkDisabled)
                        : null,
                  ),
                ),
              ),
            ),
      title: Text(
        label,
        style: text.titleMedium!.copyWith(color: selected ? c.gold : null),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: text.bodySmall!.copyWith(color: c.inkMid)),
          if (selected) ...[
            const SizedBox(width: Gap.sm),
            Icon(Icons.check_rounded, color: c.gold, size: 20),
          ],
        ],
      ),
      onTap: () {
        Haptics.tick();
        onTap();
      },
    );
  }

  /// The list picker, in place of the todo: no list, each list (and an
  /// archived one the todo is still in), and "+ Yeni liste".
  Widget _listStep(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final lists = _lists();
    final existingRef = widget.existing?.todoList;
    void pick(int? id) {
      setState(() => _listId = id);
      _go(_Step.todo);
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(context, l.todoFieldList, () => _go(_Step.todo)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _option(
                  context,
                  label: l.todoNoList,
                  selected: _listId == null,
                  onTap: () => pick(null),
                ),
                for (final list in lists)
                  _option(
                    context,
                    label: list.name,
                    dot: entityTone(list.color, c).fill,
                    trailing: list.openCount > 0 ? '${list.openCount}' : null,
                    selected: _listId == list.id,
                    onTap: () => pick(list.id),
                  ),
                // An archived list (not offered) the todo is still in.
                if (existingRef != null &&
                    !lists.any((list) => list.id == existingRef.id))
                  _option(
                    context,
                    label: existingRef.name,
                    dot: entityTone(existingRef.color, c).fill,
                    selected: _listId == existingRef.id,
                    onTap: () => pick(existingRef.id),
                  ),
                _option(
                  context,
                  label: l.todoListNew,
                  icon: Icons.add_rounded,
                  selected: false,
                  onTap: () => _go(_Step.newList),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ),
    );
  }

  /// "+ Yeni liste": its name and colour, in place of the list picker.
  Widget _newListStep(BuildContext context) {
    final l = context.l10n;
    final color =
        _newListColor ??
        rotatingSwatch(
          (ref.read(todoListsProvider).value?.data.lists.length ?? 0) +
              _madeLists.length,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(context, l.todoListNew, () => _go(_Step.list)),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Insets.sheetH,
              Gap.sm,
              Insets.sheetH,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _listName,
                  autofocus: true,
                  maxLength: todoListNameMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _createList(color),
                  decoration: InputDecoration(
                    labelText: l.todoListName,
                    errorText: _listError,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: Gap.md),
                FormLabel(l.todoListColor),
                ColorSwatchRow(
                  selected: color,
                  onChanged: (hex) => setState(() => _newListColor = hex),
                ),
              ],
            ),
          ),
        ),
        SheetActions(
          primary: PrimaryButton(
            label: l.actionSave,
            loading: _savingList,
            onPressed: () => _createList(color),
          ),
        ),
      ],
    );
  }

  /// The goal picker, in place of the todo: none, each active goal, and a
  /// goal no longer active that the todo is still linked to.
  Widget _goalStep(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final goals = ref.watch(goalsProvider).value?.data;
    final linked = _goalId;
    final known = <Goal>[
      ...?goals?.active,
      ...?goals?.achieved,
      ...?goals?.abandoned,
    ];
    void pick(int? id) {
      setState(() => _goalId = id);
      _go(_Step.todo);
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(context, l.todoFieldGoal, () => _go(_Step.todo)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _option(
                  context,
                  label: l.labelNone,
                  selected: linked == null,
                  onTap: () => pick(null),
                ),
                for (final goal in goals?.active ?? const <Goal>[])
                  _option(
                    context,
                    label: goal.name,
                    dot: entityTone(goal.color, c).fill,
                    selected: linked == goal.id,
                    onTap: () => pick(goal.id),
                  ),
                if (linked != null &&
                    !(goals?.active.any((g) => g.id == linked) ?? false))
                  _option(
                    context,
                    label:
                        known.where((g) => g.id == linked).firstOrNull?.name ??
                        l.todoGoalLinked,
                    selected: true,
                    onTap: () => pick(linked),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ),
    );
  }
}
