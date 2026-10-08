/// Data-layer providers (Riverpod 3, no codegen).
///
/// Read pattern for screens: `ref.watch(x)` yields an `AsyncValue<Fetched<T>>`.
/// Render `.value` (nullable) so the last-good value persists across a
/// refetch and a failed refresh — Riverpod 3 carries the previous value through
/// loading and error states, so `hasValue` stays true. The rest is decided by
/// `AsyncScreenState` (ui/widgets/sync_hint.dart), the same on every screen:
/// the `OfflineBanner` (with `Fetched.at`) when `refreshFailed`, a skeleton
/// only for `isFirstLoad`, the full error view for `hasFailed`, and the thin
/// `SyncHint` line while `isRefetching` — data on screen is never replaced by
/// a skeleton or a spinner while newer data loads.
///
/// Nothing here is refreshed by the screens themselves. Writes report what
/// they changed and `DataSync` (sync.dart) invalidates every read model that
/// shows it; local midnight, app resume, tab re-taps and pull-to-refresh go
/// through the same place.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderOrFamily;

import '../core/api.dart';
import '../core/session.dart';
import '../models/account.dart';
import '../models/budget.dart';
import '../models/currency.dart';
import '../models/event.dart';
import '../models/finance_category.dart';
import '../models/finance_dashboard.dart';
import '../models/goal.dart';
import '../models/subscription.dart';
import '../models/habit.dart';
import '../models/home.dart';
import '../models/journal.dart';
import '../models/todo.dart';
import '../models/transaction.dart';
import 'current_day.dart';
import 'data_scope.dart';
import 'repository.dart';
import 'sync.dart';

/// Wraps fetched data with the moment it was retrieved (for the offline
/// banner, and to tell when it is due for a refetch — see [staleAfter]).
class Fetched<T> {
  final T data;
  final DateTime at;
  const Fetched(this.data, this.at);

  /// Whether this was fetched at least [after] before [now].
  bool olderThan(Duration after, DateTime now) => now.difference(at) >= after;
}

final repositoryProvider = Provider<MeridianRepository>((ref) {
  return MeridianRepository(
    ref.watch(dioProvider),
    writes: ref.watch(dataSyncProvider),
  );
});

// --- Shared read-model plumbing ----------------------------------------------

/// How old data may be before showing it again refetches it in the background.
const staleAfter = Duration(minutes: 1);

/// The `retry` of every read model: none from Riverpod. A read model retries
/// inside its fetch instead (see [retried]).
Duration? _retriedInFetch(int _, Object _) => null;

/// Runs [attempt] — a request of a read model's fetch — and runs it once more
/// when it fails the way the app's retry policy gives a second try (see
/// `readRetry`: a refused connection or a 5xx), after the policy's delay.
///
/// The retry is part of the fetch, not Riverpod's automatic retry (which the
/// read models turn off: see [_retriedInFetch]), so a screen sees one fetch
/// that lands or fails, never the attempt in between. A blip the retry heals
/// never shows the offline banner, and a failure already on screen — the
/// banner, the error view — stays up while a refresh or a retry runs: it is
/// not withdrawn for the length of a quick retry and then shown again (see
/// `AsyncScreenState`).
///
/// The policy is the ProviderScope's `retry` ([readRetry] in the app, and
/// when none is set), so a test can turn it off. A wait cut short because
/// [ref]'s provider rebuilt or was disposed gives up with the attempt's error.
Future<T> retried<T>(Ref ref, Future<T> Function() attempt) async {
  final policy = ref.container.retry ?? readRetry;
  for (var retries = 0;; retries++) {
    try {
      return await attempt();
    } catch (error) {
      final wait = policy(retries, error);
      if (wait == null || !ref.mounted || !await _pause(ref, wait)) rethrow;
    }
  }
}

/// Waits [wait], unless [ref]'s provider rebuilds or is disposed first —
/// true when the wait ran its course. Nothing is left pending either way.
Future<bool> _pause(Ref ref, Duration wait) {
  final waited = Completer<bool>();
  final timer = Timer(wait, () => waited.complete(true));
  ref.onDispose(() {
    timer.cancel();
    if (!waited.isCompleted) waited.complete(false);
  });
  return waited.future;
}

