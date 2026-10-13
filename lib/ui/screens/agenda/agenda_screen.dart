import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/lingering_todos.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/entity_color.dart';
import '../../flows/flows.dart';
import '../../widgets/agenda_rows.dart';
import '../../widgets/capture_bar.dart';
import '../../widgets/day_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/row_motion.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import '../search/search_entry_button.dart';
import 'agenda_days.dart';
import 'agenda_tiles.dart';
import 'event_sheet.dart';
import 'todo_flows.dart';
import 'todo_lists_screen.dart';

/// What the Agenda shows — one view at a time, picked by its chips.
enum AgendaView {
  /// Every day ahead: overdue, today, the next days, later (the default).
  upcoming,

  /// Open todos without a date.
  inbox,

  /// Only the overdue ones, and "Hepsini bugüne al".
  overdue,

  /// Finished todos, by the day they were finished.
  done;

  /// The view a link's `?view=` asks for: `upcoming`, `inbox`, `overdue`,
  /// `done` — and p24's todo filters (`undated` is the inbox; `open`,
  /// `today`, `events`… are the days ahead). Null without one.
  static AgendaView? of(String? view) => switch (view) {
    null => null,
    'inbox' || 'undated' => AgendaView.inbox,
    'overdue' => AgendaView.overdue,
    'done' => AgendaView.done,
    _ => AgendaView.upcoming,
  };
}

/// The Ajanda tab (design-analysis §7.4, IA-2): todos and events in one
/// list, day by day.
///
/// * **Views** — chips under the title: "Yaklaşan" (the default), "Gelen
///   kutusu · n" and "Gecikmiş · n" (hidden while there are none), "Liste:
///   Tümü ▾" (a picker: every list, no list, each list, "+ Yeni liste",
///   "Listeleri yönet") and "Tamamlanan". The row scrolls sideways and
///   fades at its end when it does not fit.
/// * **Yaklaşan** — the open todos (`GET /todos?filter=open&sort=due`) and
///   the next 30 days of events (30 more with each "Daha fazla göster"),
///   under pinned day headings: "Gecikmiş" (with "Hepsini bugüne al"),
///   "Bugün" (always), tomorrow and the five days after it, "Sonra". A long
///   press on a day's heading adds to that day.
/// * Rows: a tap opens, the box ticks off (the row lingers 4 s, struck
///   through, then folds into "✓ n tamamlandı"), → "Tamamla", ← "Yarın", a
///   long press the menu. Every one of them with "Geri al".
/// * Adding: the capture bar ("Ekle: görev, etkinlik…") and its "Etkinlik
///   ekle".
///
/// Opened with `?view=` and `?list=` (a list id, or `none`) — the old
/// `/todos` links, redirected here — it shows that, then takes the query
/// off the location.
class AgendaTabScreen extends ConsumerStatefulWidget {
  final String? view;
  final String? list;

  const AgendaTabScreen({super.key, this.view, this.list});

  @override
  ConsumerState<AgendaTabScreen> createState() => _AgendaTabScreenState();
}

