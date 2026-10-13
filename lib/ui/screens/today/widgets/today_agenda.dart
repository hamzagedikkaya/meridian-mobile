import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api.dart';
import '../../../../core/haptics.dart';
import '../../../../data/current_day.dart';
import '../../../../data/data_scope.dart';
import '../../../../data/deferred_deletes.dart';
import '../../../../data/lingering_todos.dart';
import '../../../../data/providers.dart';
import '../../../../data/recent_changes.dart';
import '../../../../data/sync.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/event.dart';
import '../../../../models/todo.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../widgets/agenda_rows.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/nokturn_card.dart';
import '../../../widgets/row_motion.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/swipe_action.dart';
import '../../agenda/agenda_days.dart' show Occurrence, occurrencesIn;
import '../../agenda/event_sheet.dart';
import '../../agenda/todo_flows.dart';
import '../../agenda/todo_sheet.dart';
import 'today_clock.dart';
import 'today_common.dart';

/// Asks the Today card's add row to open and take the focus (the first-run
/// card's "İlk görevini ekle"): each request bumps the count.
final todayInlineAddProvider = NotifierProvider<TodayInlineAddRequests, int>(
  TodayInlineAddRequests.new,
);

class TodayInlineAddRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// One row of the Today card: a todo or an event's occurrence.
sealed class _Item {
  const _Item();
}

class _TodoItem extends _Item {
  const _TodoItem(this.todo);
  final Todo todo;
}

class _EventItem extends _Item {
  const _EventItem(this.occurrence, {required this.finished});
  final Occurrence occurrence;
  final bool finished;
}

/// The folded finished events ("+2 geçti").
class _PassedItem extends _Item {
  const _PassedItem(this.count);
  final int count;
}

/// The Today card (design-analysis §7.2.5): today's todos and events in one
/// list, in the order the day runs —
///
/// 1. overdue todos (their meta in error);
/// 2. all-day events;
/// 3. timed events and todos, by time — the events already over folded into
///    one "+2 geçti" row that opens on a tap;
/// 4. todos due today without a time.
///
/// At most six rows ("+N daha" leads to the Agenda). A row opens its sheet;
/// a todo's box ticks it off (undoable), and a ticked todo stays a moment
/// ([LingeringTodos]) before it folds into "n tamamlandı". A todo swipes
/// right to finish and left to tomorrow. The last row, "+ Bugün için görev
/// ekle", opens into a field in place: Enter adds a todo due today and
/// keeps the field.
///
/// Todos come from `/home` (overdue ones and today's; later days are on
/// the Agenda); events from today's `GET /events`, or `/home`'s until they
/// land.
class TodayAgendaSection extends ConsumerStatefulWidget {
  const TodayAgendaSection({super.key});

  /// The most rows the card lists.
  static const maxRows = 6;

  /// How many times the Today card was built: the rebuild test's counter.
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  ConsumerState<TodayAgendaSection> createState() => _TodayAgendaSectionState();
}

class _TodayAgendaSectionState extends ConsumerState<TodayAgendaSection> {
  bool _showPassed = false;