extension RevalidateOnShow on Ref {
  /// Refetches in the background when this read model's screen becomes
  /// visible again — a tab switched back to, a covering route popped — and
  /// its data is older than [after]. That is what picks up edits made on the
  /// web while the app sat on another tab.
  ///
  /// A hidden screen's subscription is paused (flutter_riverpod pauses
  /// `ref.watch` under a disabled TickerMode), and Riverpod calls `onResume`
  /// when it is shown again. A Ref may not be used inside that callback, so
  /// the check hops to a microtask; it does nothing if the provider rebuilt in
  /// between, because the captured ref is then no longer mounted.
  ///
  /// This only sees a screen come back when nothing else kept its read model
  /// listened to meanwhile. The tab bar keeps `/home` live under every tab
  /// (for its badge), so switching back to Today is checked by the bar
  /// itself (see `AppScaffold`).
  void revalidateOnShow({Duration after = staleAfter}) {
    final clock = read(clockProvider);
    final builtAt = clock();
    onResume(() {
      if (clock().difference(builtAt) < after) return;
      scheduleMicrotask(() {
        if (mounted) invalidateSelf();
      });
    });
  }
}

/// The body every read model shares: fetch with the quick retry ([retried]),
/// stamp the result with its fetch time, refetch when the day rolls over
/// ([dateRelative]) and revalidate when shown again after [staleAfter].
///
/// A read model of one record (a detail screen) names the [recordOf] scope
/// the record belongs to and itself as [detail]: when the server answers 404
/// — the record was deleted on the web or another device — every list that
/// may still show it refetches at once (see [DataSync.recordGone]), so going
/// back does not land on a ghost row.
Future<Fetched<T>> fetched<T>(
  Ref ref,
  Future<T> Function(MeridianRepository repo) load, {
  bool dateRelative = true,
  DataScope? recordOf,
  ProviderOrFamily? detail,
}) async {
  if (dateRelative) ref.watch(currentDayProvider);
  ref.revalidateOnShow();
  // The clock [staleAfter] is measured by, so `Fetched.at` and the
  // revalidation checks agree.
  final clock = ref.read(clockProvider);
  final repo = ref.watch(repositoryProvider);
  try {
    return Fetched(await retried(ref, () => load(repo)), clock());
  } on ApiException catch (e) {
    if (recordOf != null &&
        detail != null &&
        e.kind == ApiErrorKind.notFound &&
        ref.mounted) {
      ref.read(dataSyncProvider).recordGone(recordOf, detail: detail);
    }
    rethrow;
  }
}

/// A read model a tap can rewrite before the server answers.
///
/// Only Today and Habits need this: a habit or todo tick must flip on screen
/// in the same frame, on every tab that shows it. Everything else simply
/// refetches.
///
/// What it shows is the last fetched value with every pending tap applied on
/// top, oldest first. A tap stays pending until a fetch that left after the
/// server answered it has landed — that fetch has the tap in it already. So a
/// fetch that was in flight when the tap landed is never thrown away (it may
/// carry a new day, or a habit added on the web), and never flicks the tick
/// back either: it is shown with the tap applied to it. A pending tap sets
/// its result rather than toggling, so that holds as well for a fetch that
/// left after the server applied the tap but before its answer arrived.
abstract class FetchedNotifier<T> extends AsyncNotifier<Fetched<T>> {
  /// Taps not yet known to be in a fetched value, oldest first.
  final _pending = <PendingEdit<T>>[];

  /// Fetches started so far. Numbering them tells which fetches may have
  /// left before the server answered a tap.
  var _fetches = 0;

  /// The last fetched value, exactly as the server sent it.
  Fetched<T>? _fetched;

  /// Whether the latest fetch is still on its way.
  var _fetching = false;

  /// How the last fetch that finished failed; null once one succeeds.
  ({Object error, StackTrace stackTrace})? _failure;

  Future<T> load(MeridianRepository repo);

  @override
  Future<Fetched<T>> build() async {
    final fetch = ++_fetches;
    _fetching = true;
    try {
      final result = await fetched(ref, load);
      // A newer fetch started meanwhile, and Riverpod drops this result.
      if (fetch != _fetches) return result;
      _fetched = result;
      _failure = null;
      // A fetch that left after the server answered a tap has that tap in it.
      _pending.removeWhere((edit) => edit._answeredBefore(fetch));
      return _withPending(result);
    } catch (error, stackTrace) {
      if (fetch == _fetches) {
        _failure = (error: error, stackTrace: stackTrace);
      }
      rethrow;
    } finally {
      if (fetch == _fetches) _fetching = false;
    }
  }

  Fetched<T> _withPending(Fetched<T> base) {
    if (_pending.isEmpty) return base;
    var data = base.data;
    for (final edit in _pending) {
      data = edit._edit(data);
    }
    return Fetched(data, base.at);
  }

