import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/sync_hint.dart';
import 'account_detail_screen.dart';
import 'finance_utils.dart';

/// The accounts that were archived — out of the carousel and the pickers,
/// still counted in every total — each a tap from its history and a button
/// from being restored.
class ArchivedAccountsScreen extends ConsumerWidget {
  const ArchivedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(accountsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final archived = withoutDeleted(
      (async.value?.data ?? const []).where((a) => a.archived),
      hidden,
      DataScope.accounts,
      (a) => a.id,
    );

    Future<void> refresh() async {
      ref.read(dataSyncProvider).refresh([accountsProvider]);
      await settleRefresh([ref.read(accountsProvider.future)]);
    }

    Widget body;
    if (async.isFirstLoad) {
      body = const Center(child: CircularProgressIndicator());
    } else if (async.hasFailed) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off,
            title: l.errServerUnreachable,
            subtitle: l.errCheckWifi,
            actionLabel: l.actionRetry,
            onAction: refresh,
          ),
        ],
      );
    } else if (archived.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: l.archivedAccountsEmpty,
            subtitle: l.archivedAccountsBody,
          ),
        ],
      );
    } else {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.archivedAccountsBody,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: c.inkMid),
            ),
          ),
          NokturnCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < archived.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 72, color: c.divider),
                  NokturnRow(
                    leading: LeadingCircle(
                      color: hexColor(archived[i].color),
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    title: archived[i].name,
                    meta: [
                      l.accountType(archived[i].accountType),
                      formatMoney(
                        archived[i].balanceCents,
                        archived[i].currency,
                        archived[i].subunitToUnit,
                      ),
                    ].join(' · '),
                    onTap: () =>
                        context.push('/finance/account/${archived[i].id}'),
                    trailing: TextButton(
                      onPressed: () =>
                          restoreAccount(context, ref, archived[i]),
                      child: Text(l.actionRestore),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.titleArchivedAccounts)),
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
