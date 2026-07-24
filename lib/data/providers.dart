/// Data-layer providers (Riverpod 3, no codegen).
///
/// Read pattern for screens: `ref.watch(x)` yields an `AsyncValue<Fetched<T>>`.
/// Render `.value` (nullable) so the last-good value persists across a failed
/// refresh — Riverpod 3 auto-imports the previous value on error/loading, so
/// `hasValue` stays true. Show the `OfflineBanner` (with `Fetched.at`) when
/// `hasValue && hasError`; show a full `EmptyState` only when
/// `!hasValue && hasError`. `Fetched.at` is stamped at fetch time so the banner
/// can render "son güncelleme HH:mm".
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../models/account.dart';
import '../models/event.dart';
import '../models/finance_dashboard.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/home.dart';
import '../models/journal.dart';
import '../models/todo.dart';
import '../models/transaction.dart';
import 'repository.dart';

/// Wraps fetched data with the moment it was retrieved (for the offline banner).
class Fetched<T> {
  final T data;
  final DateTime at;
  const Fetched(this.data, this.at);
}

final repositoryProvider = Provider<MeridianRepository>((ref) {
  return MeridianRepository(ref.watch(dioProvider));
});

// --- Screen providers: AsyncValue<Fetched<T>> --------------------------------

final homeProvider = FutureProvider.autoDispose<Fetched<HomeSummary>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchHome();
  return Fetched(data, DateTime.now());
});

final accountsProvider =
    FutureProvider.autoDispose<Fetched<List<Account>>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchAccounts();
  return Fetched(data, DateTime.now());
});

final financeDashboardProvider =
    FutureProvider.autoDispose<Fetched<FinanceDashboard>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchFinanceDashboard();
  return Fetched(data, DateTime.now());
});

final habitsProvider =
    FutureProvider.autoDispose<Fetched<HabitsBundle>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchHabits();
  return Fetched(data, DateTime.now());
});

final goalsProvider =
    FutureProvider.autoDispose<Fetched<GoalsBundle>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchGoals();
  return Fetched(data, DateTime.now());
});

final categoriesProvider =
    FutureProvider.autoDispose<Fetched<List<TxCategory>>>((ref) async {
  final data = await ref.watch(repositoryProvider).fetchCategories();
  return Fetched(data, DateTime.now());
});

final eventsTodayProvider =
    FutureProvider.autoDispose<Fetched<List<Event>>>((ref) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final data =
      await ref.watch(repositoryProvider).fetchEvents(from: today, to: today);
  return Fetched(data, DateTime.now());
});

// --- Family screen providers -------------------------------------------------

final journalProvider = FutureProvider.autoDispose
    .family<Fetched<JournalBundle>, String>((ref, range) async {
  final data = await ref.watch(repositoryProvider).fetchJournal(range: range);
  return Fetched(data, DateTime.now());
});

final todosProvider = FutureProvider.autoDispose
    .family<Fetched<TodosBundle>, String>((ref, filter) async {
  final data = await ref.watch(repositoryProvider).fetchTodos(filter: filter);
  return Fetched(data, DateTime.now());
});

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
  final DateTime? from;
  final DateTime? to;

  const TxFilters({
    this.kind,
    this.accountId,
    this.categoryId,
    this.from,
    this.to,
  });

  @override
  bool operator ==(Object other) =>
      other is TxFilters &&
      other.kind == kind &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, accountId, categoryId, from, to);
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

  final TxFilters _filters;
  int _page = 1;
  bool _loadingMore = false;

  MeridianRepository get _repo => ref.read(repositoryProvider);

  @override
  Future<TransactionsFeed> build() async {
    ref.watch(repositoryProvider); // rebuild if the dio/base URL changes
    _page = 1;
    return _load(1, const []);
  }

  Future<TransactionsFeed> _load(int page, List<Transaction> existing) async {
    final res = await _repo.fetchTransactions(
      kind: _filters.kind,
      accountId: _filters.accountId,
      categoryId: _filters.categoryId,
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
    _page = page;
    return TransactionsFeed(
      items: merged,
      meta: res.meta,
      hasMore: fullPage && addedNew,
      at: DateTime.now(),
    );
  }

  Future<void> refresh() async {
    // On error Riverpod 3 auto-retains the previous items (copyWithPrevious),
    // so a failed refresh keeps the last-good feed visible.
    state = await AsyncValue.guard(() => _load(1, const []));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      state = AsyncData(await _load(_page + 1, current.items));
    } catch (_) {
      // Keep the accumulated list; a page failure shouldn't clear the feed.
    } finally {
      _loadingMore = false;
    }
  }

  /// Drops a transaction from the accumulated list and adjusts the meta so a
  /// delete needs no full reset (keeps totals and the running count in sync).
  void removeLocally(int id) {
    final current = state.value;
    if (current == null) return;
    final idx = current.items.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final removed = current.items[idx];
    final items = [...current.items]..removeAt(idx);
    final meta = current.meta;
    state = AsyncData(TransactionsFeed(
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
    ));
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
);