  bool get _mounted => ref.mounted;

  /// Puts the last fetched value, with the pending taps on it, on screen,
  /// and keeps what the screen showed besides the data: a fetch still on its
  /// way (the hint) and a last refresh that failed (the offline banner) —
  /// a tap neither ends the one nor withdraws the other.
  ///
  /// Writes [state] without reading it: a read would run a rebuild that is
  /// due first. Riverpod has no public way to set a value that is loading or
  /// failed, but it carries the value just set through an error and a
  /// loading state set after it, so those are set after it.
  void _show() {
    final base = _fetched;
    if (base == null || !ref.mounted) return;
    state = AsyncData(_withPending(base));
    if (_failure case final failure?) {
      state = AsyncError(failure.error, failure.stackTrace);
    }
    if (_fetching) state = const AsyncLoading();
  }

  /// Rewrites what is shown now with [edit], a tap's expected result,
  /// keeping the fetch time, and keeps applying it to every fetched value
  /// until the server's answer is in one (see [PendingEdit]). With nothing
  /// fetched yet, the edit waits for the first fetch.
  ///
  /// [edit] must *set* that result — worked out from what was on screen
  /// when the tap landed — rather than toggle: a fetch that lands before
  /// the answer may already have the tap in it, and must stay as it is.
  PendingEdit<T> patch(T Function(T data) edit) {
    // A build overridden in a test never runs ours: start from its value.
    if (_fetches == 0) _fetched ??= state.value;
    final pending = PendingEdit<T>._(this, edit);
    _pending.add(pending);
    _show();
    return pending;
  }
}

/// A tap's rewrite of a [FetchedNotifier]'s data, from the tap until a
/// fetched value has the server's answer to it in.
final class PendingEdit<T> {
  PendingEdit._(this._owner, this._edit);

  final FetchedNotifier<T> _owner;
  T Function(T data) _edit;

  /// The owner's fetch count when the server answered: fetches up to this
  /// one may have left before the answer. Null until it is answered.
  int? _answeredAt;

  bool _answeredBefore(int fetch) {
    final answeredAt = _answeredAt;
    return answeredAt != null && answeredAt < fetch;
  }

  /// The write went through. [answer], the data as the server's response
  /// says it now is, replaces the expected result; without one the expected
  /// result stands. Either way it is applied to every fetch that may have
  /// left before the answer, until one that left after it lands.
  ///
  /// Returns false when nothing shows this edit any more: its read model
  /// was disposed, and one opened since starts from a fetch of its own.
  bool confirm([T Function(T data)? answer]) {
    if (!_owner._mounted) return false;
    if (answer != null) _edit = answer;
    _answeredAt = _owner._fetches;
    _owner._show();
    return true;
  }

  /// The write failed: the tap is taken back, and the data shows as fetched
  /// with only the other pending taps on it.
  void rollback() {
    if (_owner._pending.remove(this)) _owner._show();
  }
}

// --- Screen providers: AsyncValue<Fetched<T>> --------------------------------

final homeProvider =
    AsyncNotifierProvider.autoDispose<HomeNotifier, Fetched<HomeSummary>>(
  HomeNotifier.new,
  retry: _retriedInFetch,
);

/// `/home`'s goal bars are each goal's progress as the server stored it the
/// last time it recalculated the goals, which only reading them does. A
/// refresh of both — after a transaction or a check-in, say — asks `/home`
/// at once anyway, alongside the goals, and asks it again only if the
/// recalculation moved a goal it shows (see [DataSync.refresh]).
class HomeNotifier extends FetchedNotifier<HomeSummary> {
  @override
  Future<HomeSummary> load(MeridianRepository repo) async {
    final home = await repo.fetchHome();
    // `/home` does not say how often a habit repeats, which decides whether
    // Today counts a habit done several times a day or shows its day done
    // or not. The Habits list says: it is read once for the habits no habit
    // payload has named yet.
    if (ref.mounted) {
      ref.read(habitCadenceProvider.notifier).learnOf([
        for (final habit in home.todayHabits)
          if (habit.targetCount > 1) habit.id,
      ]);
    }
    return home;
  }
}

/// Every account, archived ones included (they follow the active ones): the
/// carousel and the pickers show the active ones, the archive page the
/// others, and an archived account still opens.
final accountsProvider = FutureProvider.autoDispose<Fetched<List<Account>>>(
  // Balances add up every transaction regardless of date.
  (ref) => fetched(ref, (r) => r.fetchAccounts(), dateRelative: false),
  retry: _retriedInFetch,
);

