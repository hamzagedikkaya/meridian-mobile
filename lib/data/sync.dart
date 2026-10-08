/// Which cached screens show which server data — and the one place that
/// refreshes them.
///
/// The server's read models are aggregates. `GET /home` folds transactions
/// (month net, 7-day spending), habit logs (today's habits, streaks,
/// completion %, perfect day), todos, events and the top active goals into
/// one payload (meridian `Api::V1::HomeController`). `GET /finance/dashboard`
/// folds transactions, categories, budgets and subscriptions together.
/// `GET /goals` and `GET /goals/:id` recalculate financial goals from account
/// balances or total income and habit goals from completed logs on every read
/// (`Goals::CalculateProgress`) and store the result — which is all `/home`
/// shows of them: its top active goals carry the progress stored at the last
/// recalculation. So one write changes several screens, and the table below
/// says which — derived from what each endpoint returns, not from which
/// screen happened to make the write — and whenever both are due,
/// [DataSync.refresh] has the goals recalculated alongside `/home` and asks
/// `/home` again if that moved a goal it shows.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show
        AsyncProviderListenable,
        Family,
        ProviderBase,
        ProviderListenable,
        ProviderOrFamily;

import '../core/session.dart';
import '../models/goal.dart';
import '../models/home.dart';
import 'data_scope.dart';
import 'providers.dart';

/// The cached read models whose server response depends on [scope].
///
/// Families stand for every instance (each transactions filter, each goal
/// id, each journal range). Invalidating a model nobody shows costs nothing:
/// Riverpod only rebuilds active providers, a hidden tab's provider is paused
/// and refetches once when shown, and one that was never created is skipped.
Set<ProviderOrFamily> readModelsFor(DataScope scope) => switch (scope) {
      // Feeds list them; the dashboard sums them (month/year totals, six-month
      // series, category pie, budget spend, recent rows); balances are
      // computed from them, and an account's detail counts them (whether it
      // can still be deleted or change currency), as a category's does
      // (what its delete would leave uncategorized); a budget's spend sums
      // them; /home has month net and 7-day spending; financial goals track
      // an account balance or total income (and /home shows their progress
      // once the goals are recalculated). A transaction's detail is the row
      // and its linked pair.
      DataScope.transactions => {
          transactionsProvider,
          transactionDetailProvider,
          financeDashboardProvider,
          accountsProvider,
          accountDetailProvider,
          categoryUsageProvider,
          budgetsProvider,
          homeProvider,
          goalsProvider,
          goalDetailProvider,
        },
      // Account name, colour and currency are embedded in transaction rows
      // (and a transaction's linked pair), the dashboard's recent rows and
      // upcoming payments, subscriptions, and a financial goal's linked
      // account; an account's currency is
      // offered by the currency picker while it is in use; the opening
      // balance moves its balance and the progress of a financial goal that
      // tracks it, and with it /home's goal bars. A delete takes the
      // account's subscriptions with it and unlinks its goals (it declares
      // those scopes too).
      DataScope.accounts => {
          accountsProvider,
          accountDetailProvider,
          currenciesProvider,
          transactionsProvider,
          transactionDetailProvider,
          financeDashboardProvider,
          subscriptionsProvider,
          goalsProvider,
          goalDetailProvider,
          homeProvider,
        },
      // Which accounts there are, and which are archived: the account list
      // (carousel, pickers, archive page), the account itself, and the
      // currencies in use. Nothing else embeds whether one is archived.
      DataScope.accountList => {
          accountsProvider,
          accountDetailProvider,
          currenciesProvider,
        },
      // Category names, colours and nesting are embedded in transaction
      // rows, the dashboard's pie and budgets, budgets and subscriptions; a
      // category's delete takes its subcategories and budgets with it and
      // leaves its transactions and subscriptions uncategorized.
      DataScope.categories => {
          categoriesProvider,
          categoryUsageProvider,
          transactionsProvider,
          transactionDetailProvider,
          financeDashboardProvider,
          budgetsProvider,
          subscriptionsProvider,
        },
      // A new category is in the category lists, and an expense top-level
      // one is a place a budget can go.
      DataScope.categoryList => {
          categoriesProvider,
          categoryUsageProvider,
          budgetsProvider,
        },
      // The dashboard shows every budget; a category's detail says whether
      // it has one.
      DataScope.budgets => {
          budgetsProvider,
          financeDashboardProvider,
          categoryUsageProvider,
        },
      // The dashboard lists the upcoming ones; an account's and a category's
      // detail count them (an account with a subscription cannot change its
      // currency).
      DataScope.subscriptions => {
          subscriptionsProvider,
          financeDashboardProvider,
          accountDetailProvider,
          categoryUsageProvider,
        },
      // /home lists today's active habits and derives streaks, the week's
      // completion % and the perfect-day chain from them; a habit goal shows
      // its linked habit and counts its completed logs.
      DataScope.habits => {
          habitsProvider,
          habitDetailProvider,
          homeProvider,
          goalsProvider,
          goalDetailProvider,
        },
      // A check-in moves the habit's day, streak, chain and period, /home's
      // ring and stats, and a habit goal's progress (= its completed logs) —
      // on the Goals tab and in /home's goal bars.
      DataScope.habitLogs => {
          habitsProvider,
          habitDetailProvider,
          homeProvider,
          goalsProvider,
          goalDetailProvider,
        },
      // /home shows the top three active goals with their progress; an
      // account's detail counts the goals that track it (a delete would
      // unlink them).
      DataScope.goals => {
          goalsProvider,
          goalDetailProvider,
          homeProvider,
          accountDetailProvider,
        },
      // /home counts open and overdue todos (the Today tab's badge) and lists
      // the upcoming ones.
      DataScope.todos => {
          todosProvider,
          homeProvider,
        },
      // /home lists today's events and counts them.
      DataScope.events => {
          eventsTodayProvider,
          homeProvider,
        },
      // /home carries no journal data.
      DataScope.journal => {
          journalProvider,
          journalEntryProvider,
        },
      // Currency and time zone shape every aggregate the server reports (sums,
      // "today", day boundaries). The signed-in user itself (name, currency,
      // the greeting and avatar) is re-read as well — see [DataSync].
      DataScope.me => allReadModels,
    };