  /// Whether Today's tab was shown at the last look ([TickerMode]), and the
  /// day the card was showing: leaving either lets the lingering todos go.
  bool? _shown;
  DateTime? _day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    // The tab was left: what lingered (and "n tamamlandı") goes, without
    // motion (§4.29) — the card stays mounted behind the other tabs, so
    // [LingeringTodos] would never see its last listener leave.
    if (_shown == true && !shown) _clearLingering();
    _shown = shown;
  }

  /// Empties [LingeringTodos] once this frame is built (a provider is not
  /// changed while widgets build).
  void _clearLingering() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(lingeringTodosProvider.notifier).clear();
    });
  }

  /// Checks [todo] off ([done]) or reopens it, on the spot, and sends that
  /// state; the snackbar's "Geri al" reopens it where it was.
  Future<void> _setDone(Todo todo, {required bool done}) {
    final listed =
        ref.read(homeProvider).value?.data.upcomingTodos ?? const <Todo>[];
    final index = listed.indexWhere((t) => t.id == todo.id);
    return setTodoDone(
      context,
      ref,
      todo,
      done: done,
      index: index < 0 ? listed.length : index,
    );
  }

  /// Moves [todo] to tomorrow — gone from Today at once — with "Geri al",
  /// which puts it back on its day, in its place at once (grown back in and
  /// washed). A move that fails slides the row back.
  Future<bool> _postpone(Todo todo, DateTime today) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final back = todo.dueDay;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final home = ref.read(homeProvider.notifier);
    final listed =
        ref.read(homeProvider).value?.data.upcomingTodos ?? const <Todo>[];
    final at = listed.indexWhere((t) => t.id == todo.id);
    final edit = home.patch(
      (h) => h.copyWith(
        upcomingTodos: [
          for (final t in h.upcomingTodos)
            if (t.id != todo.id) t,
        ],
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    final sync = ref.read(dataSyncProvider);

    Future<void> undo() async {
      // Back in its place at once; the server's answer confirms it.
      final restore = home.patch((h) {
        if (h.upcomingTodos.any((t) => t.id == todo.id)) return h;
        final rows = [...h.upcomingTodos];
        rows.insert((at < 0 ? rows.length : at).clamp(0, rows.length), todo);
        return h.copyWith(upcomingTodos: rows);
      });
      sync.noteChange(DataScope.todos, todo.id, ChangeKind.restored);
      try {
        await repo.postponeTodo(todo.id, back!);
        restore.confirm();
      } catch (e) {
        restore.rollback();
        if (messenger.mounted) {
          showAppSnack(
            messenger.context,
            failureMessage(e, l, fallback: l.todoSaveFailed),
            isError: true,
          );
        }
      }
    }

    try {
      await repo.postponeTodo(todo.id, tomorrow);
      edit.confirm();
      if (mounted) {
        showAppSnack(
          context,
          l.todoPostponed(todo.title),
          actionLabel: back == null ? null : l.actionUndo,
          onAction: back == null ? null : undo,
        );
      }
      return true;
    } catch (e) {
      edit.rollback();
      if (mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.todoSaveFailed),
          isError: true,
        );
      } else {
        Haptics.reject();
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) TodayAgendaSection.debugBuilds++;
    final l = context.l10n;
    final today =
        ref.watch(homeProvider.select((a) => a.value?.data.today)) ??
        ref.watch<DateTime>(currentDayProvider);
    final day = dateOnly(today);
    // A new day: yesterday's ticks are not today's "n tamamlandı" — gone
    // from this frame on.
    final rolledOver = _day != null && _day != day;
    if (rolledOver) {
      _clearLingering();
      _showPassed = false;
    }
    _day = day;
    final upcoming =
        ref.watch(homeProvider.select((a) => a.value?.data.upcomingTodos)) ??
        const <Todo>[];
    final watched = ref.watch(lingeringTodosProvider);
    final lingering = rolledOver ? const LingeringState() : watched;
    final hidden = ref.watch(deferredDeletesProvider);
    final window = EventWindow(day, day);
    final listed = ref.watch(
      eventsProvider(window).select((a) => a.value?.data),
    );
    final homeEvents =
        ref.watch(homeProvider.select((a) => a.value?.data.todayEvents)) ??
        const <Event>[];
    final homeEventCount =
        ref.watch(homeProvider.select((a) => a.value?.data.todayEventsCount)) ??
        0;
    final now = watchTodayNow(context, ref);

    // --- Todos: overdue and today's, the lingering ones back in place.
    final todos = [
      for (final t in withoutDeleted(
        mergeInto(upcoming, lingering),
        hidden,
        DataScope.todos,
        (t) => t.id,
      ))
        if ((!t.isDone || lingering.contains(t.id)) && _isTodays(t, day)) t,
    ];

    // --- Events.
    final events = withoutDeleted(
      listed ?? homeEvents,
      hidden,
      DataScope.events,
      (e) => e.id,
    );
    final occurrences = listed == null
        ? occurrencesIn(events, window, fallbackDay: day)
        : occurrencesIn(events, window);
    // `/home` lists at most four of today's events; it says how many.
    final unlisted = listed == null
        ? (homeEventCount - occurrences.length).clamp(0, 999)
        : 0;

    final overdue = <_Item>[];
    final allDay = <_Item>[];
    final timed = <(DateTime, _Item)>[];
    final passed = <_Item>[];
    final dateOnlyTodos = <_Item>[];
    for (final t in todos) {
      final due = t.dueDay;
      final at = _timeOf(t, day);
      if (due != null && due.isBefore(day)) {
        overdue.add(_TodoItem(t));
      } else if (at != null) {
        timed.add((at, _TodoItem(t)));
      } else {
        dateOnlyTodos.add(_TodoItem(t));
      }
    }
    for (final o in occurrences) {
      final e = o.event;
      if (e.allDay || e.startAt == null) {
        allDay.add(_EventItem(o, finished: false));
        continue;
      }
      final start = e.occurrenceStart(o.day);
      if (!occurrenceEndOf(e, o.day).isAfter(now)) {
        passed.add(_EventItem(o, finished: true));
      } else {
        timed.add((start, _EventItem(o, finished: false)));
      }
    }
    timed.sort((a, b) => a.$1.compareTo(b.$1));

    final items = <_Item>[
      ...overdue,
      ...allDay,
      if (passed.isNotEmpty) _PassedItem(passed.length),
      if (passed.isNotEmpty && _showPassed) ...passed,
      for (final (_, item) in timed) item,
      ...dateOnlyTodos,
    ];
    // The cap counts the rows that are a todo or an event.
    final shown = <_Item>[];
    var rows = 0;
    var hiddenRows = 0;
    for (final item in items) {
      if (item is _PassedItem) {
        shown.add(item);
        continue;
      }
      if (rows < TodayAgendaSection.maxRows) {
        shown.add(item);
        rows++;
      } else if (!(item is _EventItem && item.finished)) {
        hiddenRows++;
      }
    }
    final more = hiddenRows + unlisted;

    final openCount =
        todos.where((t) => !t.isDone).length +
        timed.where((e) => e.$2 is _EventItem).length +
        allDay.length +
        unlisted;
    // Nothing left to do today — the events over, the todos ticked off — is
    // "Hepsi tamam"; nothing planned at all is the calm line.
    final open = items.where(
      (i) => i is _TodoItem || (i is _EventItem && !i.finished),
    );
    final nothing = items.isEmpty && unlisted == 0;
    final allDone =
        open.isEmpty &&
        unlisted == 0 &&
        (passed.isNotEmpty || lingering.finished > 0);

    final children = <Widget>[
      for (final item in shown) _row(context, item, lingering, day),
      if (more > 0)
        _LinkRow(
          label: l.todayMoreRows(more),
          onTap: () => context.go('/agenda'),
        ),
      if (allDone)
        const Padding(
          padding: EdgeInsets.fromLTRB(Insets.rowH, Gap.md, Insets.rowH, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: EmptyState.allDone(),
          ),
        )
      else if (nothing && lingering.finished == 0)
        _CalmLine(message: l.todayEmptyDay),
      if (lingering.finished > 0)
        FinishedSummaryRow(
          key: const ValueKey('todos-finished'),
          count: lingering.finished,
          onTap: () => context.go('/agenda?view=done'),
        ),
      _InlineAdd(key: const ValueKey('todo-add'), day: day),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l.titleToday,
          count: openCount > 0 ? '$openCount' : null,
          onSeeAll: () => context.go('/agenda'),
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: todayResize(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    _Item item,
    LingeringState lingering,
    DateTime day,
  ) {
    final c = context.nok;
    final l = context.l10n;
    switch (item) {
      case _PassedItem(:final count):
        return _LinkRow(
          key: const ValueKey('events-passed'),
          label: l.todayEventsPassed(count),
          muted: true,
          trailing: RotatedBox(
            quarterTurns: _showPassed ? 2 : 0,
            child: Icon(Icons.expand_more_rounded, size: 18, color: c.inkLow),
          ),
          expanded: _showPassed,
          onTap: () => setState(() => _showPassed = !_showPassed),
        );
      case _EventItem(:final occurrence, :final finished):
        final o = occurrence;
        return EventRow(
          key: ValueKey('event-${o.event.id}-${isoDate(o.day)}'),
          event: o.event,
          day: o.day,
          finished: finished,
          onTap: () => showEventSheet(context, o.event, day: o.day),
        );
      case _TodoItem(:final todo):
        final t = todo;
        final index = ref
            .read(homeProvider)
            .value
            ?.data
            .upcomingTodos
            .indexWhere((x) => x.id == t.id);
        final row = TodoRow(
          key: ValueKey('todo-${t.id}'),
          todo: t,
          done: t.isDone,
          onToggle: () => _setDone(t, done: !t.isDone),
          onTap: () => openTodoSheet(context, existing: t),
          onLongPress: () => showTodoMenu(
            context,
            ref,
            t,
            done: t.isDone,
            index: index == null || index < 0 ? 0 : index,
          ),
        );
        final collapsing = lingering.collapsing && lingering.contains(t.id);
        return _Collapse(
          key: ValueKey('todo-slot-${t.id}'),
          collapsed: collapsing,
          child: RowMotion(
            record: (scope: DataScope.todos, id: t.id),
            child: t.isDone
                ? row
                : SwipeAction(
                    key: ValueKey('todo-swipe-${t.id}'),
                    startToEnd: SwipeSpec.complete(
                      c,
                      label: l.todoComplete,
                      onSwipe: () async {
                        // The row slides back, its box fills, and it
                        // lingers like a tapped one.
                        _setDone(t, done: true);
                        return false;
                      },
                    ),
                    endToStart: SwipeSpec.postpone(
                      c,
                      label: l.todoPostpone,
                      onSwipe: () => _postpone(t, day),
                    ),
                    child: row,
                  ),
          ),
        );
    }
  }
}

/// Whether [todo] belongs on Today: overdue, or due today.
bool _isTodays(Todo todo, DateTime day) {
  final due = todo.dueDay;
  if (due == null) return todo.overdue;
  return !due.isAfter(day);
}

/// When on [day] a todo due today with a time is due; null without one.
DateTime? _timeOf(Todo todo, DateTime day) {
  final time = todo.dueTime;
  if (time == null || todo.dueDay != day) return null;
  final parts = time.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return DateTime(day.year, day.month, day.day, h, m);
}

/// A 48 dp row that leads somewhere: "+3 daha", "+2 geçti".
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.label,
    required this.onTap,
    this.muted = false,
    this.trailing,
    this.expanded,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;
  final Widget? trailing;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    // A stop of its own: its words are not the card's.
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Hit.min),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.rowH + 56 + Gap.md,
                Gap.sm,
                Insets.rowH,
                Gap.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: muted
                          ? text.bodyMedium!.copyWith(color: c.inkMid)
                          : text.labelLarge!.copyWith(color: c.gold),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Bugün plan yok — sakin bir gün": the empty card's quiet line.