/// One account with what is recorded on it (GET /accounts/:id): whether it
/// can be deleted, and whether its currency can still change.
final FutureProviderFamily<Fetched<AccountDetail>, int> accountDetailProvider =
    FutureProvider.autoDispose.family<Fetched<AccountDetail>, int>(
  (ref, id) => fetched(
    ref,
    (r) => r.fetchAccount(id),
    dateRelative: false,
    recordOf: DataScope.accounts,
    detail: accountDetailProvider,
  ),
  retry: _retriedInFetch,
);

/// The currencies a new account can be opened in (GET /currencies).
final currenciesProvider = FutureProvider.autoDispose<Fetched<CurrenciesBundle>>(
  (ref) => fetched(ref, (r) => r.fetchCurrencies(), dateRelative: false),
  retry: _retriedInFetch,
);

/// One category and what a delete or a type change would touch
/// (GET /finance_categories/:id).
final FutureProviderFamily<Fetched<CategoryUsage>, int> categoryUsageProvider =
    FutureProvider.autoDispose.family<Fetched<CategoryUsage>, int>(
  (ref, id) => fetched(
    ref,
    (r) => r.fetchCategory(id),
    dateRelative: false,
    recordOf: DataScope.categories,
    detail: categoryUsageProvider,
  ),
  retry: _retriedInFetch,
);

/// Every budget with its month-to-date spend, and the categories a new one
/// can go on (GET /budgets). The spend is counted up to today.
final budgetsProvider = FutureProvider.autoDispose<Fetched<BudgetsBundle>>(
  (ref) => fetched(ref, (r) => r.fetchBudgets()),
  retry: _retriedInFetch,
);

/// Every subscription, active and paused, with what they cost
/// (GET /subscriptions). Nothing in it moves with the date: a due date
/// stays until a payment is recorded.
final subscriptionsProvider =
    FutureProvider.autoDispose<Fetched<SubscriptionsBundle>>(
  (ref) => fetched(ref, (r) => r.fetchSubscriptions(), dateRelative: false),
  retry: _retriedInFetch,
);

final financeDashboardProvider =
    FutureProvider.autoDispose<Fetched<FinanceDashboard>>(
  (ref) => fetched(ref, (r) => r.fetchFinanceDashboard()),
  retry: _retriedInFetch,
);

final habitsProvider =
    AsyncNotifierProvider.autoDispose<HabitsNotifier, Fetched<HabitsBundle>>(
  HabitsNotifier.new,
  retry: _retriedInFetch,
);

class HabitsNotifier extends FetchedNotifier<HabitsBundle> {
  @override
  Future<HabitsBundle> load(MeridianRepository repo) async {
    final bundle = await repo.fetchHabits();
    if (ref.mounted) {
      ref.read(habitCadenceProvider.notifier).learn(bundle.habits);
    }
    return bundle;
  }
}

/// How often each habit repeats, as last read — which `/home` does not say,
/// and Today needs: a daily habit done several times a day counts up per
/// tap, a weekly or monthly one is done or not for the day.
///
/// The state is whether each habit is a daily one, by id. It is filled by
/// every habit payload the app reads (the Habits list, a habit's detail, a
/// log's answer), and for Today by one read of the Habits list when `/home`
/// lists a habit none of them named ([HabitCadence.learnOf]). Watching it
/// redraws a screen once a cadence turns up; reading it never starts a
/// fetch, so a screen can ask while it builds.
final habitCadenceProvider =
    NotifierProvider<HabitCadence, Map<int, bool>>(HabitCadence.new);

final class HabitCadence extends Notifier<Map<int, bool>> {
  /// Whether a read of the Habits list for [learnOf] is on its way.
  var _reading = false;

  /// None known yet: a habit is missing until a habit payload names it.
  @override
  Map<int, bool> build() => const {};

  void learn(Iterable<Habit> habits) {
    Map<int, bool>? learned;
    for (final habit in habits) {
      if (state[habit.id] == habit.isDaily) continue;
      (learned ??= {...state})[habit.id] = habit.isDaily;
    }
    if (learned != null) state = learned;
  }