/// Whether a change to [scope] also changes the signed-in user (`GET /me`),
/// which lives in the session rather than in a read model.
bool changesSignedInUser(DataScope scope) => scope == DataScope.me;

/// The read model of [record] alone — its detail screen — for the kinds of
/// record that have one.
ProviderBase<Object?>? detailReadModelOf(DeletedRecord record) =>
    switch (record.scope) {
      DataScope.transactions => transactionDetailProvider(record.id),
      DataScope.accounts => accountDetailProvider(record.id),
      DataScope.categories => categoryUsageProvider(record.id),
      DataScope.habits => habitDetailProvider(record.id),
      DataScope.goals => goalDetailProvider(record.id),
      DataScope.journal => journalEntryProvider(record.id),
      _ => null,
    };

/// Every server read model the app caches.
Set<ProviderOrFamily> get allReadModels => {
      homeProvider,
      accountsProvider,
      accountDetailProvider,
      currenciesProvider,
      financeDashboardProvider,
      transactionsProvider,
      transactionDetailProvider,
      categoriesProvider,
      categoryUsageProvider,
      budgetsProvider,
      subscriptionsProvider,
      habitsProvider,
      habitDetailProvider,
      goalsProvider,
      goalDetailProvider,
      todosProvider,
      eventsTodayProvider,
      journalProvider,
      journalEntryProvider,
    };

/// Turns writes into refreshes, and is the one place anything is refreshed.
///
/// The repository reports every write here (see [WriteListener]); a write
/// invalidates [readModelsFor] each scope it changed. Because this lives as
/// long as the ProviderScope — unlike a screen's WidgetRef — a write still
/// refreshes everything when the screen that sent it was closed before the
/// answer came back.
///
/// Write-driven refreshes are batched, and held while any write is still in
/// flight: a refetch that starts mid-write could bring back pre-write data
/// over a tap that already shows the result. Explicit refreshes ([refresh],
/// [refreshAll]: pull-to-refresh, a tab re-tap, app resume) run at once.
/// Either way, when `/home` and the goals are both due, the goals'
/// recalculation runs alongside `/home` (see [refresh]).
final class DataSync implements WriteListener {
  DataSync(this._container);

  final ProviderContainer _container;

  /// Read models finished writes left out of date, each with how many writes
  /// did, so [markFresh] can withdraw one write's refetch without cancelling
  /// another's.
  final _dirty = <ProviderOrFamily, int>{};

  /// Details of records finished writes deleted: left out of the next
  /// refresh, which could only get a 404 for them.
  final _deleted = <ProviderBase<Object?>>{};

  var _userDirty = false;
  var _writesInFlight = 0;
  Timer? _flush;
  var _disposed = false;

