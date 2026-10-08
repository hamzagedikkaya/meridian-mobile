/// Taps that must show their result before the server answers — a habit
/// logged, a todo ticked off or reopened — on every screen that shows the
/// item, in the same frame.
///
/// Each action patches the cached read models (the same `homeProvider`,
/// `habitsProvider` and todo lists every screen watches) with the tap's
/// result, sends the write, and on failure takes the tap back. A patch is a pending edit (see
/// `FetchedNotifier`): a refetch that may have left before the server
/// answered gets it applied too, so the tick never flicks back and the
/// refetch's own news is kept. What the write changed is then refreshed by
/// `DataSync` like any other write, so derived numbers (streaks, completion
/// %, the perfect-day chain, goals that track the habit) come from the server.
///
/// Every write states the result the user asked for — a habit day's count,
/// a todo done or not — worked out once, from what the screen showed when
/// the tap landed. The server sets that state rather than flipping whatever
/// it has, so a screen that was out of date (the web changed it meanwhile, a
/// refetch is still on its way) can never turn a habit or a todo the wrong
/// way, and the pending edit sets the same result on every refetch.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import '../models/habit.dart';
import '../models/home.dart';
import '../models/todo.dart';
import 'current_day.dart';
import 'providers.dart';
import 'sync.dart';

/// What [model] shows now — the data its screens render, pending taps
/// included — or null while it shows nothing (never opened, or its first
/// fetch still on the way). Reading one that is due for a refetch starts
/// that refetch now; it lands with the tap applied to it.
T? _shown<T>(Ref ref, ProviderBase<AsyncValue<Fetched<T>>> model) =>
    ref.exists(model) ? ref.read(model).value?.data : null;

final habitActionsProvider = Provider<HabitActions>(HabitActions.new);

final class HabitActions {
  HabitActions(this._ref);

  final Ref _ref;

  /// Per habit, whether its latest tap went through, once the server has
  /// answered it. The habit's next tap is sent only after that.
  final _latest = <int, Future<bool>>{};

  /// Taps on screen that the server has not answered yet, of any habit.
  var _unanswered = 0;

  /// Whether a tap of [habitId] is still waiting for the server; a newer tap
  /// of it is sent after that one.
  bool isBusy(int habitId) => _latest.containsKey(habitId);

  /// Whether habit [habitId] is a daily one, as far as any habit payload
  /// read so far says; null when none named it (`/home` does not say).
  /// Safe to ask while building: it never starts a fetch. (A screen that
  /// must redraw once it is known watches `habitCadenceProvider`.)
  bool? isDaily(int habitId) => _ref.read(habitCadenceProvider)[habitId];

  Habit? _listed(int habitId) => _shown(_ref, habitsProvider)
      ?.habits
      .where((h) => h.id == habitId)
      .firstOrNull;

