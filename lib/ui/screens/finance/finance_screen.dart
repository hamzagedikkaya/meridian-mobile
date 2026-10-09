import 'dart:math' as math;

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
import '../../../models/finance_dashboard.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/charts.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'account_card.dart';
import 'account_form.dart';
import 'budget_sheet.dart';
import 'finance_utils.dart';
import 'subscription_form.dart';
import 'subscriptions_screen.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with TabRootScroll<FinanceScreen> {
  @override
  AppTab get tab => AppTab.finance;

  String _scope = 'month';
  final _accountsCtrl = PageController(viewportFraction: 0.88);
  int _accountPage = 0;

  /// The carousel is on its way to the page a dot was tapped for: the pages
  /// it passes do not tick.
  bool _goingToPage = false;

  /// The first-run button is opening the cash account.
  bool _openingCash = false;

  /// Sections play their entrance only with the first data (see [Entrance]).
  bool _entered = false;

  @override
  void dispose() {
    _accountsCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    Haptics.celebrate();
    refreshTab(ref, AppTab.finance);
    await settleRefresh([
      ref.read(financeDashboardProvider.future),
      ref.read(accountsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final dashAsync = ref.watch(financeDashboardProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final dash = dashAsync.value?.data;
    final hidden = ref.watch(deferredDeletesProvider);
    final allAccounts = accountsAsync.value?.data == null
        ? null
        : withoutDeleted(
            accountsAsync.value!.data,
            hidden,
            DataScope.accounts,
            (a) => a.id,
          );
    final active = allAccounts?.where((a) => !a.archived).toList();

    // The dashboard is the screen: once it has failed with nothing cached
    // (retries done), say so — never an endless skeleton, whatever the
    // accounts did.
    final dashFailed = dashAsync.hasFailed;
    final accountsFailed = accountsAsync.hasFailed;
    final offline = dashAsync.refreshFailed || accountsAsync.refreshFailed;
    final refetching = dashAsync.isRefetching || accountsAsync.isRefetching;

    return primaryScroll(Scaffold(
      appBar: AppBar(
        title: Text(
          l.titleFinance,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        actions: [
          SegmentedPill<String>(
            options: [
              ('month', l.financeScopeMonth),
              ('year', l.financeScopeYear),
            ],
            selected: _scope,
            onChanged: (v) => setState(() => _scope = v),
          ),
          _menu(context),
        ],
      ),
      // With no account yet, the first-run card is the way in.
      floatingActionButton: active == null || active.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _openAdd(context),
              icon: const Icon(Icons.add),
              label: Text(l.financeAddTransactionFab),
            ),
      body: Column(
        children: [
          if (offline)
            OfflineBanner(
              lastUpdated: dashAsync.value?.at ?? DateTime.now(),
              onRetry: _refresh,
            ),
          Expanded(
            child: SyncHint.over(
              active: refetching,
              child: RefreshIndicator.adaptive(
                color: c.gold,
                onRefresh: _refresh,
                child: dashFailed
                    ? _errorState()
                    : dash == null
                        ? const _FinanceSkeleton()
                        : _content(
                            context,
                            dash,
                            allAccounts,
                            hidden,
                            accountsFailed: accountsFailed,
                          ),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _menu(BuildContext context) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l.actionMoreOptions,
      onSelected: (path) => context.push(path),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '/finance/categories',
          child: Text(l.financeMenuCategories),
        ),
        PopupMenuItem(
          value: '/finance/subscriptions',
          child: Text(l.financeMenuSubscriptions),
        ),
        PopupMenuItem(
          value: '/finance/accounts/archived',
          child: Text(l.financeMenuArchivedAccounts),
        ),
      ],
    );
  }

  Future<void> _openAdd(BuildContext context) async {
    final saved = await openTransactionForm(context);
    if (saved != null && context.mounted) {
      showAppSnack(context, context.l10n.txSaved);
    }
  }

  Future<void> _addAccount() async {
    await openAccountForm(context);
  }

  /// A page dot was tapped: the carousel shows that page.
  Future<void> _showAccountPage(int page) async {
    if (!_accountsCtrl.hasClients || page == _accountPage) return;
    Haptics.tick();
    _goingToPage = true;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _accountsCtrl.jumpToPage(page);
      } else {
        await _accountsCtrl.animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _goingToPage = false;
    }
  }

  /// The first-run shortcut: a cash account in the user's currency, in one
  /// tap. The card then moves on to the first transaction.
  Future<void> _openCashAccount() async {
    final l = context.l10n;
    setState(() => _openingCash = true);
    try {
      final account = await ref.read(repositoryProvider).createAccount(
            AccountInput(
              name: l.financeCashAccountName,
              accountType: 'cash',
              color: recordSwatches.first,
            ),
          );
      if (!mounted) return;
      Haptics.success();
      showAppSnack(context, l.accountCreated(account.name));
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.accountSaveFailed),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _openingCash = false);
    }
  }

  Widget _errorState() {
    final l = context.l10n;
    return ListView(
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
    );
  }

  Widget _content(
    BuildContext context,
    FinanceDashboard dash,
    List<Account>? accounts,
    Set<DeletedRecord> hidden, {
    required bool accountsFailed,
  }) {
    final active = accounts?.where((a) => !a.archived).toList();
    final recent = withoutDeleted(
      dash.recentTransactions,
      hidden,
      DataScope.transactions,
      (tx) => tx.id,
    );
    // Keyed by section, so a card that appears or goes (budgets,
    // subscriptions) after a refresh does not shift the others' state.
    final List<(String, Widget)> sections;
    if (accounts != null && accounts.isEmpty) {
      // First run: no account at all. One calm card, one step.
      sections = [('first-run', _firstRunCard(context))];
    } else {
      sections = [
        ('hero', _hero(context, dash)),
        (
          'accounts',
          _accountsSection(context, active, accounts, failed: accountsFailed),
        ),
        if (active != null && active.isNotEmpty && recent.isEmpty)
          ('first-transaction', _firstTransactionCard(context)),
        ('six-month', _sixMonthCard(context, dash)),
        ('categories', _categoriesCard(context, dash)),
        ('budgets', _budgetsCard(context, dash, hidden)),
        ('subscriptions', _subscriptionsCard(context, dash, hidden)),
        ('recent', _recentCard(context, recent)),
      ];
    }

    final stagger = !_entered;
    if (stagger) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _entered = true);
    }

    return ListView.separated(
      primary: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sections.length,
      // Lets a section keep its element when one above appears or goes.
      findItemIndexCallback: (key) {
        final index = sections.indexWhere((s) => ValueKey(s.$1) == key);
        return index < 0 ? null : index;
      },
      separatorBuilder: (_, _) => const SizedBox(height: 32),
      itemBuilder: (context, i) => Entrance.staggered(
        key: ValueKey(sections[i].$1),
        play: stagger,
        index: i,
        child: sections[i].$2,
      ),
    );
  }

  // --- first run -------------------------------------------------------------

  Widget _firstRunCard(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 40, color: c.gold),
          const SizedBox(height: 16),
          Text(l.financeFirstRunTitle, style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            l.financeFirstRunBody,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: l.financeFirstRunCash,
            loading: _openingCash,
            onPressed: _openCashAccount,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _openingCash ? null : _addAccount,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.financeFirstRunOther),
          ),
        ],
      ),
    );
  }

  Widget _firstTransactionCard(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.financeFirstTxTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            l.financeFirstTxBody,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: l.financeFirstTxAction,
            onPressed: () => _openAdd(context),
          ),
        ],
      ),
    );
  }

  // --- hero ------------------------------------------------------------------

  Widget _hero(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final totals = _scope == 'year' ? dash.year : dash.month;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _scope == 'year' ? l.todayYearNet : l.todayMonthNet,
            style: text.labelMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: 8),
          // Ay↔Yıl swaps the net value with a §5 300ms slide-up-fade.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: MoneyText(
              totals.netCents,
              key: ValueKey(_scope),
              currency: dash.currency,
              subunitToUnit: dash.subunitToUnit,
              variant: MoneyVariant.hero,
              signed: true,
              positiveGreen: true,
            ),
          ),
          const SizedBox(height: 12),
          // Single line per design; scale down so long year-scope totals never
          // overflow on narrow screens / larger text scale.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text('${l.financeIncome} ',
                    style: text.titleSmall!.copyWith(color: c.inkMid)),
                MoneyText(
                  totals.incomeCents,
                  currency: dash.currency,
                  subunitToUnit: dash.subunitToUnit,
                  variant: MoneyVariant.row,
                  signed: true,
                  positiveGreen: true,
                ),
                const SizedBox(width: 20),
                Text('${l.financeExpense} ',
                    style: text.titleSmall!.copyWith(color: c.inkMid)),
                MoneyText(
                  totals.expenseCents,
                  currency: dash.currency,
                  subunitToUnit: dash.subunitToUnit,
                  variant: MoneyVariant.row,
                  negative: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- accounts --------------------------------------------------------------

  Widget _accountsSection(
    BuildContext context,
    List<Account>? active,
    List<Account>? all, {
    required bool failed,
  }) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.financeAccounts,
          trailing: IconButton(
            onPressed: _addAccount,
            tooltip: l.accountNew,
            icon: const Icon(Icons.add),
          ),
        ),
        _accountsCarousel(context, active, all, failed: failed),
      ],
    );
  }

  Widget _accountsCarousel(
    BuildContext context,
    List<Account>? accounts,
    List<Account>? all, {
    required bool failed,
  }) {
    final c = context.nok;
    final l = context.l10n;
    // Not loaded (yet): never claim there are no accounts — a bone the
    // carousel's size while loading, the reason when it failed.
    if (accounts == null) {
      if (failed) {
        return NokturnCard(
          child: EmptyState(
            icon: Icons.cloud_off,
            title: l.errServerUnreachable,
            actionLabel: l.actionRetry,
            onAction: () => refreshTab(ref, AppTab.finance),
          ),
        );
      }
      return NokSkeleton(
        enabled: true,
        child: Container(
          // The cards and their page dots.
          height: AccountCard.heightFor(context) + _dotTarget,
          decoration: BoxDecoration(
            color: c.skeletonBone,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    if (accounts.isEmpty) {
      // Every account is archived.
      return NokturnCard(
        child: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: l.financeNoActiveAccounts,
          subtitle: l.financeNoActiveAccountsBody,
          actionLabel: l.accountNew,
          onAction: _addAccount,
          secondaryLabel: l.financeMenuArchivedAccounts,
          onSecondary: () => context.push('/finance/accounts/archived'),
        ),
      );
    }
    final pageCount = accounts.length + 1;
    // A refresh can shorten the list (an account archived on the web) under
    // the page the carousel was on; the PageView settles on its last page.
    final activePage = _accountPage.clamp(0, pageCount - 1);
    return Column(
      children: [
        SizedBox(
          // As tall as a card needs at the text size in use.
          height: AccountCard.heightFor(context),
          child: PageView.builder(
            controller: _accountsCtrl,
            itemCount: pageCount,
            onPageChanged: (i) {
              if (!_goingToPage) Haptics.tick();
              setState(() => _accountPage = i);
            },
            itemBuilder: (context, i) {
              final child = i < accounts.length
                  ? AccountCard(
                      account: accounts[i],
                      onTap: () =>
                          context.push('/finance/account/${accounts[i].id}'),
                    )
                  : AccountAddCard(onTap: _addAccount);
              // Off-center cards shrink slightly so the active page reads as
              // the focal card in the snap carousel.
              return AnimatedBuilder(
                animation: _accountsCtrl,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: child,
                ),
                builder: (context, inner) {
                  var page = activePage.toDouble();
                  // Guard: reading .page asserts unless exactly one viewport is
                  // attached (a rebuild can transiently attach two).
                  if (_accountsCtrl.hasClients &&
                      _accountsCtrl.positions.length == 1 &&
                      _accountsCtrl.position.hasContentDimensions) {
                    page = _accountsCtrl.page ?? page;
                  }
                  final dist = (page - i).abs().clamp(0.0, 1.0);
                  return Transform.scale(scale: 1 - dist * 0.06, child: inner);
                },
              );
            },
          ),
        ),
        // Each dot shows its page on a tap, a 48 dp target (design-research
        // §6.2) — narrower only when that many cannot stand side by side.
        LayoutBuilder(
          builder: (context, constraints) {
            final slot =
                math.min(_dotTarget, constraints.maxWidth / pageCount);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pageCount; i++)
                  // One stop per dot for a screen reader; its detector is
                  // left out of the tree, so this node answers the
                  // double-tap itself.
                  Semantics(
                    button: true,
                    selected: i == activePage,
                    label: l.accountsCarouselPage(i + 1, pageCount),
                    onTap: i == activePage ? null : () => _showAccountPage(i),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showAccountPage(i),
                      child: SizedBox(
                        width: slot,
                        height: _dotTarget,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            width: i == activePage ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i == activePage ? c.gold : c.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// A page dot's target, square: the height of the row of dots under the
  /// carousel, and each dot's width while they all fit side by side.
  static const _dotTarget = 48.0;

  // --- six month -------------------------------------------------------------

  Widget _sixMonthCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final s = dash.sixMonthSeries;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.financeLast6Months, style: text.titleMedium),
          const SizedBox(height: 16),
          SixMonthBars(
            labels: s.labels.map(shortMonthLabel).toList(),
            incomeCents: s.incomeCents,
            expenseCents: s.expenseCents,
            currency: dash.currency,
            subunitToUnit: dash.subunitToUnit,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ChartLegendDot(c.chartIncome),
              const SizedBox(width: 6),
              Text(l.financeIncome,
                  style: text.labelSmall!.copyWith(color: c.inkMid)),
              const SizedBox(width: 16),
              ChartLegendDot(c.chartExpense),
              const SizedBox(width: 6),
              Text(l.financeExpense,
                  style: text.labelSmall!.copyWith(color: c.inkMid)),
            ],
          ),
        ],
      ),
    );
  }

  // --- categories donut ------------------------------------------------------

  /// İşlemler, filtered to this month's expenses of [categoryId] — or, with
  /// [uncategorized], to the ones without a category.
  void _drillInto({int? categoryId, bool uncategorized = false}) {
    final month = monthOf(ref.read(currentDayProvider));
    context.push(transactionsLocation(TxFilters(
      kind: 'expense',
      categoryId: categoryId,
      uncategorized: uncategorized,
      from: month.from,
      to: month.to,
    )));
  }

  void _openSlice(FinanceDashboard dash, PieSlice slice) {
    if (slice.uncategorized) {
      _drillInto(uncategorized: true);
    } else {
      _showBreakdown(context, dash, slice);
    }
  }

  Widget _categoriesCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final pie = dash.pie;
    if (pie.isEmpty) {
      return NokturnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.financeCategoriesThisMonth, style: text.titleMedium),
            const SizedBox(height: 12),
            Text(
              l.financeNoSpendThisMonth,
              style: text.bodyMedium!.copyWith(color: c.inkLow),
            ),
          ],
        ),
      );
    }

    // Every expense of the month is in a slice — the uncategorized ones
    // too — so the slices add up to the month's spending.
    final total = pie.fold<int>(0, (a, s) => a + s.amountCents);
    final ranked = [
      for (final s in pie)
        if (!s.uncategorized) s,
    ]..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final top = ranked.take(5).toList();
    final otherCents = ranked.skip(5).fold<int>(0, (a, s) => a + s.amountCents);
    final uncategorized = pie.where((s) => s.uncategorized).firstOrNull;

    Widget legendRow({
      required Color color,
      required String name,
      required int cents,
      VoidCallback? onTap,
      Widget? extra,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              ChartLegendDot(color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.bodyMedium),
                    ?extra,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(cents, dash.currency, dash.subunitToUnit),
                style: text.bodyMedium!.copyWith(fontFeatures: tabularFigures),
              ),
              const SizedBox(width: 8),
              Text(
                l.percent(total == 0 ? 0 : cents / total * 100),
                style: text.labelSmall!.copyWith(color: c.inkMid),
              ),
            ],
          ),
        ),
      );
    }

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.financeCategoriesThisMonth, style: text.titleMedium),
          const SizedBox(height: 16),
          Center(
            child: DonutChart(
              sections: [
                for (final s in pie)
                  DonutSection(
                    value: s.amountCents.toDouble(),
                    color: hexColor(s.color),
                  ),
              ],
              onSliceTap: (i) => _openSlice(dash, pie[i]),
              centerTotalCents: total,
              centerCurrency: dash.currency,
              centerSubunitToUnit: dash.subunitToUnit,
              centerLabel: l.financeExpense,
            ),
          ),
          const SizedBox(height: 16),
          for (final s in top)
            legendRow(
              color: hexColor(s.color),
              name: s.name,
              cents: s.amountCents,
              onTap: () => _openSlice(dash, s),
            ),
          if (otherCents > 0)
            legendRow(
              color: c.inkFaint,
              name: l.financeOtherCategories,
              cents: otherCents,
            ),
          if (uncategorized != null)
            legendRow(
              color: hexColor(uncategorized.color, fallback: c.inkLow),
              name: l.financeUncategorized,
              cents: uncategorized.amountCents,
              onTap: () => _drillInto(uncategorized: true),
              extra: Text(
                l.financeCategorize,
                style: text.labelMedium!.copyWith(color: c.gold),
              ),
            ),
        ],
      ),
    );
  }

  /// A slice's spending this month, by where it is filed; a row opens those
  /// transactions in İşlemler.
  ///
  /// A category whose subcategories were used splits into the part filed
  /// under the category itself ("Market (genel)", as the web says it) and
  /// each subcategory, under a "Tümü" row for the whole slice. A top-level
  /// category's filter takes its subcategories along, so İşlemler can show
  /// the whole slice or one subcategory, but not the category's own part:
  /// that row opens nothing, rather than a list that adds up to more.
  void _showBreakdown(
      BuildContext context, FinanceDashboard dash, PieSlice slice) {
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final rows = <({String title, String? meta, int cents, int? drillId})>[
      if (slice.breakdown.isEmpty)
        (
          title: slice.name,
          meta: null,
          cents: slice.amountCents,
          drillId: slice.id,
        )
      else ...[
        (
          title: l.financeSliceAll,
          meta: l.financeSliceAllMeta,
          cents: slice.amountCents,
          drillId: slice.id,
        ),
        for (final b in slice.breakdown)
          (
            title: b.isRoot ? l.financeSliceDirect(b.name) : b.name,
            meta: null,
            cents: b.amountCents,
            drillId: b.isRoot ? null : b.id,
          ),
      ],
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(slice.name, style: text.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final row in rows)
                    NokturnRow(
                      leading: LeadingCircle(
                        color: hexColor(slice.color),
                        icon: Icons.circle,
                      ),
                      title: row.title,
                      meta: row.meta,
                      trailing: MoneyText(
                        row.cents,
                        currency: dash.currency,
                        subunitToUnit: dash.subunitToUnit,
                        negative: true,
                      ),
                      // A row opens that spending this month.
                      onTap: switch (row.drillId) {
                        final id? => () {
                            Navigator.of(sheet).pop();
                            _drillInto(categoryId: id);
                          },
                        null => null,
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- budgets ---------------------------------------------------------------

  Widget _budgetsCard(
    BuildContext context,
    FinanceDashboard dash,
    Set<DeletedRecord> hidden,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final budgets = withoutDeleted(
      dash.budgets,
      hidden,
      DataScope.budgets,
      (b) => b.id,
    );
    Color stateColor(String s) => switch (s) {
          'over' => c.error,
          'warning' => c.warning,
          _ => c.income,
        };

    final header = Row(
      children: [
        Expanded(child: Text(l.financeBudgets, style: text.titleMedium)),
        TextButton.icon(
          onPressed: () => showBudgetSheet(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l.actionAdd),
        ),
      ],
    );

    if (budgets.isEmpty) {
      return NokturnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 4),
            Text(
              l.financeBudgetsEmpty,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
          ],
        ),
      );
    }

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          for (var i = 0; i < budgets.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _budgetRow(context, dash, budgets[i], stateColor),
          ],
        ],
      ),
    );
  }

  Widget _budgetRow(BuildContext context, FinanceDashboard dash,
      BudgetStatus b, Color Function(String) stateColor) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final over = b.state == 'over';
    String money(int cents) =>
        formatMoney(cents, dash.currency, dash.subunitToUnit);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(b.categoryName, style: text.titleSmall),
        const SizedBox(height: 8),
        PacedProgressBar(
          value: (b.barPercent / 100).clamp(0.0, 1.0),
          color: stateColor(b.state),
          paceTick: (b.pacePercent / 100).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 6),
        // Spent against the limit, then what is left — or by how much it is
        // over, in the error colour on the amount only.
        Row(
          children: [
            Expanded(
              child: Text(
                l.financeBudgetSpentOf(money(b.spentCents), money(b.limitCents)),
                style: text.bodySmall!.copyWith(
                  color: c.inkMid,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                over
                    ? l.financeOverBy(money(b.overByCents))
                    : l.financeRemaining(money(b.remainingCents)),
                textAlign: TextAlign.end,
                style: text.bodySmall!.copyWith(
                  color: over ? c.error : c.inkMid,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ],
        ),
        if (!over && b.projectedCents > b.limitCents)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                l.financeMonthEndEstimate(money(b.projectedCents)),
                style: text.bodySmall!.copyWith(
                  color: c.warning,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ),
      ],
    );
    // One node for screen readers; a tap changes the limit or removes the
    // budget.
    return MergeSemantics(
      child: InkWell(
        onTap: b.id == 0 ? null : () => showBudgetSheet(context, existing: b),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: content,
        ),
      ),
    );
  }

  // --- subscriptions ---------------------------------------------------------

  Widget _subscriptionsCard(
    BuildContext context,
    FinanceDashboard dash,
    Set<DeletedRecord> hidden,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    final subs = withoutDeleted(
      dash.upcomingSubscriptions.take(5),
      hidden,
      DataScope.subscriptions,
      (s) => s.id,
    );
    String when(SubscriptionItem s) {
      final next = s.nextChargeOn;
      if (next == null) return l.subscriptionFrequency(s.frequency);
      // A date that has passed stays until the payment is recorded.
      if (dayDelta(next, now: today) < 0) return overdueSince(l, next, today);
      return l.relativeDays(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.financeUpcomingSubscriptions,
          trailing: IconButton(
            onPressed: () => openSubscriptionForm(context),
            tooltip: l.financeAddSubscription,
            icon: const Icon(Icons.add),
          ),
          onSeeAll: () => context.push('/finance/subscriptions'),
        ),
        if (subs.isEmpty)
          // Nothing due soon — which says nothing about whether there are
          // subscriptions at all ("Tümü →" lists them; "+" adds one).
          NokturnCard(
            child: Text(
              l.financeNoUpcomingPayments,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
          )
        else
          NokturnCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < subs.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 72, color: c.divider),
                  NokturnRow(
                    leading: LeadingCircle(
                      color: hexColor(subs[i].account.color, fallback: c.inkLow),
                      icon: Icons.autorenew,
                    ),
                    title: subs[i].name,
                    meta: when(subs[i]),
                    trailing: MoneyText(
                      subs[i].amountCents,
                      currency: subs[i].account.currency,
                      subunitToUnit: subs[i].account.subunitToUnit,
                      negative: true,
                    ),
                    onTap: () => showSubscriptionSheet(
                      context,
                      id: subs[i].id,
                      name: subs[i].name,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // --- recent ----------------------------------------------------------------

  Widget _recentCard(BuildContext context, List<Transaction> rows) {
    final c = context.nok;
    final l = context.l10n;
    final recent = rows.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.financeRecentTransactions,
          onSeeAll: () => context.push('/finance/transactions'),
        ),
        if (recent.isEmpty)
          NokturnCard(
            child: Text(l.financeNoTransactionsYet,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: c.inkLow)),
          )
        else
          NokturnCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 72, color: c.divider),
                  TxRow(
                    tx: recent[i],
                    onTap: () => showTransactionSheet(context, ref, recent[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FinanceSkeleton extends StatelessWidget {
  const _FinanceSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    Widget bone(double h, {double w = double.infinity, double r = 12}) =>
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: c.skeletonBone,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    final card = AccountCard.heightFor(context);
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        // Pull-to-refresh works here too.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          bone(120, r: 16),
          const SizedBox(height: 32),
          Row(children: [
            Expanded(flex: 8, child: bone(card, r: 16)),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: bone(card, r: 16)),
          ]),
          const SizedBox(height: 32),
          bone(180, r: 16),
          const SizedBox(height: 32),
          bone(260, r: 16),
          const SizedBox(height: 32),
          for (var i = 0; i < 6; i++) ...[
            bone(56, r: 12),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