  /// Makes sure the cadence of each of [habitIds] gets known: when one is
  /// not, the Habits list is read once and learned from. It is read through
  /// the Habits tab's read model — created for the read, and let go after
  /// it, when the tab is not open — so an open tab is not asked twice, a
  /// hidden one due for a refetch is brought up to date now, and the read
  /// gets the quick retry like any other. Nothing is read while a read is on
  /// its way, or when every cadence is known; a read that failed is tried
  /// again with the next `/home`.
  void learnOf(Iterable<int> habitIds) {
    if (_reading || habitIds.every(state.containsKey)) return;
    _reading = true;
    unawaited(_readList().whenComplete(() => _reading = false));
  }

  Future<void> _readList() async {
    final landed = Completer<void>();
    final subscription =
        ref.container.listen<AsyncValue<Fetched<HabitsBundle>>>(
      habitsProvider,
      (_, next) {
        if (next.isLoading || landed.isCompleted) return;
        final bundle = next.value?.data;
        if (bundle != null) learn(bundle.habits);
        landed.complete();
      },
      fireImmediately: true,
    );
    try {
      await landed.future;
    } finally {
      subscription.close();
    }
  }
}

/// One habit with an 84-day chain (the detail sheet).
final FutureProviderFamily<Fetched<Habit>, int> habitDetailProvider =
    FutureProvider.autoDispose.family<Fetched<Habit>, int>(
  (ref, id) => fetched(
    ref,
    (r) async {
      final habit = await r.fetchHabit(id, days: 84);
      if (ref.mounted) ref.read(habitCadenceProvider.notifier).learn([habit]);
      return habit;
    },
    recordOf: DataScope.habits,
    detail: habitDetailProvider,
  ),
  retry: _retriedInFetch,
);

final goalsProvider = FutureProvider.autoDispose<Fetched<GoalsBundle>>(
  (ref) => fetched(ref, (r) => r.fetchGoals()),
  retry: _retriedInFetch,
);

/// One goal, recalculated by the server on every read (GET /goals/:id).
final FutureProviderFamily<Fetched<Goal>, int> goalDetailProvider =
    FutureProvider.autoDispose.family<Fetched<Goal>, int>(
  (ref, id) => fetched(
    ref,
    (r) => r.fetchGoal(id),
    recordOf: DataScope.goals,
    detail: goalDetailProvider,
  ),
  retry: _retriedInFetch,
);

final categoriesProvider =
    FutureProvider.autoDispose<Fetched<List<TxCategory>>>(
  (ref) => fetched(ref, (r) => r.fetchCategories(), dateRelative: false),
  retry: _retriedInFetch,
);

final eventsTodayProvider = FutureProvider.autoDispose<Fetched<List<Event>>>(
  (ref) {
    final today = ref.watch(currentDayProvider);
    return fetched(ref, (r) => r.fetchEvents(from: today, to: today));
  },
  retry: _retriedInFetch,
);

// --- Family screen providers -------------------------------------------------

final journalProvider =
    FutureProvider.autoDispose.family<Fetched<JournalBundle>, String>(
  (ref, range) => fetched(ref, (r) => r.fetchJournal(range: range)),
  retry: _retriedInFetch,
);

/// Single journal entry (GET /journal_entries/:id) for the detail screen.
final FutureProviderFamily<Fetched<JournalEntry>, int> journalEntryProvider =
    FutureProvider.autoDispose.family<Fetched<JournalEntry>, int>(
  (ref, id) => fetched(
    ref,
    (r) => r.fetchJournalEntry(id),
    dateRelative: false,
    recordOf: DataScope.journal,
    detail: journalEntryProvider,
  ),
  retry: _retriedInFetch,
);

final todosProvider =
    FutureProvider.autoDispose.family<Fetched<TodosBundle>, String>(
  (ref, filter) => fetched(ref, (r) => r.fetchTodos(filter: filter)),
  retry: _retriedInFetch,
);

// --- Transactions: infinite-scroll AsyncNotifier family ----------------------

/// Immutable filter key for the transactions feed. It is the `.family`
/// argument, so a distinct set of filters gets its own independent notifier
/// instance + cache — there is no shared, racy `setFilters`.
///
/// Usage (screens own their filters and pass them as the family key):
///   final feed = ref.watch(transactionsProvider(TxFilters(accountId: id)));
///   ref.read(transactionsProvider(filters).notifier).loadMore();
/// İşlemler passes the user's chosen filters; Hesap Detay passes
/// `TxFilters(accountId: x)`; both stay isolated even when visible together.
@immutable
class TxFilters {
  final String? kind;
  final int? accountId;
  final int? categoryId;

  /// Only the transactions without a category (`category_id=none`); wins
  /// over [categoryId].
  final bool uncategorized;

