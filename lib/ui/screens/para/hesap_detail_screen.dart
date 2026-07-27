import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../models/account.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeletons.dart';
import 'para_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_row.dart';

class HesapDetailScreen extends ConsumerStatefulWidget {
  final int accountId;
  const HesapDetailScreen({super.key, required this.accountId});

  @override
  ConsumerState<HesapDetailScreen> createState() => _HesapDetailScreenState();
}

class _HesapDetailScreenState extends ConsumerState<HesapDetailScreen> {
  final _scroll = ScrollController();

  /// This account's feed key — the family isolates it from İşlemler's feed.
  TxFilters get _filters => TxFilters(accountId: widget.accountId);

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

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(transactionsProvider(_filters).notifier).loadMore();
    }
  }

  Future<bool> _confirmDelete(Transaction tx) async {
    final ok = await showConfirmDialog(
      context,
      title: 'İşlem silinsin mi?',
      message: tx.description ?? tx.category?.name,
      confirmLabel: 'Sil',
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
        showAppSnack(context, 'İşlem silindi');
      }
    } catch (_) {
      if (mounted) showAppSnack(context, 'Silinemedi', isError: true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final accounts = ref.watch(accountsProvider).value?.data;
    Account? account;
    if (accounts != null) {
      for (final a in accounts) {
        if (a.id == widget.accountId) account = a;
      }
    }
    final feedAsync = ref.watch(transactionsProvider(_filters));
    final feed = feedAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? 'Hesap'),
      ),
      body: RefreshIndicator.adaptive(
        color: c.gold,
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          await ref.read(transactionsProvider(_filters).notifier).refresh();
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(child: _header(context, account)),
            if (feed == null && feedAsync.isLoading)
              const SliverToBoxAdapter(child: _DetailSkeleton())
            else if (feed == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: EmptyState(
                    icon: Icons.cloud_off,
                    title: 'Sunucuya ulaşılamıyor',
                    actionLabel: 'Tekrar dene',
                    onAction: () => ref
                        .read(transactionsProvider(_filters).notifier)
                        .refresh(),
                  ),
                ),
              )
            else if (feed.items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Bu hesapta işlem yok',
                  ),
                ),
              )
            else
              ..._txSlivers(context, feed),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Account? account) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    if (account == null) {
      return const SizedBox(height: 120);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Hero(
            tag: 'account-bar-${account.id}',
            child: Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: hexColor(account.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(accountTypeLabel(account.accountType),
                    style: text.labelSmall!.copyWith(color: c.inkMid)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMoney(account.balanceCents, account.currency,
                        account.subunitToUnit),
                    style: text.displayMedium!
                        .copyWith(fontFeatures: tabularFigures),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _txSlivers(BuildContext context, TransactionsFeed feed) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final groups = <_G>[];
    for (final tx in feed.items) {
      final key = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (groups.isNotEmpty && groups.last.key == key) {
        groups.last.items.add(tx);
      } else {
        groups.add(_G(key, relativeDay(tx.date), [tx]));
      }
    }

    final slivers = <Widget>[];
    for (final g in groups) {
      slivers.add(SliverToBoxAdapter(
        child: Container(
          color: c.bg,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(g.label,
              style: text.labelMedium!.copyWith(color: c.inkMid)),
        ),
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
              child: TxRow(
                tx: tx,
                onTap: () async {
                  final saved =
                      await openTransactionForm(context, existing: tx);
                  if (saved == true && context.mounted) {
                    showAppSnack(context, 'İşlem güncellendi ✓');
                  }
                },
              ),
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
              : const SizedBox.shrink(),
        ),
      ),
    ));
    return slivers;
  }
}

class _G {
  final DateTime key;
  final String label;
  final List<Transaction> items;
  _G(this.key, this.label, this.items);
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return NokSkeleton(
      enabled: true,
      child: Column(
        children: [
          for (var i = 0; i < 8; i++)
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
