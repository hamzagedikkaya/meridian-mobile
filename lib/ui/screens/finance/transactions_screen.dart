import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/search.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/date_utils.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/day_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/row_motion.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'category_picker.dart';
import 'filter_chip_bar.dart';
import 'finance_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

/// İşlemler (design-analysis §7.7): every transaction, newest first, under
/// day headings that carry the day's spending, with filters and a search.
///
/// * **App bar**: "İşlemler" and a search button. The search opens a field
///   under the app bar — focused, sent 300 ms after the last keystroke, from
///   two characters on (`TxFilters.q`; contract 13.2). The route's
///   `?search=1` opens it focused; `?q=` opens it with that text.
/// * **Filters**: [Tür ▾] [Hesap ▾] [Kategori ▾] [Tarih ▾] and the clear ×
///   ([FilterChipBar]); the income · expense line under them.
/// * **Days**: `DayHeader` with the day's expenses (transfers left out),
///   "−₺1.240"; the rows are `TxRow`s, without the account's name while the
///   list is filtered to it.
/// * **Rows**: a tap opens the detail sheet, a long press its actions
///   (Düzenle · Bugüne kopyala · Sil), a swipe to the left deletes with
///   "Geri al".
/// * **New filters**: the list on screen stays; after 150 ms of waiting it
///   dims to half and stops taking taps; the results cross-fade in (200 ms)
///   at the top (§5.4).
/// * **Empty**: no transaction at all ("İşlem ekle"; the FAB steps aside),
///   none for the filters ("Filtreleri temizle"), none for the search
///   ("Aramayı temizle", and "Her yerde ara" once global search is there).
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
  late String? _kind = widget.initial.kind;
  late int? _accountId = widget.initial.accountId;
  late int? _categoryId = widget.initial.categoryId;
  late bool _uncategorized = widget.initial.uncategorized;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  // --- search ------------------------------------------------------------------

  /// The search field is open under the app bar.
  late bool _searchOpen = widget.initial.q != null;

  /// The text searched for (`q`): trimmed, two characters or more.
  late String? _query = widget.initial.q;
  late final _searchCtrl = TextEditingController(text: widget.initial.q);
  final _searchFocus = FocusNode();
  Timer? _debounce;
  bool _routeRead = false;

  // --- what is on screen ---------------------------------------------------------

  /// The last feed on screen and the filters it was for. While a newly
  /// picked filter loads, it stays up instead of a skeleton.
  TransactionsFeed? _lastFeed;
  TxFilters? _lastFeedFilters;

  /// The list waited for new results long enough to be dimmed (§5.4).
  bool _dim = false;
  Timer? _dimTimer;

  /// Each shown result set scrolls on its own controller, so a new one
  /// starts at its top while the old one fades out where it was.
  ScrollController _scroll = ScrollController();
  TxFilters? _scrollFor;
  final _retired = <ScrollController>[];
  Timer? _retireTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeRead) return;
    _routeRead = true;
    // go_router hands a page its query as the route's arguments:
    // `/finance/transactions?search=1` opens the search, `&q=` fills it.
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;
    final q = args['q'];
    if (q is String && q.trim().isNotEmpty) {
      _searchCtrl.text = q.trim();
      _query = TxFilters.queryOf(q);
      _searchOpen = true;
    }
    if (args['search'] == '1') _searchOpen = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dimTimer?.cancel();
    _retireTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    for (final controller in _retired) {
      controller.dispose();
    }
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
        q: _query,
      );

  void _onScroll() {
    if (!_scroll.hasClients || _scroll.positions.length != 1) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(transactionsProvider(_filters).notifier).loadMore();
    }
  }

  /// A new result set is on screen: it scrolls on a fresh controller (at
  /// its top), and the old one is let go once its list has faded out.
  void _scrollTo(TxFilters shown) {
    if (_scrollFor == shown) return;
    final first = _scrollFor == null;
    _scrollFor = shown;
    if (first) return;
    final old = _scroll..removeListener(_onScroll);
    _retired.add(old);
    _scroll = ScrollController()..addListener(_onScroll);
    _retireTimer?.cancel();
    _retireTimer = Timer(const Duration(seconds: 1), () {
      for (final controller in _retired) {
        controller.dispose();
      }
      _retired.clear();
    });
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

  // --- search ------------------------------------------------------------------

  void _openSearch() {
    setState(() => _searchOpen = true);
    // The field is built focused; a reopened one asks again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _query = null;
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = null);
    _searchFocus.requestFocus();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(TxFilters.searchDebounce, () => _search(text));
  }

  void _search(String text) {
    _debounce?.cancel();
    if (!mounted) return;
    final query = TxFilters.queryOf(text);
    if (query == _query) return;
    setState(() => _query = query);
  }

  /// "Her yerde ara": the same words over every kind of record (§6.8).
  void _searchEverywhere() {
    final q = _query ?? _searchCtrl.text.trim();
    context.push(Uri(path: '/search', queryParameters: {'q': q}).toString());
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
        PickerOption(
            value: 'all', label: l.labelAll, icon: Icons.all_inclusive_rounded),
        PickerOption(
            value: 'month',
            label: l.txFilterThisMonth,
            icon: Icons.calendar_today_rounded),
        PickerOption(
            value: '30d',
            label: l.txFilterLast30Days,
            icon: Icons.history_rounded),
        PickerOption(
            value: 'year',
            label: l.txFilterThisYear,
            icon: Icons.calendar_month_rounded),
        PickerOption(
            value: 'custom',
            label: l.txFilterCustomRange,
            icon: Icons.date_range_rounded),
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
    _placeSaved(saved);
    showAppSnack(context, l.txSaved);
  }

  /// [saved] in place at once — also deep in a long list, past what the
  /// write's refetch reloads.
  void _placeSaved(Transaction saved) {
    if (!mounted) return;
    ref.read(transactionsProvider(_filters).notifier).replaceLocally(saved);
  }

  Future<void> _refresh() =>
      ref.read(transactionsProvider(_filters).notifier).refresh();

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
    final feedAsync = ref.watch(transactionsProvider(filters));
    final current = feedAsync.value;
    if (current != null) {
      _lastFeed = current;
      _lastFeedFilters = filters;
    }
    // New filters loading: what was on screen stays there meanwhile.
    final waiting =
        current == null && feedAsync.isFirstLoad && _lastFeed != null;
    final feed = current ?? (waiting ? _lastFeed : null);
    final shown = waiting ? _lastFeedFilters! : filters;
    _scrollTo(shown);
    _trackWaiting(waiting);
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

    final items = feed == null
        ? const <Transaction>[]
        : withoutDeleted(
            feed.items, hidden, DataScope.transactions, (tx) => tx.id);
    // Nothing recorded at all: the empty state's "İşlem ekle" is the one
    // way to add (§6.5).
    final noneAtAll = feed != null &&
        !waiting &&
        items.isEmpty &&
        !_hasFilters &&
        _query == null;
    final duration = Motion.orInstant(context, Motion.quick);

    return CollapsingFabScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.titleTransactions),
          actions: [
            if (_searchOpen)
              IconButton(
                onPressed: _closeSearch,
                tooltip: l.txSearchClose,
                icon: const Icon(Icons.close_rounded),
              )
            else
              IconButton(
                onPressed: _openSearch,
                tooltip: l.actionSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            const SizedBox(width: Gap.xs),
          ],
        ),
        floatingActionButton: CollapsingFab(
          icon: Icons.add_rounded,
          label: l.financeAddTransactionFab,
          onPressed: _add,
          hidden: noneAtAll,
        ),
        body: Column(
          children: [
            if (offline)
              OfflineBanner(
                // A failed refresh implies a feed on screen.
                lastUpdated: current!.at,
                onRetry: _refresh,
              ),
            if (_searchOpen) _searchField(context),
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
            Expanded(
              child: SyncHint.over(
                active: feedAsync.isRefetching || waiting,
                child: IgnorePointer(
                  ignoring: waiting && _dim,
                  child: AnimatedOpacity(
                    opacity: waiting && _dim ? 0.5 : 1,
                    duration: Motion.orInstant(context, Motion.pressOut),
                    // Each result set fades out as the next fades in
                    // (§5.4): the old one in its first 100 ms, the new
                    // one from 60 ms on.
                    child: AnimatedSwitcher(
                      duration: duration,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: _crossFade,
                      child: KeyedSubtree(
                        key: ValueKey(shown),
                        child: Column(
                          children: [
                            if (feed != null)
                              _summary(context, feed, hidden, account),
                            Expanded(
                              child: _list(context, feedAsync, feed, items),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A result set's fade (§5.4): in over the last 70% of the switch, out
  /// over its first half. One builder for the screen's life, so a rebuild
  /// does not make the switcher build its transitions again.
  static Widget _crossFade(Widget child, Animation<double> animation) =>
      FadeTransition(opacity: _CrossFadeOpacity(animation), child: child);

  /// Dims the list once new results have been waited for 150 ms (§5.4);
  /// undimmed the moment they land.
  void _trackWaiting(bool waiting) {
    if (!waiting) {
      _dimTimer?.cancel();
      _dimTimer = null;
      _dim = false;
      return;
    }
    if (_dim || _dimTimer != null) return;
    _dimTimer = Timer(Motion.spinnerDelay, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  /// The search field under the app bar: focused when it opens, a clear ×
  /// while it has text.
  Widget _searchField(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    return ColoredBox(
      color: c.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.xs,
          Insets.gutter,
          Gap.xs,
        ),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: l.txSearchHint,
            prefixIcon: const Icon(Icons.search_rounded),
            // The clear × comes and goes with the text — only it rebuilds
            // on a keystroke, not the list.
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchCtrl,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      onPressed: _clearSearch,
                      tooltip: l.txSearchClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The filtered income and expense, in the currency the amounts are in:
  /// the filtered account's, else the user's (the server adds the stored
  /// minor units of every account as they are). Rows deleted a moment ago
  /// are taken out at once, before the refetch says so. Two zeros are not
  /// shown.
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
    // Nothing in or out: no "₺0 gelir · ₺0 gider" over an empty list
    // (§7.15) — the empty state says it in words.
    if (income == 0 && expense == 0) return const SizedBox(height: Gap.sm);
    String money(int cents) => formatMoney(cents, currency, subunit,
        decimals: MoneyDecimals.auto);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.xxs,
        Insets.gutter,
        Gap.sm,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          l.txSummary(money(income), money(expense)),
          style: text.bodySmall!.copyWith(
            color: c.inkMid,
            fontFeatures: tabularFigures,
          ),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AsyncValue<TransactionsFeed> feedAsync,
    TransactionsFeed? feed,
    List<Transaction> items,
  ) {
    final c = context.nok;
    final l = context.l10n;
    if (feed == null) {
      if (feedAsync.isFirstLoad) return const _TxSkeleton();
      return _scrollableEmpty(EmptyState.error(onRetry: _refresh));
    }

    if (items.isEmpty) {
      final query = _query;
      if (query != null) {
        return _scrollableEmpty(EmptyState(
          icon: Icons.search_off_rounded,
          title: l.txSearchEmpty(query),
          secondaryLabel: l.txSearchClear,
          onSecondary: _clearSearch,
          chips: ref.watch(searchOfferedProvider)
              ? [
                  NokChip(
                    label: l.txSearchEverywhere,
                    icon: Icons.travel_explore_rounded,
                    onTap: _searchEverywhere,
                  ),
                ]
              : null,
        ));
      }
      if (_hasFilters) {
        return _scrollableEmpty(EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: l.txNoneForFilter,
          secondaryLabel: l.txFilterClear,
          onSecondary: _clearFilters,
        ));
      }
      return _scrollableEmpty(EmptyState(
        icon: Icons.receipt_long_outlined,
        title: l.financeNoTransactionsYet,
        actionLabel: l.financeFirstTxAction,
        onAction: _add,
      ));
    }

    final perspective = _accountId;
    final slivers = <Widget>[
      // One group per day: its header pins while the day is on screen and
      // is pushed away by the next day's, instead of piling up under the
      // filters.
      for (final g in _groupByDay(items))
        SliverMainAxisGroup(
          key: ValueKey('day-${g.day.toIso8601String()}'),
          slivers: [
            PinnedHeaderSliver(child: _dayHeader(context, g)),
            SliverList.builder(
              itemCount: g.items.length,
              itemBuilder: (context, i) =>
                  _row(context, g.items[i], perspective),
            ),
          ],
        ),
      SliverToBoxAdapter(
        child: SizedBox(
          // Room for the FAB under the last row's amount.
          height: CollapsingFab.clearance(context),
          child: Align(
            alignment: const Alignment(0, -0.5),
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
      // Armed (§5.8): the pull let go past its threshold.
      onRefresh: () {
        Haptics.armed();
        return _refresh();
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  /// An empty state that still pulls to refresh.
  Widget _scrollableEmpty(Widget empty) => RefreshIndicator.adaptive(
        color: context.nok.gold,
        // Armed (§5.8): the pull let go past its threshold.
        onRefresh: () {
          Haptics.armed();
          return _refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(hasScrollBody: false, child: empty),
          ],
        ),
      );

  Widget _row(BuildContext context, Transaction tx, int? perspective) {
    return RowMotion(
      key: ValueKey('tx-${tx.id}'),
      record: (scope: DataScope.transactions, id: tx.id),
      child: TxSwipeToDelete(
        key: ValueKey(tx.id),
        tx: tx,
        child: TxRow(
          tx: tx,
          perspectiveAccountId: perspective,
          // Filtered to one account: its name would be on every row.
          hideAccount: perspective != null,
          onTap: () => showTransactionSheet(
            context,
            ref,
            tx,
            perspectiveAccountId: perspective,
            onSaved: _placeSaved,
          ),
          onLongPress: () =>
              showTransactionActions(context, ref, tx, onSaved: _placeSaved),
          semanticActions:
              txRowSemanticActions(context, ref, tx, onSaved: _placeSaved),
        ),
      ),
    );
  }

  /// The day's heading with what was spent that day — expenses only, a
  /// transfer is no spending — per currency: "−₺1.240".
  Widget _dayHeader(BuildContext context, _DayGroup g) {
    final l = context.l10n;
    final today = ref.read(currentDayProvider);
    final spent = <String, ({int cents, int subunit})>{};
    for (final tx in g.items) {
      if (tx.kind != 'expense') continue;
      final currency = tx.account.currency;
      final sum = spent[currency];
      spent[currency] = (
        cents: (sum?.cents ?? 0) + tx.amountCents,
        subunit: tx.account.subunitToUnit,
      );
    }
    final total = spent.isEmpty
        ? null
        : [
            for (final MapEntry(key: currency, value: sum) in spent.entries)
              formatMoney(
                sum.cents,
                currency,
                sum.subunit,
                sign: MoneySign.negative,
                decimals: MoneyDecimals.auto,
              ),
          ].join(' · ');
    var header =
        DayHeader.forDay(context, g.day, today: today, trailing: total);
    if (g.day.year != today.year) {
      // İşlemler pages back through years: a day of another year says
      // which ("Pazartesi · 29 Eylül 2025").
      final name = switch (dayDelta(g.day, now: today)) {
        -1 => l.dayYesterday,
        1 => l.dayTomorrow,
        _ => formatWeekday(g.day),
      };
      header = DayHeader(
        label: '$name · ${formatDate(g.day, withYear: true)}',
        trailing: total,
      );
    }
    if (total == null) return header;
    // One heading for a screen reader: "Bugün · 4 Ekim, Gider −₺1.240".
    return Semantics(
      header: true,
      label: '${header.label}, ${l.txDaySpent(total)}',
      excludeSemantics: true,
      child: header,
    );
  }

  List<_DayGroup> _groupByDay(List<Transaction> items) {
    final groups = <_DayGroup>[];
    for (final tx in items) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (groups.isNotEmpty && groups.last.day == day) {
        groups.last.items.add(tx);
      } else {
        groups.add(_DayGroup(day, [tx]));
      }
    }
    return groups;
  }
}

/// [parent]'s value as the result sets' cross-fade wants it: eased in over
/// its last 70% while it runs forward (the set coming in), gone in its first
/// half while it runs back (the set going out). It listens to nothing of its
/// own — [parent] carries the listeners — so it needs no disposing.
class _CrossFadeOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  _CrossFadeOpacity(this.parent);

  @override
  final Animation<double> parent;

  static const _incoming = Interval(0.3, 1, curve: Motion.fadeIn);
  static const _outgoing = Interval(0.5, 1, curve: Motion.fadeOut);

  @override
  double get value {
    final t = parent.value;
    final out = parent.status == AnimationStatus.reverse ||
        parent.status == AnimationStatus.dismissed;
    return (out ? _outgoing : _incoming).transform(t);
  }
}

class _DayGroup {
  final DateTime day;
  final List<Transaction> items;
  _DayGroup(this.day, this.items);
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
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        children: [
          for (var i = 0; i < 10; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.gutter,
                vertical: Gap.sm,
              ),
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
                  const SizedBox(width: Gap.md),
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