class _CalmLine extends StatelessWidget {
  const _CalmLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Hit.min),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.rowH,
          Gap.md,
          Insets.rowH,
          Gap.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Icon(
                  Icons.event_available_outlined,
                  size: 20,
                  color: c.inkMid,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                message,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row folding away ([collapsed]): its height closes in [Motion.collapse]
/// (`easeInCubic`) as it fades in the first 150 ms. Reduced motion: gone
/// at once.
class _Collapse extends StatefulWidget {
  const _Collapse({super.key, required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  @override
  State<_Collapse> createState() => _CollapseState();
}

class _CollapseState extends State<_Collapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.collapse,
    value: widget.collapsed ? 0 : 1,
  );
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _c,
    curve: Motion.exit,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _c,
    curve: Interval(
      1 - Motion.pressOut.inMicroseconds / Motion.collapse.inMicroseconds,
      1,
    ),
  );

  @override
  void didUpdateWidget(_Collapse old) {
    super.didUpdateWidget(old);
    if (widget.collapsed == old.collapsed) return;
    final target = widget.collapsed ? 0.0 : 1.0;
    if (Motion.reduced(context)) {
      _c.value = target;
    } else {
      _c.animateTo(target);
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    alignment: AlignmentDirectional.topStart,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}

/// "+ Bugün için görev ekle" (design-analysis §7.2.5): a 48 dp row that
/// opens into a field in place. Enter adds a todo due [day] — it grows in,
/// washed, above the field — and the field keeps the focus for the next;
/// leaving the field empty folds it back.
class _InlineAdd extends ConsumerStatefulWidget {
  const _InlineAdd({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<_InlineAdd> createState() => _InlineAddState();
}

class _InlineAddState extends ConsumerState<_InlineAdd> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text.trim().isEmpty && _open) {
        setState(() => _open = false);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: Motion.orInstant(context, Motion.collapse),
        curve: Motion.enter,
      );
    });
  }

  Future<void> _submit(String raw) async {
    final title = raw.trim();
    if (title.isEmpty) return;
    final l = context.l10n;
    _text.clear();
    _focus.requestFocus();
    try {
      final todo = await ref
          .read(repositoryProvider)
          .createTodo(TodoInput(title: title, dueDate: widget.day));
      if (!mounted) return;
      ref
          .read(dataSyncProvider)
          .noteChange(DataScope.todos, todo.id, ChangeKind.inserted);
      // On Today at once, until the refetch the write set off has it.
      ref.read(homeProvider.notifier).patch((h) {
        if (h.upcomingTodos.any((t) => t.id == todo.id)) return h;
        return h.copyWith(
          upcomingTodos: [...h.upcomingTodos, todo],
          openTodos: h.openTodos + 1,
        );
      }).confirm();
    } catch (e) {
      if (!mounted) return;
      // Nothing typed is lost.
      if (_text.text.isEmpty) _text.text = title;
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.todoSaveFailed),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    ref.listen(todayInlineAddProvider, (_, _) => _expand());

    final leading = SizedBox(
      width: 56,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Icon(Icons.add_rounded, size: 20, color: c.gold),
      ),
    );
    final Widget body;
    if (_open) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.rowH,
          Gap.xs,
          Insets.rowH,
          Gap.xs,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Gap.md),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                style: text.bodyLarge,
                decoration: InputDecoration(
                  hintText: l.todayAddForToday,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: _submit,
                // Enter keeps the field: the next todo is typed right away.
                onEditingComplete: () {},
              ),
            ),
          ],
        ),
      );
    } else {
      body = MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: _expand,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.rowH,
                  vertical: Gap.md,
                ),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Text(
                        l.todayAddForToday,
                        style: text.bodyMedium!.copyWith(color: c.inkMid),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return todayResize(context, duration: Motion.quick, child: body);
  }
}