class _AgendaTabScreenState extends ConsumerState<AgendaTabScreen>
    with TabRootScroll<AgendaTabScreen> {
  @override
  AppTab get tab => AppTab.agenda;

  static const _step = 30;
  static const _maxDays = 367;

  AgendaView _view = AgendaView.upcoming;
  int? _listId;
  bool _unlisted = false;

  /// How many days of events "Yaklaşan" reads.
  int _days = _step;

  /// What the last event window showed — kept on screen while a longer
  /// window loads, so "Daha fazla göster" never blanks the list.
  ({EventWindow window, List<Event> events})? _shownEvents;

  /// The chips' counts as last fetched — kept while another view's first
  /// load is on its way, so the chips do not blink out.
  Map<String, int> _counts = const {};

  /// The last view drawn, and its key: kept in place — dimmed after a
  /// moment — while the next one loads, never a blank (§5.4); the switch
  /// then cross-fades from it.
  Widget? _lastContent;
  Object? _lastKey;

  @override
  void initState() {
    super.initState();
    _apply(widget.view, widget.list);
    // The open todos' overdue count is the tab badge's once it is newer
    // than /home's (§6.1). Also the list "Yaklaşan" opens on, so it is not
    // fetched twice.
    ref.listenManual(todosProvider(const TodoQuery()), (_, next) {
      final fetched = next.value;
      if (fetched == null || fetched.data.counts.isEmpty) return;
      // Never while the tree builds: a cached list fires at once, from
      // initState.
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(agendaOverdueProvider.notifier)
            .report(Fetched(fetched.data.counts['overdue'] ?? 0, fetched.at));
      });
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab was left (hidden behind another): what lingered goes, without
    // motion (§4.29).
    if (!TickerMode.valuesOf(context).enabled) {
      // Not while the tree builds.
      Future.microtask(() {
        if (mounted) ref.read(lingeringTodosProvider.notifier).clear();
      });
    }
  }

  @override
  void didUpdateWidget(AgendaTabScreen old) {
    super.didUpdateWidget(old);
    if (widget.view != old.view || widget.list != old.list) {
      _apply(widget.view, widget.list);
    }
  }

  void _apply(String? view, String? list) {
    if (view == null && list == null) return;
    _view = AgendaView.of(view) ?? AgendaView.upcoming;
    _listId = list == null ? null : int.tryParse(list);
    _unlisted = list == 'none';
    // Shown once: the location goes back to the bare tab, so the same link
    // followed again applies again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GoRouter.maybeOf(context)?.go(AppTab.agenda.location);
    });
  }

  void _show(AgendaView view) {
    if (view == _view) return;
    setState(() => _view = view);
  }

  void _filterList(int? listId, {bool unlisted = false}) {
    if (listId == _listId && unlisted == _unlisted) return;
    setState(() {
      _listId = listId;
      _unlisted = unlisted;
    });
  }

  TodoQuery _query(String filter) =>
      TodoQuery(filter: filter, listId: _listId, unlisted: _unlisted);

  /// The read model of [view].
  TodoQuery _queryOf(AgendaView view) => switch (view) {
    AgendaView.upcoming || AgendaView.overdue => _query('open'),
    AgendaView.inbox => _query('undated'),
    AgendaView.done => _query('done'),
  };

  bool get _listFiltered => _listId != null || _unlisted;

  DateTime get _today => accountToday(ref);

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([
      todosProvider,
      eventsProvider,
      todoListsProvider,
    ]);
    await settleRefresh([
      refetchLanded(ref, todosProvider(_queryOf(_view))),
    ], minimum: Motion.refreshMinimum);
  }

  void _retry() => ref.read(dataSyncProvider).refresh([
    todosProvider,
    eventsProvider,
    todoListsProvider,
  ]);

  static bool _isNotFound(Object? error) =>
      error is ApiException && error.kind == ApiErrorKind.notFound;

  /// "Liste: … ▾": every list, the todos in no list, each list (with its
  /// open todos), "+ Yeni liste" and "Listeleri yönet".
  Future<void> _pickList(TodoListsBundle? lists) async {
    final l = context.l10n;
    final c = context.nok;
    final picked = await showPickerSheet<String>(
      context,
      title: l.todoFieldList,
      selected: _unlisted
          ? 'none'
          : _listId == null
          ? 'all'
          : 'list:$_listId',
      options: [
        PickerOption(value: 'all', label: l.labelAll),
        PickerOption(
          value: 'none',
          label: l.todoNoList,
          trailing: (lists?.unlistedOpenCount ?? 0) > 0
              ? '${lists!.unlistedOpenCount}'
              : null,
        ),
        for (final list in lists?.lists ?? const <TodoList>[])
          PickerOption(
            value: 'list:${list.id}',
            label: list.name,
            color: entityTone(list.color, c).fill,
            trailing: list.openCount > 0 ? '${list.openCount}' : null,
          ),
        PickerOption(
          value: 'new',
          label: l.todoListNew,
          icon: Icons.add_rounded,
        ),
        PickerOption(
          value: 'manage',
          label: l.todoListsManage,
          icon: Icons.tune_rounded,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'all':
        _filterList(null);
      case 'none':
        _filterList(null, unlisted: true);
      case 'new':
        final made = await openTodoListSheet(context);
        if (made != null && mounted) _filterList(made.id);
      case 'manage':
        context.push('/agenda/lists');
      default:
        _filterList(int.tryParse(picked.substring('list:'.length)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final hidden = ref.watch(deferredDeletesProvider);
    // The account's today, watched: the agenda redraws when it turns.
    final today = dateOnly(
      ref.watch(homeProvider.select((h) => h.value?.data.today)) ??
          ref.watch(currentDayProvider),
    );

    final listsAsync = ref.watch(todoListsProvider);
    final lists = listsAsync.value?.data;
    // The list filtered by was deleted — on the lists page, or elsewhere
    // (the server then answers 404): back to every list, never an offline
    // banner over the deleted list's rows.
    final listId = _listId;
    if (listId != null &&
        lists != null &&
        !listsAsync.isLoading &&
        ![...lists.lists, ...lists.archived].any((x) => x.id == listId)) {
      _listId = null;
    }
    var query = _queryOf(_view);
    var async = ref.watch(todosProvider(query));
    if (_listId != null && _isNotFound(async.error)) {
      _listId = null;
      query = _queryOf(_view);
      async = ref.watch(todosProvider(query));
    }
    final fetched = async.value;
    if (fetched != null && fetched.data.counts.isNotEmpty) {
      _counts = fetched.data.counts;
    }

    // "Yaklaşan" reads the events too — unless a list is picked: events
    // belong to no list.
    final withEvents = _view == AgendaView.upcoming && !_listFiltered;
    final window = EventWindow.days(today, _days);
    AsyncValue<Fetched<List<Event>>>? events;
    if (withEvents) {
      final watched = ref.watch(eventsProvider(window));
      events = watched;
      final value = watched.value;
      if (value != null) _shownEvents = (window: window, events: value.data);
    }
    final lingering = ref.watch(lingeringTodosProvider);

    final LoadPhase phase;
    if (fetched != null) {
      phase = LoadPhase.content;
    } else if (async.hasFailed) {
      phase = LoadPhase.error;
    } else {
      phase = LoadPhase.waiting;
    }

    final viewKey = (_view, _listId, _unlisted);
    // A view change cross-fades in 200 ms, without a stagger (§7.4). Always
    // the same switcher: while the next view loads, the last one stays in
    // it as it was — its scroll offset, its rows — dimmed after a moment
    // and not tappable (§5.4); the new view's key then cross-fades in.
    Widget switcher(Object key, Widget child, {required bool loading}) =>
        AnimatedSwitcher(
          duration: Motion.orInstant(context, Motion.quick),
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(
            key: ValueKey(key),
            child: _Dimmed(loading: loading, child: child),
          ),
        );
    Widget content(BuildContext context) {
      if (fetched == null) {
        // Another view is on its way: the last one stays.
        return switcher(
          _lastKey ?? viewKey,
          _lastContent ?? const SizedBox.expand(),
          loading: true,
        );
      }
      final todos = withoutDeleted(
        fetched.data.todos,
        hidden,
        DataScope.todos,
        (t) => t.id,
      );
      final Widget view = switch (_view) {
        AgendaView.upcoming || AgendaView.overdue => _upcoming(
          context,
          todos,
          query,
          lingering,
          today,
          hidden,
          events: withEvents ? events : null,
          overdueOnly: _view == AgendaView.overdue,
        ),
        AgendaView.inbox => _inbox(
          context,
          todos,
          query,
          lingering,
          today,
          hidden,
        ),
        AgendaView.done => _done(context, todos, today),
      };
      final shown = Column(
        children: [
          OfflineBannerSlot(
            banner: async.refreshFailed
                ? OfflineBanner(lastUpdated: fetched.at, onRetry: _retry)
                : null,
          ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              // Armed (§5.8): the pull let go past its threshold.
              onRefresh: () {
                Haptics.armed();
                return _refresh();
              },
              child: view,
            ),
          ),
        ],
      );
      _lastContent = shown;
      _lastKey = viewKey;
      return switcher(viewKey, shown, loading: false);
    }

    final refetching = async.isRefetching || (events?.isRefetching ?? false);
    // The list filtered by — an archived one too (a link may name it).
    final filteredList = _listId == null || lists == null
        ? null
        : [
            ...lists.lists,
            ...lists.archived,
          ].where((x) => x.id == _listId).firstOrNull;
    return primaryScroll(
      Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(l.tabAgenda, style: text.headlineLarge),
          actions: [
            // Hidden when the server has no search (contract §13).
            const SearchEntryButton(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: l.actionMoreOptions,
              onSelected: (item) {
                switch (item) {
                  case 'lists':
                    context.push('/agenda/lists');
                  case 'done':
                    _show(AgendaView.done);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'lists', child: Text(l.todoListsManage)),
                PopupMenuItem(value: 'done', child: Text(l.agendaShowDone)),
              ],
            ),
            const SizedBox(width: Gap.xs),
          ],
        ),
        body: CaptureBarLayout(
          // What a row starts — a move, a menu — says how it went here, above
          // the capture bar, even once the row itself is gone.
          body: Builder(
            builder: (host) => AgendaHost(
              hostContext: host,
              ref: ref,
              child: Column(
                children: [
                  _ViewChips(
                    view: _view,
                    counts: _counts,
                    list: _unlisted ? l.todoNoList : filteredList?.name,
                    listColor: filteredList == null
                        ? null
                        : entityTone(filteredList.color, c).fill,
                    listFiltered: _listFiltered,
                    onView: _show,
                    onList: () => _pickList(lists),
                  ),
                  Expanded(
                    child: SyncHint.over(
                      active: refetching,
                      child: LoadPhaseSwitcher(
                        phase: phase,
                        skeleton: (_) => const _AgendaSkeleton(),
                        content: content,
                        error: (_) => EmptyState.error(
                          onRetry: _retry,
                          onServerSettings: () =>
                              context.push('/profile/server'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bar: CaptureBar(
            label: l.agendaCaptureLabel,
            onOpen: () => openQuickAdd(context, ctx: QuickAddContext.agenda),
            secondaryIcon: Icons.event_outlined,
            secondaryTooltip: l.agendaAddEvent,
            onSecondary: () => openEventForm(context, day: _today),
          ),
        ),
      ),
    );
  }

  /// The space under the last row: the capture bar and the system's inset.
  double _bottomClearance(BuildContext context) =>
      Insets.captureBarClearance + MediaQuery.paddingOf(context).bottom;

  /// The open todos on screen: the server's, with the ones just ticked off
  /// still among them (struck through) until they fold away — those that
  /// belong in [query] on [today], and not deleted meanwhile ([hidden]).
  List<Todo> _withLingering(
    List<Todo> todos,
    TodoQuery query,
    LingeringState lingering,
    DateTime today,
    Set<RecordKey> hidden,
  ) {
    final mine = LingeringState(
      todos: {
        for (final MapEntry(:key, :value) in lingering.todos.entries)
          if (query.admitsOpen(value.todo, today) &&
              !hidden.contains((scope: DataScope.todos, id: value.todo.id)))
            key: value,
      },
      collapsing: lingering.collapsing,
      finished: lingering.finished,
    );
    return mergeInto(todos, mine);
  }

  /// "Yaklaşan" — or, with [overdueOnly], "Gecikmiş" alone.
  Widget _upcoming(
    BuildContext context,
    List<Todo> fetchedTodos,
    TodoQuery query,
    LingeringState lingering,
    DateTime today,
    Set<RecordKey> hidden, {
    AsyncValue<Fetched<List<Event>>>? events,
    bool overdueOnly = false,
  }) {
    final l = context.l10n;
    final todos = _withLingering(fetchedTodos, query, lingering, today, hidden);
    final shownEvents = events == null ? null : _shownEvents;
    final occurrences = shownEvents == null
        ? const <Occurrence>[]
        : occurrencesIn(
            withoutDeleted(
              shownEvents.events,
              hidden,
              DataScope.events,
              (e) => e.id,
            ),
            shownEvents.window,
          );
    var groups = upcomingGroups(
      todos: todos,
      occurrences: occurrences,
      today: today,
    );
    if (overdueOnly) {
      groups = [
        for (final g in groups)
          if (g.kind == AgendaGroupKind.overdue) g,
      ];
    }
    final index = {for (var i = 0; i < todos.length; i++) todos[i].id: i};
    final finished = lingering.finished;
    final nothing = groups.every((g) => g.entries.isEmpty) && finished == 0;

    final slivers = <Widget>[];
    if (nothing) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: overdueOnly
              ? EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: l.todoFilterEmpty('overdue'),
                )
              : EmptyState(
                  icon: Icons.wb_twilight_rounded,
                  title: l.agendaUpcomingEmpty,
                  subtitle: l.agendaUpcomingEmptyBody,
                ),
        ),
      );
    } else {
      for (final group in groups) {
        slivers.add(
          _group(
            context,
            group,
            today,
            index,
            lingering,
            finished:
                group.kind == AgendaGroupKind.today ||
                    (overdueOnly && group == groups.last)
                ? finished
                : 0,
          ),
        );
      }
      if (overdueOnly && groups.isEmpty && finished > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: _card(context, [_summary(context, finished)]),
          ),
        );
      }
    }
    if (events != null && _days < _maxDays) {
      slivers.add(SliverToBoxAdapter(child: _showMore(context, events)));
    }
    slivers.add(
      SliverPadding(
        padding: EdgeInsets.only(bottom: _bottomClearance(context)),
      ),
    );
    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  /// One day (or "Gecikmiş", "Sonra"): its pinned heading over a card of
  /// its rows. Today, empty, still shows — with what was just finished.
  Widget _group(
    BuildContext context,
    AgendaGroup group,
    DateTime today,
    Map<int, int> index,
    LingeringState lingering, {
    int finished = 0,
  }) {
    final l = context.l10n;
    final showList = !_listFiltered;
    Widget header;
    switch (group.kind) {
      case AgendaGroupKind.overdue:
        final open = group.todos.where((t) => t.isOpen).toList();
        header = DayHeader.overdue(
          label: l.todoGroupOverdue,
          count: open.isEmpty ? null : '${open.length}',
          onMoveAllToToday: open.isEmpty
              ? null
              : () => moveTodos(
                  context,
                  ref,
                  open,
                  day: today,
                  message: l.todosMovedToday(open.length),
                  ghost: _view == AgendaView.overdue,
                ),
        );
      case AgendaGroupKind.later:
        header = DayHeader(label: l.agendaLater);
      case AgendaGroupKind.today || AgendaGroupKind.day:
        header = _DayHeading(
          day: group.day!,
          header: DayHeader.forDay(context, group.day!, today: today),
        );
    }

    final rows = <Widget>[];
    if (group.entries.isNotEmpty) {
      rows.add(
        RemovalAwareList<AgendaEntry>(
          items: group.entries,
          recordOf: agendaRecordOf,
          animateRemoval: (entry) => switch (entry) {
            TodoEntry(:final todo) => _removedByUser(DataScope.todos, todo.id),
            // By the event's own id: a delete hides every occurrence.
            EventEntry(:final event) => _removedByUser(
              DataScope.events,
              event.id,
            ),
          },
          itemBuilder: (context, entry) => switch (entry) {
            TodoEntry(:final todo) => AgendaTodoTile(
              todo: todo,
              index: index[todo.id] ?? 0,
              today: today,
              showList: showList,
              collapsing: lingering.collapsing && lingering.contains(todo.id),
            ),
            EventEntry(:final event, :final day) => RowMotion(
              record: (scope: DataScope.events, id: event.id),
              child: EventRow(
                key: ValueKey('event-${event.id}-$day'),
                event: event,
                day: day,
                showDay: group.kind == AgendaGroupKind.later,
                onTap: () => showEventSheet(context, event, day: day),
              ),
            ),
          },
        ),
      );
    }
    if (finished > 0) rows.add(_summary(context, finished));

    final Widget body;
    if (rows.isEmpty) {
      body = EmptyState.inline(
        icon: Icons.wb_sunny_outlined,
        message: l.agendaTodayEmpty,
      );
    } else {
      body = _card(context, rows);
    }
    return SliverMainAxisGroup(
      key: ValueKey(('group', group.kind, group.day)),
      slivers: [
        PinnedHeaderSliver(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.gutter,
            Gap.xs,
            Insets.gutter,
            Gap.lg,
          ),
          sliver: SliverToBoxAdapter(child: body),
        ),
      ],
    );
  }

  /// Whether the user just removed record [id] of [scope] here — a delete
  /// from its menu or sheet, a day picked for a todo: its row folds away
  /// where it was.
  bool _removedByUser(DataScope scope, int id) =>
      ref.read(deferredDeletesProvider).contains((scope: scope, id: id)) ||
      ref.read(recentChangesProvider.notifier).of(scope, id) ==
          ChangeKind.removed;

  Widget _card(BuildContext context, List<Widget> rows) => NokturnCard(
    variant: NokCardVariant.list,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    ),
  );

  /// "✓ 3 tamamlandı": what was just ticked off, folded; a tap shows them.
  Widget _summary(BuildContext context, int count) => FinishedSummaryRow(
    key: const ValueKey('finished-summary'),
    count: count,
    onTap: () => _show(AgendaView.done),
  );

  /// "Daha fazla göster": thirty more days of events, up to a year — or,
  /// when the longer window failed, why, and "Tekrar dene".
  Widget _showMore(
    BuildContext context,
    AsyncValue<Fetched<List<Event>>> events,
  ) {
    final l = context.l10n;
    final c = context.nok;
    final loading = events.value == null;
    final error = loading && events.hasFailed ? events.error : null;
    final Widget child;
    if (error != null) {
      child = Semantics(
        liveRegion: true,
        child: Column(
          children: [
            Text(
              failureMessage(error, l, fallback: l.agendaLoadFailed),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: c.inkMid),
            ),
            TextButton.icon(
              onPressed: () =>
                  ref.read(dataSyncProvider).refresh([eventsProvider]),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l.actionRetry),
            ),
          ],
        ),
      );
    } else if (loading) {
      child = const Padding(
        padding: EdgeInsets.all(Gap.md),
        child: CircularProgressIndicator.adaptive(),
      );
    } else {
      child = TextButton(
        onPressed: () =>
            setState(() => _days = math.min(_days + _step, _maxDays)),
        child: Text(l.agendaShowMore),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 0),
      child: Center(child: child),
    );
  }

  /// "Gelen kutusu": open todos without a date, newest first, each with its
  /// "Bugün" and "Yarın".
  Widget _inbox(
    BuildContext context,
    List<Todo> fetchedTodos,
    TodoQuery query,
    LingeringState lingering,
    DateTime today,
    Set<RecordKey> hidden,
  ) {
    final l = context.l10n;
    final todos = _withLingering(fetchedTodos, query, lingering, today, hidden);
    final finished = lingering.finished;
    final showList = !_listFiltered;
    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (todos.isEmpty && finished == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.inbox_outlined,
              title: l.agendaInboxEmpty,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              Gap.md,
              Insets.gutter,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _card(context, [
                RemovalAwareList<Todo>(
                  items: todos,
                  recordOf: (t) => (scope: DataScope.todos, id: t.id),
                  animateRemoval: (t) => _removedByUser(DataScope.todos, t.id),
                  itemBuilder: (context, todo) => InboxTodoTile(
                    todo: todo,
                    index: todos.indexOf(todo),
                    today: today,
                    showList: showList,
                    collapsing:
                        lingering.collapsing && lingering.contains(todo.id),
                  ),
                ),
                if (finished > 0) _summary(context, finished),
              ]),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: _bottomClearance(context)),
        ),
      ],
    );
  }

  /// "Tamamlanan": finished todos under the day each was finished on; the
  /// box reopens one, with "Geri al".
  Widget _done(BuildContext context, List<Todo> todos, DateTime today) {
    final l = context.l10n;
    final groups = doneGroups(todos);
    final showList = !_listFiltered;
    return CustomScrollView(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              title: l.todoFilterEmpty('done'),
            ),
          )
        else
          for (final group in groups)
            SliverMainAxisGroup(
              key: ValueKey(('done', group.day)),
              slivers: [
                PinnedHeaderSliver(
                  child: group.day == null
                      ? DayHeader(label: l.agendaViewDone)
                      : DayHeader.forDay(context, group.day!, today: today),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.gutter,
                    Gap.xs,
                    Insets.gutter,
                    Gap.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _card(context, [
                      for (final todo in group.todos)
                        AgendaTodoTile(
                          key: ValueKey('done-${todo.id}'),
                          todo: todo,
                          index: todos.indexOf(todo),
                          today: today,
                          showList: showList,
                          finishedView: true,
                        ),
                    ]),
                  ),
                ),
              ],
            ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: _bottomClearance(context)),
        ),
      ],
    );
  }
}