  /// With [accountId]: also the other accounts' transfers into it, so the
  /// account's history adds up to its balance.
  final bool includeIncomingTransfers;
  final DateTime? from;
  final DateTime? to;

  const TxFilters({
    this.kind,
    this.accountId,
    this.categoryId,
    this.uncategorized = false,
    this.includeIncomingTransfers = false,
    this.from,
    this.to,
  });

  /// An account's history: its own transactions and the transfers into it.
  const TxFilters.account(int this.accountId)
      : kind = null,
        categoryId = null,
        uncategorized = false,
        includeIncomingTransfers = true,
        from = null,
        to = null;

  @override
  bool operator ==(Object other) =>
      other is TxFilters &&
      other.kind == kind &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.uncategorized == uncategorized &&
      other.includeIncomingTransfers == includeIncomingTransfers &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, accountId, categoryId, uncategorized,
      includeIncomingTransfers, from, to);
}

/// Accumulated pages for the İşlemler feed.
class TransactionsFeed {
  final List<Transaction> items;
  final TransactionMeta meta;
  final bool hasMore;
  final DateTime at;

  const TransactionsFeed({
    required this.items,
    required this.meta,
    required this.hasMore,
    required this.at,
  });
}

class TransactionsNotifier extends AsyncNotifier<TransactionsFeed> {
  TransactionsNotifier(this._filters);

  /// The most pages a refetch reloads (250 rows), one after another: the
  /// rows a refresh can change (a new transaction lands near the top, an
  /// edit or delete usually is of a recent one) at a bounded cost.
  static const reloadPages = 5;

  final TxFilters _filters;

  /// The feed as it is on screen — kept by hand rather than read from
  /// `state` while a rebuild runs.
  TransactionsFeed? _shown;

  /// Rows the app saved itself and put in place ([replaceLocally]) since
  /// the last refetch landed, by id — kept where their date sorts by the
  /// refetch too (see [_withTail]).
  final _placed = <int, Transaction>{};

  /// Bumped by every rebuild, so a `loadMore` that was in flight cannot
  /// append a page of the old feed to the new one.
  int _generation = 0;
  bool _loadingMore = false;

  MeridianRepository get _repo => ref.read(repositoryProvider);

  @override
  Future<TransactionsFeed> build() async {
    ref.watch(repositoryProvider); // rebuild if the dio/base URL changes
    ref.revalidateOnShow();
    final generation = ++_generation;
    final before = _shown;
    // A refetch (after a write, on resume, on a re-tap, on a delete) reloads
    // the pages that were on screen, one after another — up to
    // [reloadPages] — and keeps the rows loaded beyond them (see
    // [_withTail]), so the list keeps its length and the scroll position
    // holds: the user stays where they were. The feed stays on screen until
    // the reload is in. Each page gets the quick retry ([retried]).
    final pages = before == null
        ? 1
        : (before.items.length / before.meta.pageLimit.clamp(1, 1000))
            .ceil()
            .clamp(1, reloadPages);
    var feed = await retried(ref, () => _load(1, const []));
    var loaded = 1;
    // Stop early once a newer rebuild has superseded this one.
    while (loaded < pages && feed.hasMore && generation == _generation) {
      final (page, rows) = (loaded + 1, feed.items);
      feed = await retried(ref, () => _load(page, rows));
      loaded++;
    }
    if (generation != _generation) return feed;
    // Merged with the feed as it is now, not as it was when the reload
    // left: an edit or delete made meanwhile is applied to it.
    final merged = _withTail(feed, _shown, _placed.values);
    _placed.clear();
    return _show(merged);
  }

  TransactionsFeed _show(TransactionsFeed feed) => _shown = feed;

