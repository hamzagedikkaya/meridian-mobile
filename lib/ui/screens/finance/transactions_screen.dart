import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/skeletons.dart';
import 'filter_chip_bar.dart';
import 'finance_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_row.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scroll = ScrollController();
  String? _kind;
  int? _accountId;
  String? _accountLabel;
  int? _categoryId;
  String? _categoryLabel;
  DateTime? _from;
  DateTime? _to;
  String? _dateLabel;

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
  TxFilters get _filters => TxFilters(
        kind: _kind,
        accountId: _accountId,
        categoryId: _categoryId,
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
      _from != null;

  void _clearFilters() {
    setState(() {
      _kind = null;
      _accountId = null;
      _accountLabel = null;
      _categoryId = null;
      _categoryLabel = null;
      _from = null;
      _to = null;
      _dateLabel = null;
    });
  }

  // --- filter pickers --------------------------------------------------------

  Future<void> _pickAccount() async {
    final l = context.l10n;
    final accounts =
        ref.read(accountsProvider).value?.data ?? const [];
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
          ),
      ],
    );
    if (id == null) return;
    setState(() {
      if (id == -1) {
        _accountId = null;
        _accountLabel = null;
      } else {
        _accountId = id;
        _accountLabel = accounts.firstWhere((a) => a.id == id).name;
      }
    });
  }

  Future<void> _pickCategory() async {
    final l = context.l10n;
    final cats = ref.read(categoriesProvider).value?.data ?? const [];
    final id = await showPickerSheet<int>(
      context,
      title: l.txFilterCategory,
      selected: _categoryId ?? -1,
      options: [
        PickerOption<int>(value: -1, label: l.txFilterAllCategories),
        for (final cat in cats)
          PickerOption<int>(
            value: cat.id,
            label: cat.parentId == null ? cat.name : '   ${cat.name}',
            color: hexColor(cat.color),
          ),
      ],
    );
    if (id == null) return;
    setState(() {
      if (id == -1) {
        _categoryId = null;
        _categoryLabel = null;
      } else {
        _categoryId = id;
        _categoryLabel = cats.firstWhere((cat) => cat.id == id).name;
      }
    });
  }

  Future<void> _pickDate() async {
    final l = context.l10n;
    final now = DateTime.now();
    final key = await showPickerSheet<String>(
      context,
      title: l.txFilterDateRange,
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
      ],
    );
    if (key == null) return;
    setState(() {
      switch (key) {
        case 'month':
          _from = DateTime(now.year, now.month, 1);
          _to = DateTime(now.year, now.month + 1, 0);
          _dateLabel = l.txFilterThisMonth;
        case '30d':
          _from = now.subtract(const Duration(days: 30));
          _to = now;
          _dateLabel = l.txFilterLast30Days;
        case 'year':
          _from = DateTime(now.year, 1, 1);
          _to = DateTime(now.year, 12, 31);
          _dateLabel = l.txFilterThisYear;
        default:
          _from = null;
          _to = null;
          _dateLabel = null;
      }
    });
  }

  // --- row actions -----------------------------------------------------------

  Future<bool> _confirmDelete(Transaction tx) async {
    final l = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l.txDeleteTitle,
      message: tx.description ?? tx.category?.name,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok) return false;
    Haptics.danger();
    try {
      await ref.read(repositoryProvider).deleteTransaction(tx.id);
      if (mounted) {
        // Optimistic drop keeps the scroll position (no full feed reload).
        ref.read(transactionsProvider(_filters).notifier).removeLocally(tx.id);
        ref.invalidate(financeDashboardProvider);
        ref.invalidate(accountsProvider);
        showAppSnack(context, l.txDeleted);
      }
    } catch (_) {
      if (mounted) showAppSnack(context, l.txDeleteFailed, isError: true);
    }
    return false; // removeLocally already dropped the row
  }

  void _showDetail(Transaction tx) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    // Build the meta line from present parts only — a null-category non-transfer
    // row must not leave a stray leading " · " separator.
    final metaParts = <String>[
      if (tx.category != null)
        tx.category!.name
      else if (tx.kind == 'transfer')
        l.financeTransfer,
      tx.account.name,
      formatDate(tx.date, withYear: true),
    ];
    showModalBottomSheet<void>(
      context: context,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx.description ?? tx.category?.name ?? l.financeTransaction,
                style: text.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                metaParts.join(' · '),
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
              const SizedBox(height: 16),
              MoneyText(
                tx.amountCents,
                currency: tx.account.currency,
                subunitToUnit: tx.account.subunitToUnit,
                variant: MoneyVariant.title,
                signed: tx.kind == 'income',
                positiveGreen: tx.kind == 'income',
                negative: tx.kind == 'expense',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetCtx).pop();
                        final saved =
                            await openTransactionForm(context, existing: tx);
                        if (saved == true && mounted) {
                          showAppSnack(context, l.txUpdated);
                        }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(l.actionEdit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDelete(tx);
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: c.error),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(l.actionDelete),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(transactionsProvider(_filters));
    final feed = feedAsync.value;
    final offline = feedAsync.hasError && feed != null;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.titleTransactions)),
      body: Column(
        children: [
          if (offline)
            OfflineBanner(
              lastUpdated: feed.at,
              onRetry: () =>
                  ref.read(transactionsProvider(_filters).notifier).refresh(),
            ),
          FilterChipBar(
            kind: _kind,
            onKind: (k) => setState(() => _kind = k),
            accountLabel: _accountLabel,
            categoryLabel: _categoryLabel,
            dateLabel: _dateLabel,
            onAccountTap: _pickAccount,
            onCategoryTap: _pickCategory,
            onDateTap: _pickDate,
          ),
          if (feed != null) _summary(context, feed.meta),
          Expanded(child: _list(context, feedAsync, feed)),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, TransactionMeta meta) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              l.txSummary(
                formatMoney(meta.filteredIncomeCents, 'TRY', 100),
                formatMoney(meta.filteredExpenseCents, 'TRY', 100),
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

  Widget _list(BuildContext context,
      AsyncValue<TransactionsFeed> feedAsync, TransactionsFeed? feed) {
    final c = context.nok;
    final l = context.l10n;
    if (feed == null) {
      if (feedAsync.isLoading) return const _TxSkeleton();
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off,
            title: l.errServerUnreachable,
            subtitle: l.errCheckWifi,
            actionLabel: l.actionRetry,
            onAction: () =>
                ref.read(transactionsProvider(_filters).notifier).refresh(),
          ),
        ],
      );
    }

    if (feed.items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: _hasFilters
                ? l.txNoneForFilter
                : l.financeNoTransactionsYet,
            secondaryLabel: _hasFilters ? l.txFilterClear : null,
            onSecondary: _hasFilters ? _clearFilters : null,
          ),
        ],
      );
    }

    final groups = _groupByDay(feed.items);
    final slivers = <Widget>[];
    for (final g in groups) {
      slivers.add(SliverPersistentHeader(
        pinned: true,
        delegate: _DayHeaderDelegate(g.label, c),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final tx = g.items[i];
            return Dismissible(
              key: ValueKey('tx-${tx.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(tx),
              background: Container(
                color: c.error,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: Icon(Icons.delete_outline, color: c.inkHi),
              ),
              child: TxRow(tx: tx, onTap: () => _showDetail(tx)),
            );
          },
          childCount: g.items.length,
        ),
      ));
    }
    slivers.add(SliverToBoxAdapter(
      child: SizedBox(
        height: 80,
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
    ));

    return RefreshIndicator.adaptive(
      color: c.gold,
      onRefresh: () =>
          ref.read(transactionsProvider(_filters).notifier).refresh(),
      child: CustomScrollView(controller: _scroll, slivers: slivers),
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

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final NokturnColors colors;
  _DayHeaderDelegate(this.label, this.colors);

  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 36,
      color: colors.bg,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        label,
        style: text.labelMedium!.copyWith(color: colors.inkMid),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate old) =>
      old.label != label || old.colors != colors;
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
