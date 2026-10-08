import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'account_form.dart';
import 'finance_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

/// Archives [account] — it leaves the carousel and the pickers, its history
/// keeps counting — and offers "Geri al" (which restores it).
Future<void> archiveAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.archiveAccount(account.id);
  } catch (e) {
    if (context.mounted) {
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.accountArchiveFailed),
        isError: true,
      );
    }
    return;
  }
  if (!context.mounted) return;
  showAppSnack(
    context,
    l.accountArchived(account.name),
    actionLabel: l.actionUndo,
    onAction: () async {
      try {
        await repo.unarchiveAccount(account.id);
      } catch (e) {
        if (messenger.mounted) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(
                failureMessage(e, l, fallback: l.accountRestoreFailed),
              ),
            ));
        }
      }
    },
  );
}

/// Brings an archived [account] back to the carousel and the pickers.
Future<void> restoreAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final l = context.l10n;
  try {
    await ref.read(repositoryProvider).unarchiveAccount(account.id);
    if (context.mounted) showAppSnack(context, l.accountRestored(account.name));
  } catch (e) {
    if (context.mounted) {
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.accountRestoreFailed),
        isError: true,
      );
    }
  }
}

class AccountDetailScreen extends ConsumerStatefulWidget {
  final int accountId;
  const AccountDetailScreen({super.key, required this.accountId});

  @override
  ConsumerState<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  final _scroll = ScrollController();