/// A day's heading that a long press adds to: quick add, opened on that
/// day (§6.5). Screen readers hear the long press as "bu güne ekle".
class _DayHeading extends StatelessWidget {
  final DateTime day;
  final DayHeader header;

  const _DayHeading({required this.day, required this.header});

  @override
  Widget build(BuildContext context) {
    void add() => openQuickAdd(context, ctx: QuickAddContext.agenda, day: day);
    return Semantics(
      onLongPress: add,
      onLongPressHint: context.l10n.agendaDayAddHint,
      // The Semantics above is the long press screen readers hear: one
      // action, on the heading's own node — not a second, unlabeled one.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onLongPress: () {
          Feedback.forLongPress(context);
          add();
        },
        child: header,
      ),
    );
  }
}

/// The view chips, in a row that scrolls sideways when it does not fit —
/// its last 24 dp fading out then, so the rest is seen to be there.
class _ViewChips extends StatefulWidget {
  final AgendaView view;
  final Map<String, int> counts;

  /// The list picked (its name, or "Listesiz"), and its colour.
  final String? list;
  final Color? listColor;
  final bool listFiltered;
  final ValueChanged<AgendaView> onView;
  final VoidCallback onList;

  const _ViewChips({
    required this.view,
    required this.counts,
    required this.list,
    required this.listColor,
    required this.listFiltered,
    required this.onView,
    required this.onList,
  });

