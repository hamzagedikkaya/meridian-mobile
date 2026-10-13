import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/day_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'account_card.dart';
import 'account_form.dart';
import 'reconcile_sheet.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

/// Archives [account] — it leaves the carousel and the pickers, its history
/// keeps counting — and offers "Geri al" (which restores it).
///
/// An account archived already is left alone: archiving it again would
/// change nothing, and its "Geri al" would restore an account the user had
/// archived on purpose.
Future<void> archiveAccount(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  if (account.archived) return;
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  // Under the app's messenger, and alive after this screen: where a failed
  // "Geri al" is said.
  final host = Navigator.of(context, rootNavigator: true).context;
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
        if (host.mounted) {
          showAppSnack(
            host,
            failureMessage(e, l, fallback: l.accountRestoreFailed),
            isError: true,
          );
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

  /// The header, measured: the FAB ("İşlem") shows only once its "+ İşlem"
  /// chip has scrolled away — one control per action on screen (§6.5).
  final _headerKey = GlobalKey();
  bool _pastHeader = false;

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
    final header = _headerKey.currentContext?.size?.height;
    final past = header != null && _scroll.position.pixels > header - 24;
    if (past != _pastHeader) setState(() => _pastHeader = past);
  }

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([accountsProvider]);
    await Future.wait([
      ref.read(transactionsProvider(_filters).notifier).refresh(),
      settleRefresh([ref.read(accountsProvider.future)]),
    ]);
  }

  Future<void> _add({String? kind}) async {
    final l = context.l10n;
    final saved = await openTransactionForm(
      context,
      initialAccountId: widget.accountId,
      initialKind: kind,
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
  /// offered instead — or, for one archived already, only said. What is
  /// recorded on it comes from the server.
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
    // Archived already (here, or on the web since this screen learnt it):
    // archiving is no way out for it.
    final archived = account.archived || detail.account.archived;
    if (!detail.deletable) {
      if (archived) {
        await showInfoDialog(
          context,
          title: l.accountCantDeleteTitle,
          message: l.accountCantDeleteArchived(
            detail.transactionsCount,
            detail.incomingTransfersCount,
          ),
        );
        return;
      }
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
    bool hasTransactions(Object error) =>
        error is ApiException && error.code == 'has_transactions';
    // A transaction recorded on it since the check: an archived account is
    // simply back, as it was — it is not told to archive itself.
    String? explain(Object error) {
      if (!archived || !hasTransactions(error)) return null;
      final refusal = error as ApiException;
      return l.accountCantDeleteArchived(
        (refusal.number('transactions_count') ?? 0).toInt(),
        (refusal.number('incoming_transfers_count') ?? 0).toInt(),
      );
    }

    // …and an active one is back, and can be archived instead.
    ({String label, VoidCallback run})? recover(Object error) =>
        !archived && hasTransactions(error)
            ? (
                label: l.actionArchive,
                run: () => repo.archiveAccount(account.id).then(
                      (_) {
                        if (!host.mounted) return;
                        showAppSnack(host, l.accountArchived(account.name));
                      },
                      onError: (Object e) {
                        if (!host.mounted) return;
                        showAppSnack(
                          host,
                          failureMessage(e, l,
                              fallback: l.accountArchiveFailed),
                          isError: true,
                        );
                      },
                    ),
              )
            : null;
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
        recover: recover,
        explain: explain,
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
      recover: recover,
      explain: explain,
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

    return CollapsingFabScope(
      child: Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? l.titleAccount),
        actions: [
          if (account != null) _menu(context, account),
        ],
      ),
      floatingActionButton: account == null || account.archived
          ? null
          : CollapsingFab(
              icon: Icons.add_rounded,
              label: l.financeAddTransactionFab,
              onPressed: _add,
              hidden: !_pastHeader,
            ),
      body: SyncHint.over(
        active: feedAsync.isRefetching || accountsAsync.isRefetching,
        child: RefreshIndicator.adaptive(
          color: c.gold,
          // The pull's own tick; the retry buttons call [_refresh] silently.
          onRefresh: () {
            Haptics.armed();
            return _refresh();
          },
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
                    : KeyedSubtree(
                        key: _headerKey,
                        child: _header(context, account, feed),
                      ),
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

  /// The account at the top (design-analysis §7.6): its type as an
  /// overline, the balance in Fraunces (where the tile's balance lands),
  /// this month's income and spending on it from the loaded history, then
  /// what can be done: a transaction, a transfer out of it, and squaring
  /// the balance with the real one. Linked goals, when there are any.
  Widget _header(
    BuildContext context,
    Account account,
    TransactionsFeed? feed,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    var income = 0;
    var expense = 0;
    for (final tx in feed?.items ?? const <Transaction>[]) {
      if (tx.account.id != account.id) continue;
      if (tx.date.year != today.year || tx.date.month != today.month) continue;
      if (tx.kind == 'income') income += tx.amountCents;
      if (tx.kind == 'expense') expense += tx.amountCents;
    }
    String money(int cents, MoneySign sign) => formatMoney(
          cents,
          account.currency,
          account.subunitToUnit,
          sign: sign,
          decimals: MoneyDecimals.auto,
        );
    final linkedGoals = ref
            .watch(accountDetailProvider(account.id))
            .value
            ?.data
            .linkedGoalsCount ??
        0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.md,
        Insets.gutter,
        Gap.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.accountTypeOverline(account.accountType),
                style: text.labelMedium,
              ),
              if (account.archived)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm, vertical: Gap.xxs),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Text(
                    l.accountArchivedBadge,
                    style: text.labelSmall!.copyWith(color: c.inkMid),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          AccountBalanceHero(
            accountId: account.id,
            child: MoneyText(
              account.balanceCents,
              currency: account.currency,
              subunitToUnit: account.subunitToUnit,
              variant: MoneyVariant.display,
            ),
          ),
          if (income != 0 || expense != 0) ...[
            const SizedBox(height: Gap.xs),
            Text(
              l.accountMonthSummary(
                income == 0 ? null : money(income, MoneySign.always),
                expense == 0 ? null : money(expense, MoneySign.negative),
              ),
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ],
          if (account.archived) ...[
            const SizedBox(height: Gap.lg),
            Text(
              l.accountArchivedNote,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              onPressed: () => restoreAccount(context, ref, account),
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              label: Text(l.actionRestore),
            ),
          ] else ...[
            const SizedBox(height: Gap.lg),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                _ActionChip(
                  label: l.financeAddTransactionFab,
                  icon: Icons.add_rounded,
                  filled: true,
                  onTap: _add,
                ),
                _ActionChip(
                  label: l.financeTransfer,
                  icon: Icons.swap_horiz_rounded,
                  onTap: () => _add(kind: 'transfer'),
                ),
                _ActionChip(
                  label: l.accountReconcile,
                  icon: Icons.balance_rounded,
                  onTap: () => showReconcileSheet(context, ref, account),
                ),
              ],
            ),
          ],
          if (linkedGoals > 0) ...[
            const SizedBox(height: Gap.sm),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => context.push('/goals'),
                borderRadius: Radii.mdAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Hit.min),
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 20, color: c.inkMid),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          l.accountLinkedGoals(linkedGoals),
                          style: text.titleSmall,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.inkLow,
                      ),
                    ],
                  ),
                ),
              ),
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
            // The header's "+ İşlem" is the way to add one: no second
            // button here (§6.5).
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l.financeNoTransactionsInAccount,
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

    final today = ref.watch(currentDayProvider);

    /// A day's spending from this account, for its heading: "−₺1.240".
    String? spentOn(_G g) {
      var cents = 0;
      for (final tx in g.items) {
        if (tx.kind == 'expense' && tx.account.id == widget.accountId) {
          cents += tx.amountCents;
        }
      }
      if (cents == 0) return null;
      final currency = account?.currency ?? g.items.first.account.currency;
      final subunit =
          account?.subunitToUnit ?? g.items.first.account.subunitToUnit;
      return formatMoneyCompact(
        cents,
        currency,
        subunit,
        sign: MoneySign.negative,
      );
    }

    return [
      for (final g in groups)
        DayHeader.group(
          key: ValueKey('day-${g.key}'),
          header: DayHeader.forDay(
            context,
            g.key,
            today: today,
            trailing: spentOn(g),
          ),
          slivers: [
        SliverList.builder(
          itemCount: g.items.length,
          itemBuilder: (context, i) {
            final tx = g.items[i];
            return TxSwipeToDelete(
              key: ValueKey('tx-${tx.id}'),
              tx: tx,
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
            );
          },
        ),
          ],
        ),
      // Room for the FAB (and the nav bar's inset), the loading spinner
      // centred in it.
      SliverToBoxAdapter(
        child: SizedBox(
          height: CollapsingFab.clearance(context),
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

/// One of the account header's actions (§7.6): a 36 dp pill in a 48 dp
/// target — [filled] gold for the main one, surface2 with a hairline for
/// the others. A button, not a choice: it is never "selected".
class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final fg = filled ? c.onGold : c.inkHi;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: PressableScale.small(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Material(
              color: filled ? c.gold : c.surface2,
              shape: StadiumBorder(
                side: filled ? BorderSide.none : BorderSide(color: c.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge!.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
