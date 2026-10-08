import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/date_utils.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'category_picker.dart';
import 'filter_chip_bar.dart';
import 'finance_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

/// Every transaction, newest first, grouped by day, with filters.
///
/// [initial] are the filters it opens with: Finance drills into it — a
/// category this month, the month's uncategorized spending.
class TransactionsScreen extends ConsumerStatefulWidget {
  final TxFilters initial;

  const TransactionsScreen({super.key, this.initial = const TxFilters()});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scroll = ScrollController();
  late String? _kind = widget.initial.kind;
  late int? _accountId = widget.initial.accountId;
  late int? _categoryId = widget.initial.categoryId;
  late bool _uncategorized = widget.initial.uncategorized;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  /// The last feed on screen and the filters it was for. While a newly
  /// picked filter loads, the previous results stay up, dimmed, instead of a
  /// skeleton.
  TransactionsFeed? _lastFeed;
  TxFilters? _shownFilters;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// The feed key derived from the current filter state. setState rebuilds the
  /// screen, which re-watches the provider with a fresh key — no racy setFilters.
  /// An account filter lists the transfers into the account too, as its own
  /// screen does, so its history adds up.
  TxFilters get _filters => TxFilters(
        kind: _kind,
        accountId: _accountId,
        categoryId: _uncategorized ? null : _categoryId,
        uncategorized: _uncategorized,
        includeIncomingTransfers: _accountId != null,
        from: _from,
        to: _to,
      );

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      ref.read(transactionsProvider(_filters).notifier).loadMore();
    }
  }

  bool get _hasFilters =>
      _kind != null ||
      _accountId != null ||
      _categoryId != null ||
      _uncategorized ||
      _from != null;

  void _clearFilters() {
    setState(() {
      _kind = null;
      _accountId = null;
      _categoryId = null;
      _uncategorized = false;
      _from = null;
      _to = null;
    });
  }

  // --- filter pickers --------------------------------------------------------

  Future<void> _pickAccount(List<Account> accounts) async {
    final l = context.l10n;
    final id = await showPickerSheet<int>(
      context,
      title: l.txFilterAccount,
      selected: _accountId ?? -1,
      options: [
        PickerOption<int>(value: -1, label: l.txFilterAllAccounts),
        for (final a in accounts)
          PickerOption<int>(
            value: a.id,
            label: a.name,
            color: hexColor(a.color),
            subtitle: a.archived ? l.accountArchivedBadge : null,
          ),
      ],
    );
    if (id == null) return;
    setState(() => _accountId = id == -1 ? null : id);
  }

  Future<void> _pickCategory() async {
    final l = context.l10n;
    final choice = await showCategoryPicker(
      context,
      title: l.txFilterCategory,
      selected: _uncategorized
          ? const NoCategory()
          : (_categoryId == null
              ? const AnyCategory()
              : OneCategory(_categoryById(_categoryId!) ??
                  TxCategory(
                    id: _categoryId!,
                    name: '',
                    kind: 'expense',
                    color: '',
                    position: 0,
                  ))),
      allowAny: true,
      allowCreate: false,
    );
    if (choice == null) return;
    setState(() {
      switch (choice) {
        case AnyCategory():
          _categoryId = null;
          _uncategorized = false;
        case NoCategory():
          _categoryId = null;
          _uncategorized = true;
        case OneCategory(:final category):
          _categoryId = category.id;
          _uncategorized = false;
      }
    });
  }

  TxCategory? _categoryById(int id) {
    for (final category
        in ref.read(categoriesProvider).value?.data ?? const <TxCategory>[]) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// The date presets, by key: this month, the last 30 days, this year.
  ({DateTime from, DateTime to})? _preset(String key, DateTime today) =>
      switch (key) {
        'month' => (
            from: DateTime(today.year, today.month, 1),
            to: DateTime(today.year, today.month + 1, 0),
          ),
        '30d' => (from: today.subtract(const Duration(days: 30)), to: today),
        'year' => (
            from: DateTime(today.year, 1, 1),
            to: DateTime(today.year, 12, 31),
          ),
        _ => null,
      };

  /// Which preset the current range is, if any.
  String? _presetKey(DateTime today) {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return null;
    for (final key in const ['month', '30d', 'year']) {
      final range = _preset(key, today)!;
      if (dateOnly(range.from) == dateOnly(from) &&
          dateOnly(range.to) == dateOnly(to)) {
        return key;
      }
    }
    return 'custom';
  }

  String? _dateLabel(AppL10n l, DateTime today) => switch (_presetKey(today)) {
        null => null,
        'month' => l.txFilterThisMonth,
        '30d' => l.txFilterLast30Days,
        'year' => l.txFilterThisYear,
        _ => '${formatDate(_from!)} – ${formatDate(_to!)}',
      };

  Future<void> _pickDate() async {
    final l = context.l10n;
    // The account's today, as the server counts months (see
    // data/current_day.dart).
    final today = ref.read(currentDayProvider);
    final key = await showPickerSheet<String>(
      context,
      title: l.txFilterDateRange,
      selected: _presetKey(today) ?? 'all',
      options: [
        PickerOption(value: 'all', label: l.labelAll, icon: Icons.all_inclusive),
        PickerOption(
            value: 'month',
            label: l.txFilterThisMonth,
            icon: Icons.calendar_today),
        PickerOption(
            value: '30d', label: l.txFilterLast30Days, icon: Icons.history),
        PickerOption(
            value: 'year',
            label: l.txFilterThisYear,
            icon: Icons.calendar_month),
        PickerOption(
            value: 'custom',
            label: l.txFilterCustomRange,
            icon: Icons.date_range),
      ],
    );
    if (key == null || !mounted) return;
    if (key == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100),
        initialDateRange: _from != null && _to != null
            ? DateTimeRange(start: _from!, end: _to!)
            : null,
      );
      if (range == null) return;
      setState(() {
        _from = dateOnly(range.start);
        _to = dateOnly(range.end);
      });
      return;
    }
    final range = _preset(key, today);
    setState(() {
      _from = range?.from;
      _to = range?.to;
    });
  }

  Future<void> _add() async {
    final l = context.l10n;
    final saved =
        await openTransactionForm(context, initialAccountId: _accountId);
    if (saved == null || !mounted) return;
    // In place at once; the write's refetch brings the rest.
    ref.read(transactionsProvider(_filters).notifier).replaceLocally(saved);
    showAppSnack(context, l.txSaved);
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // The day headers ("Bugün", "Dün") are relative to today.
    final today = ref.watch(currentDayProvider);
    // Loaded (and kept current) for the account and category filters.
    final hidden = ref.watch(deferredDeletesProvider);
    final accounts = withoutDeleted(
      ref.watch(accountsProvider).value?.data ?? const <Account>[],
      hidden,
      DataScope.accounts,
      (a) => a.id,
    );
    final categories = ref.watch(categoriesProvider).value?.data ?? const [];
    final filters = _filters;
    if (_shownFilters != null && filters != _shownFilters) {
      // A new filter starts at the top of its results.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _shownFilters = filters;
    final feedAsync = ref.watch(transactionsProvider(filters));
    final current = feedAsync.value;
    if (current != null) _lastFeed = current;
    final previous = feedAsync.isFirstLoad ? _lastFeed : null;
    final feed = current ?? previous;
    final offline = feedAsync.refreshFailed;

    Account? account;
    for (final a in accounts) {
      if (a.id == _accountId) account = a;
    }
    String? categoryLabel;
    if (_uncategorized) {
      categoryLabel = l.financeUncategorized;
    } else if (_categoryId != null) {
      categoryLabel = l.txFilterCategory;
      for (final category in categories) {
        if (category.id == _categoryId) categoryLabel = category.name;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.titleTransactions)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l.financeAddTransactionFab),
      ),
      body: Column(
        children: [
          if (offline)
            OfflineBanner(
              // A failed refresh implies a feed on screen.
              lastUpdated: current!.at,
              onRetry: () =>
                  ref.read(transactionsProvider(_filters).notifier).refresh(),
            ),
          FilterChipBar(
            kind: _kind,
            onKind: (k) => setState(() => _kind = k),
            accountLabel: _accountId == null
                ? null
                : (account?.name ?? l.txFilterAccount),
            categoryLabel: categoryLabel,
            dateLabel: _dateLabel(l, today),
            onAccountTap: () => _pickAccount(accounts),
            onCategoryTap: _pickCategory,
            onDateTap: _pickDate,
            onClear: _hasFilters ? _clearFilters : null,
          ),
          if (feed != null)
            Opacity(
              opacity: previous == null ? 1 : 0.5,
              child: _summary(context, feed, hidden, account),
            ),
          Expanded(
            child: SyncHint.over(
              active: feedAsync.isRefetching || previous != null,
              // Same wrappers either way, so the list is not remounted when
              // the new results land.
              child: IgnorePointer(
                ignoring: previous != null,
                child: Opacity(
                  opacity: previous == null ? 1 : 0.5,
                  child: _list(context, feedAsync, feed, hidden),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The filtered income and expense, in the currency the amounts are in:
  /// the filtered account's, else the user's (the server adds the stored
  /// minor units of every account as they are). Rows deleted a moment ago
  /// are taken out at once, before the refetch says so.
  Widget _summary(
    BuildContext context,
    TransactionsFeed feed,
    Set<DeletedRecord> hidden,
    Account? account,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final user = ref.watch(currentUserProvider);
    final currency = account?.currency ?? user?.currency ?? 'TRY';
    final subunit = account?.subunitToUnit ?? user?.subunitToUnit ?? 100;
    var income = feed.meta.filteredIncomeCents;
    var expense = feed.meta.filteredExpenseCents;
    for (final tx in feed.items) {
      if (!hidden.contains((scope: DataScope.transactions, id: tx.id))) {
        continue;
      }
      if (tx.kind == 'income') income -= tx.amountCents;
      if (tx.kind == 'expense') expense -= tx.amountCents;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              l.txSummary(
                formatMoney(income, currency, subunit),
                formatMoney(expense, currency, subunit),
              ),
              style: text.bodySmall!.copyWith(color: c.inkMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() =>
      ref.read(transactionsProvider(_filters).notifier).refresh();

  Widget _list(
    BuildContext context,
    AsyncValue<TransactionsFeed> feedAsync,
    TransactionsFeed? feed,
    Set<DeletedRecord> hidden,
  ) {
    final c = context.nok;
    final l = context.l10n;
    if (feed == null) {
      if (feedAsync.isFirstLoad) return const _TxSkeleton();
      return RefreshIndicator.adaptive(
        color: c.gold,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.cloud_off,
              title: l.errServerUnreachable,
              subtitle: l.errCheckWifi,
              actionLabel: l.actionRetry,
              onAction: _refresh,
            ),
          ],
        ),
      );
    }

    final items = withoutDeleted(
      feed.items,
      hidden,
      DataScope.transactions,
      (tx) => tx.id,
    );
    if (items.isEmpty) {
      return RefreshIndicator.adaptive(
        color: c.gold,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: _hasFilters
                  ? l.txNoneForFilter
                  : l.financeNoTransactionsYet,
              actionLabel: _hasFilters ? null : l.financeFirstTxAction,
              onAction: _hasFilters ? null : _add,
              secondaryLabel: _hasFilters ? l.txFilterClear : null,
              onSecondary: _hasFilters ? _clearFilters : null,
            ),
          ],
        ),
      );
    }

    final groups = _groupByDay(items);
    final perspective = _accountId;
    final slivers = <Widget>[
      // One group per day: its header pins while the day is on screen and
      // is pushed away by the next day's, instead of piling up under the
      // filters.
      for (final g in groups)
        SliverMainAxisGroup(
          key: ValueKey('day-${g.key.toIso8601String()}'),
          slivers: [
            PinnedHeaderSliver(child: _DayHeader(g.label)),
            SliverList.builder(
              itemCount: g.items.length,
              itemBuilder: (context, i) {
                final tx = g.items[i];
                return TxSwipeToDelete(
                  key: ValueKey('tx-${tx.id}'),
                  tx: tx,
                  child: TxRow(
                    tx: tx,
                    perspectiveAccountId: perspective,
                    onTap: () => showTransactionSheet(
                      context,
                      ref,
                      tx,
                      perspectiveAccountId: perspective,
                      // In place at once — also deep in a long list, past
                      // what the edit's refetch reloads.
                      onSaved: (saved) => ref
                          .read(transactionsProvider(_filters).notifier)
                          .replaceLocally(saved),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 96,
          child: Center(
            child: feed.hasMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.txAllLoaded,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall!
                        .copyWith(color: c.inkLow)),
          ),
        ),
      ),
    ];

    return RefreshIndicator.adaptive(
      color: c.gold,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  List<_DayGroup> _groupByDay(List<Transaction> items) {
    final l = context.l10n;
    final groups = <_DayGroup>[];
    for (final tx in items) {
      final key = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (groups.isNotEmpty && groups.last.key == key) {
        groups.last.items.add(tx);
      } else {
        groups.add(_DayGroup(key, l.relativeDay(tx.date), [tx]));
      }
    }
    return groups;
  }
}

class _DayGroup {
  final DateTime key;
  final String label;
  final List<Transaction> items;
  _DayGroup(this.key, this.label, this.items);
}

/// A day's heading; at least 36 dp, taller with large text.
class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        color: c.bg,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          label,
          style: text.labelMedium!.copyWith(color: c.inkMid),
        ),
      ),
    );
  }
}

class _TxSkeleton extends StatelessWidget {
  const _TxSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return NokSkeleton(
      enabled: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (var i = 0; i < 10; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.skeletonBone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
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
