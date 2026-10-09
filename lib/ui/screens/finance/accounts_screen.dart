import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/sync_hint.dart';
import 'account_detail_screen.dart';
import 'account_form.dart';
import 'finance_utils.dart';

/// The Hesaplar page (`/finance/accounts`, design-analysis §7.6): every
/// account, the archived ones in their own group under the active ones —
/// open when [showArchived] (`?archived=1`, where the old archive page's
/// links now land). A tap opens an account; "Hesap" adds one.
///
/// WP-8 redesigns it (per-currency totals, tiles); until then it lists
/// them in rows.
class AccountsScreen extends ConsumerWidget {
  final bool showArchived;

  const AccountsScreen({super.key, this.showArchived = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(accountsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final all = withoutDeleted(
      async.value?.data ?? const <Account>[],
      hidden,
      DataScope.accounts,
      (a) => a.id,
    );
    final active = [for (final a in all) if (!a.archived) a];
    final archived = [for (final a in all) if (a.archived) a];

    Future<void> refresh() async {
      ref.read(dataSyncProvider).refresh([accountsProvider]);
      await settleRefresh([ref.read(accountsProvider.future)]);
    }

    Widget row(Account a, {Widget? trailing}) => NokturnRow(
          leading: LeadingCircle(
            color: hexColor(a.color),
            icon: Icons.account_balance_wallet_outlined,
          ),
          title: a.name,
          meta: [
            l.accountType(a.accountType),
            formatMoney(a.balanceCents, a.currency, a.subunitToUnit),
          ].join(' · '),
          onTap: () => context.push('/finance/account/${a.id}'),
          trailing: trailing,
        );

    Widget card(List<Widget> rows) => NokturnCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 72, color: c.divider),
                rows[i],
              ],
            ],
          ),
        );

    Widget body;
    if (async.isFirstLoad) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (async.hasFailed) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: l.errServerUnreachable,
            subtitle: l.errCheckWifi,
            actionLabel: l.actionRetry,
            onAction: refresh,
          ),
        ],
      );
    } else {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          if (active.isEmpty)
            EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: l.financeNoActiveAccounts,
            )
          else
            card([for (final a in active) row(a)]),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 16),
            Theme(
              // The group's own hairlines are the card's.
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const PageStorageKey('accounts-archived'),
                initiallyExpanded: showArchived,
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '${l.titleArchivedAccounts} (${archived.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  l.archivedAccountsBody,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: c.inkMid),
                ),
                children: [
                  card([
                    for (final a in archived)
                      row(
                        a,
                        trailing: TextButton(
                          onPressed: () => restoreAccount(context, ref, a),
                          child: Text(l.actionRestore),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.financeAccounts)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => openAccountForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.accountNew),
      ),
      body: Column(
        children: [
          if (async.refreshFailed)
            OfflineBanner(lastUpdated: async.value!.at, onRetry: refresh),
          Expanded(
            child: SyncHint.over(
              active: async.isRefetching,
              child: RefreshIndicator.adaptive(
                color: c.gold,
                onRefresh: refresh,
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