  /// [head], the freshly reloaded first pages, followed by the rows of
  /// [before] (the feed on screen until now) that come after the last row
  /// of [head] — so a refresh never cuts a long scroll short.
  ///
  /// The seam is found by identity, so rows the server added or removed
  /// above it shift nothing: each row shows once, the fresh copy winning.
  /// The kept rows are as they were last loaded (an in-app edit or delete of
  /// one is applied to them directly: [replaceLocally], [removeLocally]);
  /// infinite scroll pages in what comes after them. Without a seam — the
  /// last fresh row is not among the old ones — only [head] is kept, and
  /// infinite scroll pages the rest back in.
  ///
  /// [placed] are rows the app saved since the last refetch, as the server
  /// answered. One that [head] lists is fresh there. Any other belongs among
  /// the kept rows — an edit that moved a recent row to an older day, or a
  /// back-dated new one, which [head] no longer reaches — and is kept where
  /// its date sorts, as [replaceLocally] put it, even when it sorts right at
  /// the seam (where a day's rows may be ordered otherwise than by id). One
  /// that sorts past the kept rows is left to infinite scroll.
  TransactionsFeed _withTail(
    TransactionsFeed head,
    TransactionsFeed? before,
    Iterable<Transaction> placed,
  ) {
    if (before == null || !head.hasMore || head.items.isEmpty) return head;
    if (before.items.length <= head.items.length) return head;
    final seam = before.items.indexWhere((t) => t.id == head.items.last.id);
    if (seam < 0) return head;
    final merged = _dedupe([...head.items, ...before.items.skip(seam + 1)]);
    final fresh = {for (final t in head.items) t.id};
    final last = head.items.last;
    for (final tx in placed) {
      if (fresh.contains(tx.id) || !_matches(tx)) continue;
      // Among the kept rows already, where [replaceLocally] put it.
      final kept = merged.indexWhere((t) => t.id == tx.id);
      if (kept >= 0) {
        merged[kept] = tx;
        continue;
      }
      // Newer than the reloaded pages reach, yet not in them: the server no
      // longer lists it here (deleted, or moved on the web meanwhile).
      if (tx.date.isAfter(last.date)) continue;
      final at = _sortedIndex(merged, tx, from: head.items.length);
      if (at == merged.length && before.hasMore) continue;
      merged.insert(at, tx);
    }
    if (merged.length == head.items.length) return head;
    return TransactionsFeed(
      items: merged,
      meta: head.meta,
      hasMore: before.hasMore,
      at: head.at,
    );
  }

  /// Where [tx] goes in [items], which are in the server's order — newest
  /// day first, and within a day the latest created first (taken here as
  /// the higher id) — searching from [from] on.
  static int _sortedIndex(
    List<Transaction> items,
    Transaction tx, {
    int from = 0,
  }) {
    for (var i = from; i < items.length; i++) {
      final other = items[i];
      if (other.date.isBefore(tx.date) ||
          (other.date == tx.date && other.id < tx.id)) {
        return i;
      }
    }
    return items.length;
  }

  /// The page [loadMore] asks for next. Counted from the rows on screen
  /// rather than from the pages fetched: after rows were added or removed
  /// above, the next page then overlaps the end of the list a little (the
  /// duplicates are dropped) instead of skipping rows.
  int _nextPage(TransactionsFeed feed) =>
      feed.items.length ~/ feed.meta.pageLimit.clamp(1, 1000) + 1;

  Future<TransactionsFeed> _load(int page, List<Transaction> existing) async {
    final res = await _repo.fetchTransactions(
      kind: _filters.kind,
      accountId: _filters.accountId,
      categoryId: _filters.categoryId,
      uncategorized: _filters.uncategorized,
      includeIncomingTransfers: _filters.includeIncomingTransfers,
      from: _filters.from,
      to: _filters.to,
      page: page,
    );
    final merged = _dedupe([...existing, ...res.items]);
    // Guard against an infinite paginate loop: stop when the server returns a
    // short (final) page, and require the dedupe to have actually appended new
    // rows — a full page of pure duplicates must not keep requesting forever.
    final addedNew = merged.length > existing.length;
    final fullPage = res.items.length >= res.meta.pageLimit;
    return TransactionsFeed(
      items: merged,
      meta: res.meta,
      hasMore: fullPage && addedNew,
      at: DateTime.now(),
    );
  }