  /// Sets habit [habitId]'s log for today to [count] — the tap's result,
  /// worked out from what the user sees (the check ring: its target or 0;
  /// the counter: one step up or down) — on Today and on Habits at once,
  /// then sends it (`PUT /habits/:id/logs/:date`). The server's answer
  /// replaces the habit on both, so the Habits list needs no refetch.
  ///
  /// [day] is the date the tapped screen shows as today — `/home`'s `today`
  /// or the habit's `today.date` — which is the server's today, never the
  /// device's; without one, the first of those that is known. A screen
  /// whose day differs (one left over from before midnight) is not patched,
  /// and catches up from the write's refetch.
  ///
  /// No tap is dropped. When an earlier tap of the same habit is still
  /// waiting, this one shows at once and is sent after it, so the server
  /// ends on the last one. If that earlier tap fails, this one is taken back
  /// unsent and the result is false. A failure of this tap's own request is
  /// rethrown after the tap is taken back on both screens.
  Future<bool> setToday(int habitId, int count, {DateTime? day}) async {
    final earlier = _latest[habitId];
    final outcome = Completer<bool>();
    _latest[habitId] = outcome.future;
    _unanswered++;
    var answered = false;
    PendingEdit<HomeSummary>? home;
    PendingEdit<HabitsBundle>? habits;
    try {
      final summary = _shown(_ref, homeProvider);
      final listed = _listed(habitId);
      final DateTime logged = day ??
          summary?.today ??
          listed?.today.date ??
          _ref.read<DateTime>(currentDayProvider);
      // Patch only what is on screen, and only the screens that show that
      // day: a tab never opened fetches fresh when shown.
      final row = summary?.todayHabits.where((h) => h.id == habitId).firstOrNull;
      // Each patch is for [logged] only: applied to a refetch that brings
      // another day (midnight passed meanwhile), it changes nothing, so the
      // tap never shows on the new day's rows.
      if (row != null && (summary!.today == null || summary.today == logged)) {
        final daily = listed?.isDaily ?? isDaily(habitId) ?? true;
        final log = row.logFor(count, daily: daily);
        home = _ref.read(homeProvider.notifier).patch(
              (h) => h.today == null || h.today == logged
                  ? h.withHabitToday(habitId, log)
                  : h,
            );
      }
      if (listed != null && listed.today.date == logged) {
        final log = listed.logFor(count);
        habits = _ref.read(habitsProvider.notifier).patch(
              (b) => b.day == null || b.day == logged
                  ? b.withHabitToday(habitId, log)
                  : b,
            );
      }
      if (earlier != null && !await earlier) {
        // The earlier tap was taken back, and this one builds on it.
        home?.rollback();
        habits?.rollback();
        return false;
      }
      final result = await _ref
          .read(repositoryProvider)
          .setHabitLog(habitId, logged, count: count);
      answered = true;
      _unanswered--;
      _ref.read(habitCadenceProvider.notifier).learn([result.habit]);
      home?.confirm((h) => h.merge(result));
      _answerHabits(habits, result);
      return true;
    } catch (_) {
      home?.rollback();
      habits?.rollback();
      rethrow;
    } finally {
      if (!answered) _unanswered--;
      outcome.complete(answered);
      if (identical(_latest[habitId], outcome.future)) _latest.remove(habitId);
    }
  }

  /// Folds the server's answer into the Habits list: the habit as the server
  /// now has it and, once no other tap is waiting, the header (done count,
  /// perfect-day chain) as well. Until then the answer knows nothing of the
  /// taps still on their way, and its header would step the count back.
  ///
  /// The list then shows what a refetch would bring, so this write's own
  /// refetch of it is dropped — unless the answer is about another day than
  /// the list shows (a tap that straddled midnight: see
  /// [HabitsBundle.isDayOf]). The answer is then left out of the list, and
  /// the refetch brings the list as the server now has it.
  void _answerHabits(PendingEdit<HabitsBundle>? tap, HabitLogResult result) {
    final header = _unanswered == 0;
    HabitsBundle answer(HabitsBundle b) => b.merge(result, header: header);
    if (tap == null || !tap.confirm(answer)) {
      // No Habits list showed the tap. One opened since may have its first
      // fetch still on the way, sent before the answer: it gets the answer.
      if (!_ref.exists(habitsProvider)) return;
      _ref.read(habitsProvider.notifier).patch(answer).confirm();
    }
    final list = _shown(_ref, habitsProvider);
    if (list == null || list.isDayOf(result)) {
      _ref.read(dataSyncProvider).markFresh(habitsProvider);
    }
  }
}

/// A todo Today no longer lists, and the place it had there — what "undo"
/// puts back after a refetch dropped the finished todo from Today's open
/// todos.
typedef TodoPlace = ({Todo todo, int index});

final todoActionsProvider = Provider<TodoActions>(TodoActions.new);

final class TodoActions {
  TodoActions(this._ref);

  final Ref _ref;