  @override
  State<_ViewChips> createState() => _ViewChipsState();
}

class _ViewChipsState extends State<_ViewChips> {
  /// More chips past the right edge: the fade shows.
  bool _more = false;

  /// Whether the row's end fades out now (for tests).
  @visibleForTesting
  bool get fading => _more;

  bool _onMetrics(ScrollMetrics m) {
    final more = m.extentAfter > 0.5;
    if (more != _more) {
      // Not during layout.
      scheduleMicrotask(() {
        if (mounted) setState(() => _more = more);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final view = widget.view;
    final inbox = widget.counts['undated'] ?? 0;
    final overdue = widget.counts['overdue'] ?? 0;
    Widget chip(AgendaView v, String label) => NokChip(
      label: label,
      selected: view == v,
      exclusive: true,
      onTap: view == v ? null : () => widget.onView(v),
    );
    final chips = <Widget>[
      chip(AgendaView.upcoming, l.agendaViewUpcoming),
      // A view with nothing in it has no chip — never a "0" (§7.15) —
      // unless it is the one shown.
      if (inbox > 0 || view == AgendaView.inbox)
        chip(
          AgendaView.inbox,
          inbox > 0
              ? l.agendaChipCount(l.agendaViewInbox, inbox)
              : l.agendaViewInbox,
        ),
      if (overdue > 0 || view == AgendaView.overdue)
        chip(
          AgendaView.overdue,
          overdue > 0
              ? l.agendaChipCount(l.agendaViewOverdue, overdue)
              : l.agendaViewOverdue,
        ),
      NokChip(
        label: l.agendaListChip(widget.list),
        selected: widget.listFiltered,
        dot: widget.listColor,
        icon: widget.listFiltered && widget.listColor == null
            ? Icons.format_list_bulleted_rounded
            : null,
        dropdown: true,
        onTap: widget.onList,
      ),
      chip(AgendaView.done, l.agendaViewDone),
    ];
    final row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: Gap.sm),
                chips[i],
              ],
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: [
            const Color(0xFFFFFFFF),
            const Color(0xFFFFFFFF),
            _more ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
          ],
          stops: [0, rect.width <= 24 ? 0 : 1 - 24 / rect.width, 1],
        ).createShader(rect),
        child: row,
      ),
    );
  }
}