  /// Pull-to-refresh and retry: refetch (the first pages, up to
  /// [reloadPages], with the rows beyond them kept) and wait for it. Never
  /// throws — a failure stays visible through the AsyncValue — and never
  /// waits forever.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await settleRefresh([future]);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        _loadingMore ||
        state.isLoading) {
      return;
    }
    _loadingMore = true;
    final generation = _generation;
    try {
      final next = await _load(_nextPage(current), current.items);
      // A refetch replaced the feed meanwhile; this page belongs to the old one.
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(_show(next));
    } catch (_) {
      // Keep the accumulated list; a page failure shouldn't clear the feed.
    } finally {
      _loadingMore = false;
    }
  }

  /// Drops a transaction from the accumulated list and adjusts the meta, so a
  /// delete shows at once. The delete's own refetch then replaces the feed.
  void removeLocally(int id) {
    _placed.remove(id);
    final current = state.value;
    if (current == null) return;
    final idx = current.items.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final removed = current.items[idx];
    final items = [...current.items]..removeAt(idx);
    final meta = current.meta;
    state = AsyncData(_show(TransactionsFeed(
      items: items,
      meta: TransactionMeta(
        totalCount: meta.totalCount > 0 ? meta.totalCount - 1 : 0,
        page: meta.page,
        pageLimit: meta.pageLimit,
        filteredIncomeCents: removed.kind == 'income'
            ? meta.filteredIncomeCents - removed.amountCents
            : meta.filteredIncomeCents,
        filteredExpenseCents: removed.kind == 'expense'
            ? meta.filteredExpenseCents - removed.amountCents
            : meta.filteredExpenseCents,
      ),
      hasMore: current.hasMore,
      at: current.at,
    )));
  }

  /// Puts [saved] — a transaction just saved in the app, as the server
  /// answered — where the server now lists it, wherever in the list that is
  /// (also among the rows a refetch keeps as they were: see [_withTail]).
  ///
  /// An edit that left its day alone replaces the row in place. One that
  /// moved it to another day moves it to where that day sorts, so an edit
  /// that sends a recent row back a few months shows it there, among rows
  /// already loaded — and the edit's refetch, which reloads only the first
  /// pages, keeps it there. A row not listed yet (just created) goes where
  /// its day sorts too. Either is left to infinite scroll when it sorts past
  /// the rows loaded so far, and a row the edit took out of this feed's
  /// filters is dropped. The write's own refetch then brings everything
  /// else up to date.
  void replaceLocally(Transaction saved) {
    final current = state.value;
    if (current == null) return;
    if (!_matches(saved)) {
      removeLocally(saved.id);
      return;
    }
    _placed[saved.id] = saved;
    final idx = current.items.indexWhere((t) => t.id == saved.id);
    final rest = [...current.items];
    if (idx >= 0) rest.removeAt(idx);
    var at = idx;
    // Same day: the server lists it where it was.
    if (idx < 0 || current.items[idx].date != saved.date) {
      at = _sortedIndex(rest, saved);
      if (at == rest.length && current.hasMore) {
        // Past the rows loaded so far: infinite scroll brings it. Still in
        // the feed, so its totals stay as they are.
        _placed.remove(saved.id);
        if (idx < 0) return;
        at = -1;
      }
    }
    state = AsyncData(_show(TransactionsFeed(
      items: at < 0 ? rest : (rest..insert(at, saved)),
      meta: current.meta,
      hasMore: current.hasMore,
      at: current.at,
    )));
  }

  /// Whether [tx] belongs in this feed, by the server's rules for its
  /// filters (a root category also matches its subcategories; a transfer
  /// into the account counts when the feed asks for incoming transfers).
  bool _matches(Transaction tx) {
    final f = _filters;
    if (f.kind != null && tx.kind != f.kind) return false;
    if (f.accountId != null &&
        tx.account.id != f.accountId &&
        !(f.includeIncomingTransfers &&
            tx.kind == 'transfer' &&
            tx.relatedAccount?.id == f.accountId)) {
      return false;
    }
    if (f.uncategorized) {
      if (tx.category != null) return false;
    } else if (f.categoryId != null &&
        tx.category?.id != f.categoryId &&
        tx.category?.parentId != f.categoryId) {
      return false;
    }
    final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
    final from = f.from;
    if (from != null && day.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    final to = f.to;
    if (to != null && day.isAfter(DateTime(to.year, to.month, to.day))) {
      return false;
    }
    return true;
  }

  static List<Transaction> _dedupe(List<Transaction> list) {
    final seen = <int>{};
    final out = <Transaction>[];
    for (final t in list) {
      if (seen.add(t.id)) out.add(t);
    }
    return out;
  }
}

final transactionsProvider = AsyncNotifierProvider.autoDispose
    .family<TransactionsNotifier, TransactionsFeed, TxFilters>(
  TransactionsNotifier.new,
  retry: _retriedInFetch,
);

/// Drops transaction [id], which the server has just deleted, from every
/// feed that is open — each set of filters, each account's history — as
/// [TransactionsNotifier.removeLocally] does for one. Infinite scroll then
/// pages on from the rows that are really left (none is skipped), and the
/// refetch the delete triggers keeps no stale copy of it among the rows it
/// does not reload.
void forgetDeletedTransaction(ProviderContainer container, int id) {
  for (final instance in container.allProviders(family: transactionsProvider)) {
    final filters = instance.provider.argument;
    if (filters is! TxFilters) continue;
    container.read(transactionsProvider(filters).notifier).removeLocally(id);
  }
}