  /// Refreshes of `/home` and the goals so far: only the latest one's
  /// recalculation may still ask `/home` again (see [refresh]).
  var _recalculations = 0;

  /// Writes sent and not yet answered.
  int get writesInFlight => _writesInFlight;

  @override
  void writeStarted() => _writesInFlight++;

  @override
  void writeFinished(Set<DataScope> changed, {DeletedRecord? deleted}) {
    if (_writesInFlight > 0) _writesInFlight--;
    // Once per write, however many of its scopes name a model.
    final models = {for (final scope in changed) ...readModelsFor(scope)};
    for (final model in models) {
      _dirty.update(model, (writes) => writes + 1, ifAbsent: () => 1);
    }
    final gone = deleted == null ? null : detailReadModelOf(deleted);
    if (gone != null) _deleted.add(gone);
    if (changed.any(changesSignedInUser)) _userDirty = true;
    _scheduleFlush();
  }

  /// [model] already shows what the server would now return for the write
  /// that just finished — its own response was applied to it — so that
  /// write's refetch of [model] is dropped. Another write that also changed
  /// [model] still refetches it. Must be called right after the write's
  /// future completes: the queued refetch runs on the next event-loop turn.
  void markFresh(ProviderOrFamily model) {
    final writes = _dirty[model];
    if (writes == null) return;
    if (writes <= 1) {
      _dirty.remove(model);
    } else {
      _dirty[model] = writes - 1;
    }
  }

  /// Refetches [models] now — every instance of a family, except the ones in
  /// [except]. Screens keep showing their current data while the new data
  /// loads, and each fetch gets its own quick retry (see `retried`).
  ///
  /// When [models] include both `/home` and the goals, `/home` is still asked
  /// at once, and the goals alongside it. `/home` shows each goal's progress
  /// as the server stored it, and the server recalculates and stores it only
  /// when the goals are read (`GET /goals`), so a `/home` answered before
  /// that may show the old progress. Once the goals are in — and `/home`'s
  /// own fetch has landed — `/home` is asked once more, but only if a goal
  /// it shows is no longer active or not at the progress the recalculation
  /// stored. Neither waits for the other: when the server cannot be reached,
  /// Today says so as soon as `/home` itself fails.
  void refresh(
    Iterable<ProviderOrFamily> models, {
    Set<ProviderBase<Object?>> except = const {},
  }) {
    if (_disposed) return;
    final batch = models.toSet();
    final recalculate =
        batch.contains(homeProvider) && batch.remove(goalsProvider);
    for (final model in batch) {
      switch (model) {
        case ProviderBase<Object?>() when except.contains(model):
          break;
        case Family() when except.any((p) => p.from == model):
          for (final instance in _container.allProviders(family: model)) {
            if (!except.contains(instance.provider)) {
              _invalidate(instance.provider);
            }
          }
        default:
          _invalidate(model);
      }
    }
    if (recalculate) {
      _invalidate(goalsProvider);
      unawaited(_recalculateGoalsFor(++_recalculations));
    }
  }

  void _invalidate(ProviderOrFamily model) => _container.invalidate(model);

  /// Has the server recalculate every goal — which it does on `GET /goals` —
  /// then asks `/home` again if its goal bars predate that (see [refresh]).
  /// [round] is this refresh's number: a newer refresh of both does its own.
  ///
  /// The goals are read through the Goals tab's read model, created for the
  /// read when there is no Goals tab: a tab's refetch is not doubled by a
  /// second `GET /goals`, a hidden tab's refetch runs now instead of when the
  /// tab is shown, and the read gets the quick retry like any other.
  Future<void> _recalculateGoalsFor(int round) async {
    final goals = await _landed(goalsProvider);
    if (goals == null || !_isLatest(round)) return;
    if (!_container.exists(homeProvider)) return;
    final home = await _landed(homeProvider);
    // A `/home` that failed is on screen as such: its retry asks again.
    if (home == null || !_isLatest(round)) return;
    if (!_showsProgressOf(home.data, goals.data)) _invalidate(homeProvider);
  }

  bool _isLatest(int round) => !_disposed && round == _recalculations;

  /// What [model] shows once its fetch in flight, if any, has landed; null
  /// when that failed. Listened to meanwhile, so a fetch that waits for its
  /// screen to be shown again runs now.
  ///
  /// It watches the state rather than `future`, which a tap made meanwhile
  /// completes early with the data it patched (see `FetchedNotifier`).
  Future<T?> _landed<T>(ProviderListenable<AsyncValue<T>> model) async {
    final landed = Completer<T?>();
    final subscription = _container.listen<AsyncValue<T>>(
      model,
      (_, next) {
        if (next.isLoading || landed.isCompleted) return;
        landed.complete(next.hasError ? null : next.value);
      },
      fireImmediately: true,
    );
    try {
      return await landed.future;
    } finally {
      subscription.close();
    }
  }

