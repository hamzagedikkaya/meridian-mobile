import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sync_hint.dart';
import 'account_detail_screen.dart';
import 'account_form.dart';
import 'finance_utils.dart';

/// The Hesaplar page (`/finance/accounts`, design-analysis §7.6).
///
/// * A totals card: the balances per currency, never added across them
///   ("TRY ₺36.250,00", "GAU 412 gr").
/// * The active accounts grouped by type — Nakit, Banka, Kredi kartı,
///   Birikim, Kripto — in 64 dp rows (the type's icon in the account's
///   tone, the name, the balance). A tap opens the account.
/// * The archived ones under "Arşivlenmiş hesaplar (n)", each with "Geri
///   yükle" — open when [showArchived] (`?archived=1`, where the old
///   archive page's links land).
/// * "Hesap" adds one.
class AccountsScreen extends ConsumerWidget {
  final bool showArchived;

  const AccountsScreen({super.key, this.showArchived = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
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
    final defaultId = defaultAccountId(ref);
    final userCurrency =
        ref.watch(currentUserProvider.select((u) => u?.currency)) ?? 'TRY';

    Future<void> refresh() async {
      ref.read(dataSyncProvider).refresh([accountsProvider]);
      await settleRefresh([ref.read(accountsProvider.future)]);
    }

    Widget row(Account a, {Widget? trailing}) => NokturnRow(
          leading: LeadingCircle.tone(
            entityTone(a.color, c),
            icon: accountTypeIcon(a.accountType),
          ),
          title: a.name,
          meta: [
            l.accountType(a.accountType),
            if (a.id == defaultId && !a.archived) l.accountDefaultBadge,
          ].join(' · '),
          onTap: () => context.push('/finance/account/${a.id}'),
          trailing: trailing ??
              MoneyText(
                a.balanceCents,
                currency: a.currency,
                subunitToUnit: a.subunitToUnit,
              ),
        );

    Widget card(List<Widget> rows) => NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) NokturnRow.divider(),
                rows[i],
              ],
            ],
          ),
        );

    Widget totals() {
      final sums = balancesByCurrency(active, first: userCurrency);
      return NokturnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.accountsTotalsTitle, style: text.labelMedium),
            const SizedBox(height: Gap.sm),
            for (final s in sums)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(
                  children: [
                    Text(
                      s.currency,
                      style: text.bodyMedium!.copyWith(color: c.inkMid),
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MoneyText(
                            s.cents,
                            currency: s.currency,
                            subunitToUnit: s.subunitToUnit,
                          ),
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

    final empty = !async.isFirstLoad && !async.hasFailed && active.isEmpty;
    Widget body;
    if (async.isFirstLoad) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (async.hasFailed) {
      body = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: EmptyState.error(onRetry: refresh)),
          ),
        ],
      );
    } else {
      final types = <String>{
        ...accountTypes,
        // A type this app does not know yet still lists its accounts.
        for (final a in active) a.accountType,
      };
      final groups = [
        for (final type in types)
          (type, [for (final a in active) if (a.accountType == type) a]),
      ].where((g) => g.$2.isNotEmpty);
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.sm,
          Insets.gutter,
          CollapsingFab.clearance(context),
        ),
        children: [
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x4),
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: l.financeNoActiveAccounts,
                subtitle: archived.isEmpty ? null : l.financeNoActiveAccountsBody,
                actionLabel: l.accountNew,
                onAction: () => openAccountForm(context),
              ),
            )
          else ...[
            totals(),
            for (final (type, accounts) in groups) ...[
              SectionHeader(
                l.accountType(type),
                padding: const EdgeInsets.only(top: Gap.xxl, bottom: Gap.xs),
              ),
              card([for (final a in accounts) row(a)]),
            ],
          ],
          if (archived.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            Theme(
              // The group's own hairlines are the card's.
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const PageStorageKey('accounts-archived'),
                initiallyExpanded: showArchived,
                // ExpansionTile ignores reduced motion on its own (§5.9).
                expansionAnimationStyle: Motion.reduced(context)
                    ? AnimationStyle.noAnimation
                    : null,
                tilePadding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '${l.titleArchivedAccounts} (${archived.length})',
                  style: text.titleSmall,
                ),
                subtitle: Text(
                  l.archivedAccountsBody,
                  style: text.bodySmall!.copyWith(color: c.inkMid),
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

    return CollapsingFabScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l.financeAccounts)),
        floatingActionButton: CollapsingFab(
          icon: Icons.add_rounded,
          label: l.accountFab,
          onPressed: () => openAccountForm(context),
          // The empty state carries the same action.
          hidden: empty,
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
      ),
    );
  }
}