  /// Per todo, whether its latest tap went through, once answered.
  final _latest = <int, Future<bool>>{};

  bool isBusy(int todoId) => _latest.containsKey(todoId);

  /// Marks todo [todoId] done, or open again ([done] false), on every
  /// screen that shows it at once — Today's checkbox with its open and
  /// overdue counts (the tab badge), and each todo list on screen with its
  /// counts — then sends that state (`PATCH /todos/:id/toggle` with
  /// `done`). The server's answer — the status it now has — stands until
  /// the refetch that follows lands, which drops a finished todo from the
  /// lists of open todos.
  ///
  /// [restore] is where the todo was: reopening one that a refetch already
  /// dropped puts it back there ("Geri al") — on Today, and in each todo
  /// list on screen that takes it by its filter.
  ///
  /// Taps of the same todo are sent in order, each after the one before is
  /// answered; when that one failed, this one is taken back unsent and the
  /// result is false. A failure of its own request is rethrown after every
  /// screen is rolled back.
  Future<bool> setDone(
    int todoId, {
    required bool done,
    TodoPlace? restore,
  }) async {
    final earlier = _latest[todoId];
    final outcome = Completer<bool>();
    _latest[todoId] = outcome.future;
    var answered = false;
    PendingEdit<HomeSummary>? tap;
    final listTaps = <PendingEdit<TodosBundle>>[];
    final reopening = !done && restore != null;
    HomeSummary shown(HomeSummary h, String status) =>
        status == 'done' || status == 'cancelled' || !reopening
            ? h.withTodoStatus(todoId, status)
            : h.withTodoReopened(restore.todo, index: restore.index);
    TodosBundle shownIn(TodosBundle b, String status) =>
        status == 'done' || status == 'cancelled' || !reopening
            ? b.withTodoStatus(todoId, status)
            : b.withTodoReopened(restore.todo, index: restore.index);
    try {
      final status = done ? 'done' : 'pending';
      final home = _shown(_ref, homeProvider);
      final today = home?.today ?? _ref.read<DateTime>(currentDayProvider);
      final listed = home?.upcomingTodos.any((t) => t.id == todoId) ?? false;
      // Put back on Today only what `/home` lists: open todos due within
      // the next seven days. Its counts for any other follow the refetch.
      final due = reopening ? restore.todo.dueDay : null;
      final belongs = due != null &&
          !due.isAfter(DateTime(today.year, today.month, today.day + 7));
      if (home != null && (listed || belongs)) {
        tap = _ref.read(homeProvider.notifier).patch((h) => shown(h, status));
      }
      for (final instance
          in _ref.container.allProviders(family: todosProvider).toList()) {
        final query = instance.provider.argument;
        if (query is! TodoQuery) continue;
        final model = todosProvider(query);
        final bundle = _shown(_ref, model);
        if (bundle == null) continue;
        final inList = bundle.todos.any((t) => t.id == todoId);
        if (!inList && !(reopening && query.admitsOpen(restore.todo, today))) {
          continue;
        }
        listTaps.add(
          _ref.read(model.notifier).patch((b) => shownIn(b, status)),
        );
      }
      if (earlier != null && !await earlier) {
        tap?.rollback();
        for (final listTap in listTaps) {
          listTap.rollback();
        }
        return false;
      }
      final answer = await _ref
          .read(repositoryProvider)
          .setTodoDone(todoId, done: done);
      answered = true;
      tap?.confirm((h) => shown(h, answer.status));
      for (final listTap in listTaps) {
        listTap.confirm((b) => shownIn(b, answer.status));
      }
      return true;
    } catch (_) {
      tap?.rollback();
      for (final listTap in listTaps) {
        listTap.rollback();
      }
      rethrow;
    } finally {
      outcome.complete(answered);
      if (identical(_latest[todoId], outcome.future)) _latest.remove(todoId);
    }
  }
}