  /// This account's history — its own transactions and the transfers into
  /// it — isolated from İşlemler's feed by the family key.
  TxFilters get _filters => TxFilters.account(widget.accountId);

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

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([accountsProvider]);
    await Future.wait([
      ref.read(transactionsProvider(_filters).notifier).refresh(),
      settleRefresh([ref.read(accountsProvider.future)]),
    ]);
  }

  Future<void> _add() async {
    final l = context.l10n;
    final saved = await openTransactionForm(
      context,
      initialAccountId: widget.accountId,
    );
    if (saved == null || !mounted) return;
    ref.read(transactionsProvider(_filters).notifier).replaceLocally(saved);
    showAppSnack(context, l.txSaved);
  }

  Future<void> _edit(Account account) async {
    await openAccountForm(context, existing: account);
  }

  /// Deletes the account when nothing is recorded on it — at once, with
  /// "Geri al", or after saying what else goes when it pays subscriptions or
  /// feeds goals. An account with history cannot be deleted (other
  /// accounts' transfers into it would lose their target): archiving is
  /// offered instead. What is recorded on it comes from the server.
  Future<void> _delete(Account account) async {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final host = navigator.context;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    AccountDetail detail;
    try {
      detail = (await ref.read(accountDetailProvider(account.id).future)).data;
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.accountDeleteFailed),
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    if (!detail.deletable) {
      final archive = await showConfirmDialog(
        context,
        title: l.accountCantDeleteTitle,
        message: l.errHasTransactions(
          detail.transactionsCount,
          detail.incomingTransfersCount,
        ),
        confirmLabel: l.actionArchive,
      );
      if (archive && mounted) await archiveAccount(context, ref, account);
      return;
    }
    final consequences = l.accountDeleteConsequences(
      subscriptions: detail.subscriptionsCount,
      goals: detail.linkedGoalsCount,
    );
    final record = (scope: DataScope.accounts, id: account.id);
    Future<void> send() => repo.deleteAccount(account.id);
    if (consequences.isEmpty) {
      // Nothing else goes with it: delete with an undo.
      navigator.pop();
      if (!host.mounted) return;
      deleteWithUndo(
        host,
        deletes,
        record: record,
        message: l.accountDeleted(account.name),
        send: send,
        failedMessage: l.accountDeleteFailed,
      );
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: l.accountDeleteTitle(account.name),
      message: consequences,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    navigator.pop();
    if (!host.mounted) return;
    deleteNow(
      host,
      deletes,
      record: record,
      message: l.accountDeleted(account.name),
      send: send,
      failedMessage: l.accountDeleteFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    // The day headers ("Bugün", "Dün") are relative to today.
    ref.watch(currentDayProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.value?.data;
    final hidden = ref.watch(deferredDeletesProvider);
    Account? account;
    if (accounts != null) {
      for (final a in accounts) {
        if (a.id == widget.accountId) account = a;
      }
    }
    // The server no longer has it: deleted on the web or another device.
    // (One deleted here leaves the screen as it goes.)
    final gone = accounts != null && account == null;
    final feedAsync = ref.watch(transactionsProvider(_filters));
    final feed = feedAsync.value;
    // A failed refresh keeps the last list up; say that it is not current.
    final offline = feedAsync.refreshFailed || accountsAsync.refreshFailed;

    if (gone) {
      return Scaffold(
        appBar: AppBar(title: Text(l.titleAccount)),
        body: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: l.accountGone,
          subtitle: l.errRecordGoneBody,
          actionLabel: l.actionBack,
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? l.titleAccount),
        actions: [
          if (account != null) _menu(context, account),
        ],
      ),
      floatingActionButton: account == null || account.archived
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(l.financeAddTransactionFab),
            ),
      body: SyncHint.over(
        active: feedAsync.isRefetching || accountsAsync.isRefetching,
        child: RefreshIndicator.adaptive(
          color: c.gold,
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (offline)
                SliverToBoxAdapter(
                  child: OfflineBanner(
                    lastUpdated: feed?.at ?? accountsAsync.value!.at,
                    onRetry: _refresh,
                  ),
                ),
              SliverToBoxAdapter(
                child: account == null
                    ? const _HeaderSkeleton()
                    : _header(context, account),
              ),
              if (feed == null && feedAsync.isFirstLoad)
                const SliverToBoxAdapter(child: _DetailSkeleton())
              else if (feed == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: EmptyState(
                      icon: Icons.cloud_off,
                      title: l.errServerUnreachable,
                      actionLabel: l.actionRetry,
                      onAction: () => ref
                          .read(transactionsProvider(_filters).notifier)
                          .refresh(),
                    ),
                  ),
                )
              else
                ..._feedSlivers(context, feed, hidden, account),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, Account account) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l.actionMoreOptions,
      onSelected: (action) {
        switch (action) {
          case 'edit':
            _edit(account);
          case 'archive':
            archiveAccount(context, ref, account);
          case 'restore':
            restoreAccount(context, ref, account);
          case 'delete':
            _delete(account);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(l.actionEdit)),
        if (account.archived)
          PopupMenuItem(value: 'restore', child: Text(l.actionRestore))
        else
          PopupMenuItem(value: 'archive', child: Text(l.actionArchive)),
        PopupMenuItem(value: 'delete', child: Text(l.actionDelete)),
      ],
    );
  }

  Widget _header(BuildContext context, Account account) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l.accountType(account.accountType),
                            style:
                                text.labelSmall!.copyWith(color: c.inkMid),
                          ),
                        ),
                        if (account.archived) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.hairline),
                            ),
                            child: Text(
                              l.accountArchivedBadge,
                              style:
                                  text.labelSmall!.copyWith(color: c.inkMid),
                            ),
                          ),
                        ],
                      ],
                    ),
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
          if (account.archived) ...[
            const SizedBox(height: 16),
            Text(
              l.accountArchivedNote,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => restoreAccount(context, ref, account),
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              label: Text(l.actionRestore),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _feedSlivers(
    BuildContext context,
    TransactionsFeed feed,
    Set<DeletedRecord> hidden,
    Account? account,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final items = withoutDeleted(
      feed.items,
      hidden,
      DataScope.transactions,
      (tx) => tx.id,
    );
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l.financeNoTransactionsInAccount,
              actionLabel: account == null || account.archived
                  ? null
                  : l.financeFirstTxAction,
              onAction:
                  account == null || account.archived ? null : _add,
            ),
          ),
        ),
      ];
    }
    final groups = <_G>[];
    for (final tx in items) {
      final key = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (groups.isNotEmpty && groups.last.key == key) {
        groups.last.items.add(tx);
      } else {
        groups.add(_G(key, l.relativeDay(tx.date), [tx]));
      }
    }

    void onSaved(Transaction saved) => ref
        .read(transactionsProvider(_filters).notifier)
        .replaceLocally(saved);

    return [
      for (final g in groups) ...[
        SliverToBoxAdapter(
          child: Semantics(
            header: true,
            child: Container(
              color: c.bg,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(g.label,
                  style: text.labelMedium!.copyWith(color: c.inkMid)),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: g.items.length,
          itemBuilder: (context, i) {
            final tx = g.items[i];
            void delete() => deleteTransactionWithUndo(context, ref, tx);
            return Semantics(
              customSemanticsActions: {
                CustomSemanticsAction(label: l.actionDelete): delete,
              },
              child: Dismissible(
                key: ValueKey('tx-${tx.id}'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => delete(),
                background: Container(
                  color: c.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.actionDelete,
                        style: text.labelLarge!.copyWith(color: c.bg),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.delete_outline, color: c.bg),
                    ],
                  ),
                ),
                child: TxRow(
                  tx: tx,
                  perspectiveAccountId: widget.accountId,
                  onTap: () => showTransactionSheet(
                    context,
                    ref,
                    tx,
                    perspectiveAccountId: widget.accountId,
                    onSaved: onSaved,
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }
}

class _G {
  final DateTime key;
  final String label;
  final List<Transaction> items;
  _G(this.key, this.label, this.items);
}

/// The header's place while the accounts load: its size, never a blank.
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return NokSkeleton(
      enabled: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: c.skeletonBone,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
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