/// The view on screen, around it always — so the view keeps its element
/// when a load starts or ends. While [loading] — the next view on its way —
/// it is as it was, then, once the wait passes [Motion.spinnerDelay], at
/// half strength; never tappable meanwhile.
class _Dimmed extends StatefulWidget {
  final bool loading;
  final Widget child;

  const _Dimmed({required this.loading, required this.child});

  @override
  State<_Dimmed> createState() => _DimmedState();
}

class _DimmedState extends State<_Dimmed> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _wait();
  }

  @override
  void didUpdateWidget(_Dimmed old) {
    super.didUpdateWidget(old);
    if (widget.loading == old.loading) return;
    _timer?.cancel();
    _timer = null;
    if (widget.loading) {
      _wait();
    } else {
      _dim = false;
    }
  }

  void _wait() {
    _timer = Timer(Motion.spinnerDelay, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: widget.loading,
    child: AnimatedOpacity(
      opacity: widget.loading && _dim ? 0.5 : 1,
      duration: Motion.orInstant(context, Motion.pressOut),
      child: widget.child,
    ),
  );
}

/// The first load's stand-in: a day heading over a card of rows.
class _AgendaSkeleton extends StatelessWidget {
  const _AgendaSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: Insets.rowH, vertical: 16),
      child: Row(
        children: [
          Bone(width: 24, height: 24, shape: BoneShape.block),
          SizedBox(width: 44),
          Expanded(child: Bone.text(lineHeight: 22)),
          SizedBox(width: 48),
        ],
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.md,
        Insets.gutter,
        0,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Gap.sm),
          child: Bone.text(width: 120),
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(children: [for (var i = 0; i < 4; i++) row()]),
        ),
      ],
    );
  }
}