  /// Whether `/home`'s goal bars show what the goals' recalculation stored:
  /// each goal `/home` shows is still active, at the same progress. (Which
  /// goals `/home` picks for its top three is the server's call; a goal the
  /// recalculation moves into them shows with the next refresh.)
  static bool _showsProgressOf(HomeSummary home, GoalsBundle goals) {
    final stored = {
      for (final goal in goals.active) goal.id: goal.progressPercent,
    };
    return home.activeGoals
        .every((goal) => stored[goal.id] == goal.progressPercent);
  }

  /// A record of [scope] is gone — [detail], the read model of that one
  /// record, was just answered 404 because it was deleted on the web or
  /// another device. Every other read model that may still show it refetches
  /// now; [detail] itself is left alone (asking again would only 404 again).
  void recordGone(DataScope scope, {required ProviderOrFamily detail}) =>
      refresh(readModelsFor(scope).where((model) => model != detail));

  /// Refetches every read model — visible ones at once, hidden tabs when they
  /// are next shown — and the signed-in user (name, currency; the greeting and
  /// avatar), which may have changed on the web.
  void refreshAll() {
    refresh(allReadModels);
    _refreshSignedInUser();
  }

  void _refreshSignedInUser() {
    if (_disposed) return;
    // Never throws, and does nothing unless someone is signed in.
    unawaited(_container.read(sessionProvider.notifier).refreshMe());
  }

  void _scheduleFlush() {
    if (_disposed ||
        _flush != null ||
        _writesInFlight > 0 ||
        (_dirty.isEmpty && !_userDirty)) {
      return;
    }
    // The next event-loop turn rather than a microtask: whatever awaited the
    // write resumes first, so it can still apply the response and call
    // [markFresh] for what that made current.
    _flush = Timer(Duration.zero, () {
      _flush = null;
      // Another write started meanwhile; the last one to finish flushes.
      if (_writesInFlight > 0) return;
      final batch = _dirty.keys.toList();
      final deleted = {..._deleted};
      final user = _userDirty;
      _dirty.clear();
      _deleted.clear();
      _userDirty = false;
      refresh(batch, except: deleted);
      if (user) _refreshSignedInUser();
    });
  }

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    _flush = null;
    _dirty.clear();
    _deleted.clear();
    _userDirty = false;
  }
}

final dataSyncProvider = Provider<DataSync>((ref) {
  final sync = DataSync(ref.container);
  ref.onDispose(sync.dispose);
  return sync;
});

/// What a pull-to-refresh spinner waits for: [results], but at most
/// [timeout], and never an exception — a failed refetch is already on screen
/// through the provider's error state (offline banner or error view), so the
/// gesture only has to end. [minimum] keeps a very fast refresh from
/// flashing the spinner.
Future<void> settleRefresh(
  Iterable<Future<Object?>> results, {
  Duration timeout = const Duration(seconds: 12),
  Duration minimum = Duration.zero,
}) async {
  Future<void> quietly(Future<Object?> result) async {
    try {
      await result;
    } catch (_) {
      // Reported by the provider's AsyncError.
    }
  }

  try {
    await Future.wait<void>([
      for (final result in results) quietly(result),
      if (minimum > Duration.zero) Future<void>.delayed(minimum),
    ]).timeout(timeout);
  } catch (_) {
    // Timed out: let the spinner go; the refetch carries on in the background.
  }
}

/// [model]'s fetch in flight landing, for [settleRefresh] — what a
/// pull-to-refresh of a read model a tap can patch (`FetchedNotifier`)
/// waits for. Its `future` alone may complete early: a tap made meanwhile
/// puts the data it patched on screen, which completes it, while the fetch
/// carries on. So it is asked for again while [model] is still loading.
/// Never throws.
Future<void> refetchLanded(
  WidgetRef ref,
  AsyncProviderListenable<Object?> model,
) async {
  Future<Object?>? last;
  while (ref.context.mounted) {
    final future = ref.read(model.future);
    // Loading still, yet the same future: never wait on it twice.
    if (identical(future, last)) return;
    last = future;
    try {
      await future;
    } catch (_) {
      // Reported by the provider's AsyncError.
    }
    if (!ref.context.mounted || !ref.read(model).isLoading) return;
  }
}
