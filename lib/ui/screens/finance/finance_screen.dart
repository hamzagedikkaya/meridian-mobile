import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/finance_dashboard.dart';
import '../../../models/subscription.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../flows/flows.dart' show markSubscriptionPaid, SubscriptionLite,
    subscriptionChargesInFlightProvider;
import '../../widgets/app_snackbar.dart';
import '../../widgets/category_bars.dart';
import '../../widgets/charts.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/hero_stat.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/pace_line.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'account_card.dart';
import 'account_detail_screen.dart';
import 'account_form.dart';
import 'budget_sheet.dart';
import 'finance_utils.dart';
import 'subscription_form.dart';
import 'subscriptions_screen.dart';
import 'transaction_form_screen.dart';
import 'tx_detail_sheet.dart';
import 'tx_row.dart';

/// The SharedPreferences key that remembers the setup card was hidden.
const financeSetupDismissedKey = 'finance.setup.dismissed';

/// The finance hero's sentence (design-analysis §4.24, contract §13.3),
/// deterministic, first match wins:
///
/// 1. With last month's day-by-day spending (and something spent in it),
///    from the 3rd of the month on: against the same day last month.
/// 2. Otherwise, when at least 3 of the 5 months before this one had
///    spending: where this month's pace ends against the 5-month average
///    (the months without spending count as zero).
/// 3. Otherwise: what was spent so far, and per day.
String financeInsight(AppL10n l, FinanceDashboard dash, DateTime today) {
  String money(int cents) => formatMoney(
        cents,
        dash.currency,
        dash.subunitToUnit,
        decimals: MoneyDecimals.auto,
      );
  final expense = dash.month.expenseCents;
  final spend = dash.spendCumulativeCents;
  final reference = dash.referenceCumulativeCents;
  if (spend != null &&
      spend.length >= 3 &&
      reference != null &&
      reference.isNotEmpty &&
      reference.last > 0) {
    final same = reference[math.min(spend.length, reference.length) - 1];
    final diff = spend.last - same;
    if (diff != 0) {
      return l.financeInsightVsLastMonth(money(diff.abs()), less: diff < 0);
    }
  }
  final days = today.day;
  final previous = dash.sixMonthSeries.expenseCents;
  final before = previous.length >= 6
      ? previous.sublist(previous.length - 6, previous.length - 1)
      : const <int>[];
  final spent = [for (final c in before) if (c != 0) c];
  if (spent.length >= 3 && expense > 0) {
    // "5 aylık ortalama": over all five months, as the sentence says.
    final average = before.fold<int>(0, (a, b) => a + b) / before.length;
    final monthDays = DateTime(today.year, today.month + 1, 0).day;
    final projected = (expense / days * monthDays).round();
    final percent = ((projected - average).abs() / average * 100).round();
    return l.financeInsightProjection(
      money(projected),
      percent,
      below: projected < average,
    );
  }
  if (expense == 0) return l.financeNoSpendThisMonth;
  final perDay = (expense / days).round();
  return l.financeInsightSpent(money(expense), money(perDay));
}

/// Whether [sentence] in [style] needs more than the hero's two lines at
/// [width] and the current text size — then `HeroStat` would cut it with
/// "…", so Finance shows it whole in the chart slot instead (§4.20, §8.3).
bool insightNeedsMoreLines(
  BuildContext context,
  String sentence,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: sentence, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 2,
  )..layout(maxWidth: width);
  final exceeds = painter.didExceedMaxLines;
  painter.dispose();
  return exceeds;
}

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

/// Finans (design-analysis §7.5): now first. The month's net is the hero;
/// then setting up (while it is not done), the accounts, what is due, the
/// budgets, the latest transactions, where the money went and the last six
/// months. The month/year switch is gone — the dashboard has no range.
class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with TabRootScroll<FinanceScreen> {
  @override
  AppTab get tab => AppTab.finance;

  /// The first-run button is opening the cash account.
  bool _openingCash = false;

  /// "Gizle" on the setup card, remembered on the device.
  bool _setupDismissed = false;

  @override
  void initState() {
    super.initState();
    try {
      _setupDismissed =
          ref.read(sharedPrefsProvider).getBool(financeSetupDismissedKey) ??
              false;
    } catch (_) {
      // No preferences (a test without them): the card shows.
    }
  }

  void _dismissSetup() {
    setState(() => _setupDismissed = true);
    try {
      ref.read(sharedPrefsProvider).setBool(financeSetupDismissedKey, true);
    } catch (_) {
      // No preferences: hidden for as long as the screen lives.
    }
  }

  /// Refetches the tab. [minimum] holds a pull's spinner long enough not
  /// to flash (§5.5); a retry button passes none.
  Future<void> _refresh({Duration minimum = Duration.zero}) async {
    refreshTab(ref, AppTab.finance);
    await settleRefresh([
      ref.read(financeDashboardProvider.future),
      ref.read(accountsProvider.future),
      ref.read(subscriptionsProvider.future),
    ], minimum: minimum);
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
    final offline = dashAsync.refreshFailed || accountsAsync.refreshFailed;
    final refetching = dashAsync.isRefetching || accountsAsync.isRefetching;
    final setup = dash == null || allAccounts == null || allAccounts.isEmpty
        ? null
        : _setupState(dash, hidden);

    final firstRun = allAccounts != null && allAccounts.isEmpty;
    final phase = dashFailed
        ? LoadPhase.error
        : dash == null
            ? LoadPhase.waiting
            : LoadPhase.content;

    return primaryScroll(EntranceHost(
      child: CollapsingFabScope(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              l.titleFinance,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            actions: [
              IconButton(
                onPressed: () =>
                    context.push('/finance/transactions?search=1'),
                tooltip: l.financeSearch,
                icon: const Icon(Icons.search_rounded),
              ),
              _menu(context),
            ],
          ),
          // With no account yet, the first-run card is the way in; while
          // the setup card offers the first transaction, it carries the
          // action (one control per action, §6.5).
          floatingActionButton: active == null || active.isEmpty || firstRun
              ? null
              : CollapsingFab(
                  icon: Icons.add_rounded,
                  label: l.financeAddTransactionFab,
                  onPressed: () => _openAdd(context),
                  hidden: setup != null && setup.visible && !setup.transaction,
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
                    // The pull's own tick; retry calls [_refresh] silently.
                    onRefresh: () {
                      Haptics.armed();
                      return _refresh(minimum: Motion.refreshMinimum);
                    },
                    child: LoadPhaseSwitcher(
                      phase: phase,
                      skeleton: (_) => const _FinanceSkeleton(),
                      error: (_) => _errorState(),
                      content: (context) => _content(
                        context,
                        dash!,
                        allAccounts,
                        hidden,
                        setup,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _menu(BuildContext context) {
    final l = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l.actionMoreOptions,
      onSelected: (value) {
        if (value == 'budget') {
          showBudgetSheet(context);
        } else {
          context.push(value);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '/finance/accounts',
          child: Text(l.financeAccounts),
        ),
        PopupMenuItem(
          value: '/finance/categories',
          child: Text(l.financeMenuCategories),
        ),
        PopupMenuItem(
          value: '/finance/subscriptions',
          child: Text(l.financeMenuSubscriptions),
        ),
        PopupMenuItem(value: 'budget', child: Text(l.financeMenuAddBudget)),
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

  /// The first-run shortcut: a cash account in the user's currency, in one
  /// tap. The setup card then moves on to the first transaction.
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
      Haptics.confirm();
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
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: EmptyState.error(onRetry: _refresh)),
        ),
      ],
    );
  }

  /// Where setting up stands: an account (always, once there is one), a
  /// first transaction, a budget and a subscription (both optional).
  _Setup _setupState(FinanceDashboard dash, Set<DeletedRecord> hidden) {
    final transaction = dash.recentTransactions.isNotEmpty;
    final budget = dash.budgets.isNotEmpty;
    var subscription = dash.upcomingSubscriptions.isNotEmpty;
    if (!subscription && !_setupDismissed) {
      // Nothing due within 30 days says nothing about having any.
      final bundle = ref.watch(subscriptionsProvider).value?.data;
      subscription = bundle != null && bundle.all.isNotEmpty;
    }
    final done = 1 +
        (transaction ? 1 : 0) +
        (budget ? 1 : 0) +
        (subscription ? 1 : 0);
    return _Setup(
      transaction: transaction,
      budget: budget,
      subscription: subscription,
      visible: !_setupDismissed && done < 4,
    );
  }

  Widget _content(
    BuildContext context,
    FinanceDashboard dash,
    List<Account>? accounts,
    Set<DeletedRecord> hidden,
    _Setup? setup,
  ) {
    final recent = withoutDeleted(
      dash.recentTransactions,
      hidden,
      DataScope.transactions,
      (tx) => tx.id,
    );
    final setupVisible = setup?.visible ?? false;
    final s = dash.sixMonthSeries;
    // Keyed by section, so a section that appears or goes (budgets, the
    // setup card) after a refresh does not shift the others' state.
    final List<(String, Widget)> sections;
    if (accounts != null && accounts.isEmpty) {
      // First run: no account at all. One calm card, one step.
      sections = [('first-run', _gutter(_firstRunCard(context)))];
    } else {
      sections = [
        ('hero', _gutter(_hero(context, dash, accounts))),
        if (setup != null && setupVisible)
          ('setup', _gutter(_setupCard(context, setup))),
        ('accounts', FinanceAccountsSection(userCurrency: dash.currency)),
        (
          'upcoming',
          _gutter(_UpcomingSection(dash: dash, ghost: !setupVisible)),
        ),
        if (dash.budgets.isNotEmpty || !setupVisible)
          ('budgets', _gutter(_budgetsSection(context, dash, hidden))),
        // Deviation from §7.5 ("bu ay işlem yok" hides sections 6–8): the
        // latest transactions stay even when they are last month's — on
        // the 1st an empty screen would hide what was just recorded.
        if (recent.isNotEmpty)
          ('recent', _gutter(_recentSection(context, recent))),
        if (dash.pie.isNotEmpty)
          ('categories', _gutter(_categoriesSection(context, dash))),
        if (SixMonthBars.hasEnoughData(s.incomeCents, s.expenseCents))
          ('six-month', _gutter(_sixMonthSection(context, dash))),
      ];
    }

    return ListView.separated(
      primary: true,
      padding: EdgeInsets.only(
        top: Gap.sm,
        bottom: CollapsingFab.clearance(context),
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sections.length,
      // Lets a section keep its element when one above appears or goes.
      findItemIndexCallback: (key) {
        final index = sections.indexWhere((s) => ValueKey(s.$1) == key);
        return index < 0 ? null : index;
      },
      separatorBuilder: (_, _) => const SizedBox(height: Gap.xxl),
      itemBuilder: (context, i) => Entrance.staggered(
        key: ValueKey(sections[i].$1),
        play: true,
        index: i,
        child: sections[i].$2,
      ),
    );
  }

  static Widget _gutter(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
        child: child,
      );

  // --- first run -------------------------------------------------------------

  Widget _firstRunCard(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      padding: const EdgeInsets.all(Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 40, color: c.gold),
          const SizedBox(height: Gap.lg),
          Text(l.financeFirstRunTitle, style: text.headlineMedium),
          const SizedBox(height: Gap.sm),
          Text(
            l.financeFirstRunBody,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.xxl),
          PrimaryButton(
            label: l.financeFirstRunCash,
            loading: _openingCash,
            onPressed: _openCashAccount,
          ),
          const SizedBox(height: Gap.sm),
          TextButton(
            onPressed: _openingCash ? null : _addAccount,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.financeFirstRunOther),
          ),
        ],
      ),
    );
  }

  // --- hero ------------------------------------------------------------------

  Widget _hero(
    BuildContext context,
    FinanceDashboard dash,
    List<Account>? accounts,
  ) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    final month = dash.month;
    final insight = financeInsight(l, dash, today);
    final spend = dash.spendCumulativeCents;
    final reference = dash.referenceCumulativeCents;
    // The pace line needs WP-15's series, and something to draw.
    final drawPace = spend != null &&
        spend.isNotEmpty &&
        (spend.last > 0 || (reference?.any((v) => v > 0) ?? false));
    final reference0 = reference == null ||
            reference.isEmpty ||
            reference.last == 0
        ? null
        : reference;
    // Accounts in another currency: the totals add them unconverted (an
    // older server) or leave them out (WP-15's `totals_by_currency`).
    final otherCurrency = accounts != null &&
        accounts.any((a) =>
            !a.archived &&
            a.currency.toUpperCase() != dash.currency.toUpperCase());
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final pace = drawPace
        ? PaceLine(
            spent: spend,
            reference: reference0,
            daysInMonth: DateTime(today.year, today.month + 1, 0).day,
            month: today,
            currency: dash.currency,
            subunitToUnit: dash.subunitToUnit,
            semanticsLabel: insight,
          )
        : null;
    Widget money(int cents, {bool income = false}) => MoneyText(
          cents,
          currency: dash.currency,
          subunitToUnit: dash.subunitToUnit,
          signed: income,
          negative: !income,
          decimals: MoneyDecimals.auto,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, box) {
          final insightStyle = text.bodyMedium!.copyWith(color: c.inkHi);
          final long = insightNeedsMoreLines(
            context,
            insight,
            insightStyle,
            box.maxWidth - 2 * Insets.card,
          );
          return HeroStat(
            overline: l.financeMonthNet,
            value: MoneyText(
              month.netCents,
              currency: dash.currency,
              subunitToUnit: dash.subunitToUnit,
              variant: MoneyVariant.hero,
              signed: true,
              positiveGreen: true,
            ),
            support: HeroStatSupport(
              parts: [
                (l.financeIncome, money(month.incomeCents, income: true)),
                (l.financeExpense, money(month.expenseCents)),
              ],
            ),
            footnote: l.financeYearNet(formatMoney(
              dash.year.netCents,
              dash.currency,
              dash.subunitToUnit,
              sign: MoneySign.always,
              decimals: MoneyDecimals.auto,
            )),
            // The hero keeps its sentence to two lines; where it needs more
            // (measured, at this width and text size) "…" would cut an amount
            // or a percentage, so the sentence goes with the chart slot
            // instead, whole.
            insight: long ? null : insight,
            chart: long || pace != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (long) Text(insight, style: insightStyle),
                      if (long && pace != null) const SizedBox(height: Gap.lg),
                      ?pace,
                    ],
                  )
                : null,
          );
        }),
        if (otherCurrency)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Builder(builder: (context) {
              final note = Text(
                dash.totalsByCurrency != null
                    ? l.financeCurrencyNoteExcluded
                    : l.financeCurrencyNoteMixed,
                style: text.bodySmall!.copyWith(color: c.inkMid),
              );
              final link = TextButton(
                onPressed: () => context.push('/finance/accounts'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.financeAccounts),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              );
              // Larger text: the link goes under the note.
              return large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [note, link],
                    )
                  : Row(children: [Expanded(child: note), link]);
            }),
          ),
      ],
    );
  }

  // --- setup -----------------------------------------------------------------

  Widget _setupCard(BuildContext context, _Setup setup) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    Widget step(
      String label, {
      required bool done,
      bool optional = false,
      VoidCallback? onTap,
    }) {
      return MergeSemantics(
        child: Semantics(
          checked: done,
          child: InkWell(
            onTap: done ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.rowH,
                  vertical: Gap.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 24,
                      color: done ? c.income : c.inkDisabled,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: text.titleSmall!.copyWith(
                              color: done ? c.inkMid : c.inkHi,
                            ),
                          ),
                          if (optional)
                            Text(
                              l.labelOptional,
                              style: text.bodySmall!.copyWith(color: c.inkMid),
                            ),
                        ],
                      ),
                    ),
                    if (!done)
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
        ),
      );
    }

    return NokturnCard(
      variant: NokCardVariant.list,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.rowH, 0, Gap.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.financeSetupTitle(setup.done, 4),
                      style: text.titleMedium,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _dismissSetup,
                  style: TextButton.styleFrom(foregroundColor: c.inkMid),
                  child: Text(l.actionHide),
                ),
              ],
            ),
          ),
          step(l.financeSetupAccount, done: true),
          step(
            l.financeFirstTxTitle,
            done: setup.transaction,
            onTap: () => _openAdd(context),
          ),
          step(
            l.financeSetupBudget,
            done: setup.budget,
            optional: true,
            onTap: () => showBudgetSheet(context),
          ),
          step(
            l.financeSetupSubscription,
            done: setup.subscription,
            optional: true,
            onTap: () => openSubscriptionForm(context),
          ),
        ],
      ),
    );
  }

  // --- budgets ---------------------------------------------------------------

  Widget _budgetsSection(
    BuildContext context,
    FinanceDashboard dash,
    Set<DeletedRecord> hidden,
  ) {
    final l = context.l10n;
    final budgets = withoutDeleted(
      dash.budgets,
      hidden,
      DataScope.budgets,
      (b) => b.id,
    );
    if (budgets.isEmpty) {
      return GhostCard(
        icon: Icons.donut_large_rounded,
        message: l.financeBudgetsEmpty,
        actionLabel: l.financeMenuAddBudget,
        onAction: () => showBudgetSheet(context),
        dismissKey: 'finance.budgets',
      );
    }
    final today = ref.watch(currentDayProvider);
    final daysLeft =
        DateTime(today.year, today.month + 1, 0).day - today.day + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l.financeBudgets,
          onAdd: () => showBudgetSheet(context),
          addTooltip: l.financeMenuAddBudget,
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            children: [
              for (var i = 0; i < budgets.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1),
                _BudgetRow(
                  budget: budgets[i],
                  dash: dash,
                  daysLeft: daysLeft,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- recent ----------------------------------------------------------------

  Widget _recentSection(BuildContext context, List<Transaction> rows) {
    final l = context.l10n;
    final recent = rows.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l.financeRecentTransactions,
          onSeeAll: () => context.push('/finance/transactions'),
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            children: [
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) NokturnRow.divider(),
                // The same row grammar as every transaction list (§6.4):
                // swipe ← Sil, long press Düzenle · Bugüne kopyala · Sil —
                // and the same as screen-reader actions. The dashboard
                // refetches after each write, so nothing is placed by hand.
                TxSwipeToDelete(
                  key: ValueKey('recent-tx-${recent[i].id}'),
                  tx: recent[i],
                  child: TxRow(
                    tx: recent[i],
                    onTap: () => showTransactionSheet(context, ref, recent[i]),
                    onLongPress: () =>
                        showTransactionActions(context, ref, recent[i]),
                    semanticActions:
                        txRowSemanticActions(context, ref, recent[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- categories ------------------------------------------------------------

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

  Widget _categoriesSection(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final pie = dash.pie;
    // Every expense of the month is in a slice — the uncategorized ones
    // too — so the slices add up to the month's spending.
    final ranked = [
      for (final s in pie)
        if (!s.uncategorized) s,
    ]..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final top = ranked.take(5).toList();
    final otherCents = ranked.skip(5).fold<int>(0, (a, s) => a + s.amountCents);
    final uncategorized = pie.where((s) => s.uncategorized).firstOrNull;
    final biggest = [...pie]
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final lead = biggest.first;
    final insight = l.financeCategoriesInsight(
      lead.uncategorized ? l.financeUncategorized : lead.name,
      formatMoney(
        lead.amountCents,
        dash.currency,
        dash.subunitToUnit,
        decimals: MoneyDecimals.auto,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l.financeCategoriesThisMonth),
        // The bars' rows bring their own 20 dp sides.
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.rowH,
                  Gap.md,
                  Insets.rowH,
                  Gap.xs,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    insight,
                    style: text.bodyMedium!.copyWith(color: c.inkMid),
                  ),
                ),
              ),
              CategoryBars(
                currency: dash.currency,
                subunitToUnit: dash.subunitToUnit,
                semanticsLabel: insight,
                onCategorize: () => _drillInto(uncategorized: true),
                items: [
                  for (final s in top)
                    CategoryBarItem(
                      name: s.name,
                      cents: s.amountCents,
                      color: entityTone(s.color, c).fill,
                      onTap: () => _showBreakdown(context, dash, s),
                    ),
                  if (otherCents > 0)
                    CategoryBarItem(
                      name: l.financeOtherCategories,
                      cents: otherCents,
                      kind: CategoryBarKind.other,
                    ),
                  if (uncategorized != null)
                    CategoryBarItem(
                      name: l.financeUncategorized,
                      cents: uncategorized.amountCents,
                      kind: CategoryBarKind.uncategorized,
                      onTap: () => _drillInto(uncategorized: true),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
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
    showNokSheet<void>(
      context,
      title: slice.name,
      builder: (sheet) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Gap.sm),
          children: [
            for (final row in rows)
              NokturnRow(
                leading: LeadingCircle(
                  color: hexColor(slice.color),
                  icon: Icons.category_outlined,
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
    );
  }

  // --- six months ------------------------------------------------------------

  Widget _sixMonthSection(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final s = dash.sixMonthSeries;
    final expenses = s.expenseCents;
    String? insight;
    if (expenses.isNotEmpty) {
      final average = expenses.fold<int>(0, (a, b) => a + b) / expenses.length;
      if (average > 0) {
        final current = expenses.last;
        final percent = ((current - average).abs() / average * 100).round();
        insight = l.financeSixMonthInsight(percent, below: current < average);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l.financeLast6Months),
        NokturnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (insight != null) ...[
                ExcludeSemantics(
                  child: Text(
                    insight,
                    style: text.bodyMedium!.copyWith(color: c.inkMid),
                  ),
                ),
                const SizedBox(height: Gap.lg),
              ],
              SixMonthBars(
                labels: s.labels.map(shortMonthLabel).toList(),
                incomeCents: s.incomeCents,
                expenseCents: s.expenseCents,
                currency: dash.currency,
                subunitToUnit: dash.subunitToUnit,
                semanticsLabel: insight,
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  ChartLegendDot(c.chartIncome, hollow: true),
                  const SizedBox(width: 6),
                  Text(l.financeIncome,
                      style: text.labelSmall!.copyWith(color: c.inkMid)),
                  const SizedBox(width: Gap.lg),
                  ChartLegendDot(c.chartExpense),
                  const SizedBox(width: 6),
                  Text(l.financeExpense,
                      style: text.labelSmall!.copyWith(color: c.inkMid)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where setting up stands (see `_setupState`).
class _Setup {
  final bool transaction;
  final bool budget;
  final bool subscription;
  final bool visible;

  const _Setup({
    required this.transaction,
    required this.budget,
    required this.subscription,
    required this.visible,
  });

  /// Steps done, the account included.
  int get done =>
      1 + (transaction ? 1 : 0) + (budget ? 1 : 0) + (subscription ? 1 : 0);
}

// --- accounts ------------------------------------------------------------------

/// Finance's accounts (design-analysis §7.5 #3, §7.6): "Hesaplar" with the
/// balances per currency under it (never added across currencies), "Tümü"
/// to the Hesaplar page, and a horizontal strip of [AccountTile]s that runs
/// to the screen's edge — two whole tiles and a hint of the third at
/// 360 dp — ending in the dashed "+ Hesap" tile.
///
/// Its own widget: the strip scrolling rebuilds nothing else.
class FinanceAccountsSection extends ConsumerWidget {
  /// The user's currency: its total comes first.
  final String userCurrency;

  const FinanceAccountsSection({super.key, required this.userCurrency});

  void _actions(BuildContext context, WidgetRef ref, Account account) {
    final l = context.l10n;
    showNokSheet<void>(
      context,
      title: account.name,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NokturnRow(
              leading: Icon(Icons.edit_outlined, color: context.nok.inkMid),
              title: l.actionEdit,
              onTap: () {
                Navigator.of(sheet).pop();
                openAccountForm(context, existing: account);
              },
            ),
            NokturnRow(
              leading: Icon(Icons.archive_outlined, color: context.nok.inkMid),
              title: l.actionArchive,
              onTap: () {
                Navigator.of(sheet).pop();
                archiveAccount(context, ref, account);
              },
            ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(accountsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final all = async.value?.data == null
        ? null
        : withoutDeleted(
            async.value!.data,
            hidden,
            DataScope.accounts,
            (a) => a.id,
          );
    final active = all?.where((a) => !a.archived).toList();
    final height = AccountTile.heightFor(context);

    Widget gutter(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: child,
        );

    Widget body;
    if (active == null) {
      // Not loaded (yet): never claim there are no accounts — a bone the
      // strip's size while loading, the reason when it failed.
      body = async.hasFailed
          ? gutter(NokturnCard(
              child: EmptyState.inline(
                icon: Icons.cloud_off_rounded,
                message: l.errServerUnreachable,
                actionLabel: l.actionRetry,
                onAction: () => refreshTab(ref, AppTab.finance),
              ),
            ))
          : gutter(NokSkeleton(
              enabled: true,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: c.skeletonBone,
                  borderRadius: Radii.lgAll,
                ),
              ),
            ));
    } else if (active.isEmpty) {
      // Every account is archived.
      body = gutter(NokturnCard(
        child: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: l.financeNoActiveAccounts,
          subtitle: l.financeNoActiveAccountsBody,
          actionLabel: l.accountNew,
          onAction: () => openAccountForm(context),
          secondaryLabel: l.financeMenuArchivedAccounts,
          onSecondary: () => context.push('/finance/accounts?archived=1'),
        ),
      ));
    } else {
      body = SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          itemCount: active.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
          itemBuilder: (context, i) {
            if (i == active.length) {
              return AccountAddTile(onTap: () => openAccountForm(context));
            }
            final account = active[i];
            return AccountTile(
              key: ValueKey('account-${account.id}'),
              account: account,
              onTap: () => context.push('/finance/account/${account.id}'),
              onLongPress: () => _actions(context, ref, account),
            );
          },
        ),
      );
    }

    final totals = active == null || active.isEmpty
        ? null
        : l.accountsTotal(formatCurrencySums(
            balancesByCurrency(active, first: userCurrency),
          ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        gutter(SectionHeader(
          l.financeAccounts,
          onSeeAll: () => context.push('/finance/accounts'),
          padding: EdgeInsets.zero,
        )),
        if (totals != null)
          gutter(Text(
            totals,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          )),
        const SizedBox(height: Gap.sm),
        body,
      ],
    );
  }
}

// --- upcoming payments -------------------------------------------------------------

/// What is due (design-analysis §7.5 #4): the payments due within 7 days or
/// overdue, each paid with "Ödendi" once its day has come. Nothing due:
/// one row to the subscriptions and what they cost a month — or, with none
/// at all, a dashed card to add them ([ghost]; the setup card carries that
/// step while it shows).
class _UpcomingSection extends ConsumerWidget {
  final FinanceDashboard dash;
  final bool ghost;

  const _UpcomingSection({required this.dash, required this.ghost});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final due = withoutDeleted(
      dash.upcomingSubscriptions.where((s) {
        final next = s.nextChargeOn;
        return next != null && dayDelta(next, now: today) <= 7;
      }),
      hidden,
      DataScope.subscriptions,
      (s) => s.id,
    );
    final header = SectionHeader(
      l.financeUpcomingSubscriptions,
      onSeeAll: () => context.push('/finance/subscriptions'),
    );
    if (due.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                for (var i = 0; i < due.length; i++) ...[
                  if (i > 0) NokturnRow.divider(),
                  _UpcomingRow(item: due[i], today: today),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final subsAsync = ref.watch(subscriptionsProvider);
    final bundle = subsAsync.value?.data;
    // Not known yet: nothing, rather than a claim either way.
    if (bundle == null) return const SizedBox.shrink();
    if (bundle.active.isEmpty) {
      if (!ghost || bundle.inactive.isNotEmpty) {
        return const SizedBox.shrink();
      }
      return GhostCard(
        icon: Icons.autorenew_rounded,
        message: l.financeSubscriptionsGhost,
        actionLabel: l.financeAddSubscription,
        onAction: () => openSubscriptionForm(context),
        dismissKey: 'finance.subscriptions',
      );
    }
    final monthly = <SubscriptionTotal>[...bundle.totals]..sort((a, b) {
        if (a.currency == dash.currency) return -1;
        if (b.currency == dash.currency) return 1;
        return a.currency.compareTo(b.currency);
      });
    final perMonth = [
      for (final t in monthly)
        if (t.monthlyCents != 0)
          formatMoney(
            t.monthlyCents,
            t.currency,
            t.subunitToUnit,
            decimals: MoneyDecimals.auto,
          ),
    ].join(' · ');
    return NokturnCard(
      variant: NokCardVariant.list,
      child: InkWell(
        onTap: () => context.push('/finance/subscriptions'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.rowH,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.autorenew_rounded, size: 20, color: c.inkMid),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    l.financeMenuSubscriptions,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (perMonth.isNotEmpty)
                  Flexible(
                    child: Text(
                      l.financeSubscriptionsMonthly(perMonth),
                      textAlign: TextAlign.end,
                      style: context.nokText.numMeta
                          .copyWith(color: c.inkMid),
                    ),
                  ),
                const SizedBox(width: Gap.xs),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.inkLow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A payment that is due: its account's colour behind `autorenew`, the
/// name, when ("3 gün sonra · Aylık", or "Gecikmiş · 1 Ekim" in error) and
/// the amount — with "Ödendi" under it once the day has come. "Ödendi" is
/// off from the first tap until the server answers: a payment is not safe
/// to send twice (D29).
class _UpcomingRow extends ConsumerWidget {
  final SubscriptionItem item;
  final DateTime today;

  const _UpcomingRow({required this.item, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final next = item.nextChargeOn!;
    final delta = dayDelta(next, now: today);
    final overdue = delta < 0;
    final meta = overdue
        ? overdueSince(l, next, today)
        : '${l.relativeDays(next)} · ${l.subscriptionFrequency(item.frequency)}';
    final paying = ref.watch(
      subscriptionChargesInFlightProvider.select((s) => s.contains(item.id)),
    );
    final amount = MoneyText(
      item.amountCents,
      currency: item.account.currency,
      subunitToUnit: item.account.subunitToUnit,
      negative: true,
    );
    final pay = delta <= 0
        ? OutlinedButton(
            onPressed: paying
                ? null
                : () => markSubscriptionPaid(
                      context,
                      ref,
                      SubscriptionLite.ofItem(item),
                    ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 36),
              tapTargetSize: MaterialTapTargetSize.padded,
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            ),
            child: Text(l.financePaid),
          )
        : null;
    return InkWell(
      onTap: () => showSubscriptionSheet(context, id: item.id, name: item.name),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.rowH,
            vertical: Insets.rowV,
          ),
          child: Row(
            children: [
              LeadingCircle(
                color: hexColor(item.account.color, fallback: c.inkLow),
                icon: Icons.autorenew_rounded,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    Text(
                      meta,
                      style: text.bodySmall!.copyWith(
                        color: overdue ? c.error : c.inkMid,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [amount, ?pay],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- budget row ------------------------------------------------------------------

/// A budget (design-analysis §7.5 #5): its name and spend against the
/// limit, the bar with the month's pace tick, and what is left per day. Over
/// the limit: by how much (the amount alone in error) and "Limiti düzenle".
/// Heading past it at this pace: the month-end estimate in warning.
class _BudgetRow extends StatelessWidget {
  final BudgetStatus budget;
  final FinanceDashboard dash;
  final int daysLeft;

  const _BudgetRow({
    required this.budget,
    required this.dash,
    required this.daysLeft,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final b = budget;
    final over = b.state == 'over' || b.overByCents > 0;
    String money(int cents) => formatMoney(
          cents,
          dash.currency,
          dash.subunitToUnit,
          decimals: MoneyDecimals.auto,
        );
    final meta = text.bodySmall!.copyWith(
      color: c.inkMid,
      fontFeatures: tabularFigures,
    );
    // What may still go out each day, in whole units.
    final unit = dash.subunitToUnit;
    final perDay = b.remainingCents <= 0
        ? 0
        : (b.remainingCents / math.max(daysLeft, 1) / unit).floor() * unit;
    VoidCallback? edit() =>
        b.id == 0 ? null : () => showBudgetSheet(context, existing: b);
    return MergeSemantics(
      child: InkWell(
        onTap: edit(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.rowH,
            vertical: Gap.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text(b.categoryName, style: text.titleSmall)),
                  const SizedBox(width: Gap.sm),
                  // Money is never cut: it shrinks to the room there is.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        l.financeBudgetSpentOf(
                          money(b.spentCents),
                          money(b.limitCents),
                        ),
                        style: meta,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              PacedProgressBar(
                value: (b.barPercent / 100).clamp(0.0, 1.0),
                color: entityTone(b.color, c).fill,
                paceTick: (b.pacePercent / 100).clamp(0.0, 1.0),
                over: over,
              ),
              const SizedBox(height: Gap.sm),
              if (over)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Gap.sm,
                  children: [
                    Text(
                      l.financeOverBy(money(b.overByCents)),
                      style: meta.copyWith(color: c.error),
                    ),
                    if (b.id != 0)
                      TextButton(
                        onPressed: edit(),
                        child: Text(l.financeBudgetEditLimit),
                      ),
                  ],
                )
              else ...[
                Text(l.financeBudgetPerDay(money(perDay), daysLeft),
                    style: meta),
                if (b.projectedCents > b.limitCents)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.xxs),
                    child: Text(
                      l.financeMonthEndEstimate(money(b.projectedCents)),
                      style: meta.copyWith(color: c.warning),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
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
    final tile = AccountTile.heightFor(context);
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.sm,
          Insets.gutter,
          96,
        ),
        // Pull-to-refresh works here too.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          bone(260, r: 16),
          const SizedBox(height: Gap.xxl),
          bone(16, w: 120, r: 4),
          const SizedBox(height: Gap.md),
          Row(children: [
            bone(tile, w: AccountTile.width, r: 16),
            const SizedBox(width: Gap.sm),
            bone(tile, w: AccountTile.width, r: 16),
          ]),
          const SizedBox(height: Gap.xxl),
          bone(180, r: 16),
          const SizedBox(height: Gap.xxl),
          for (var i = 0; i < 5; i++) ...[
            bone(56, r: 12),
            const SizedBox(height: Gap.md),
          ],
        ],
      ),
    );
  }
}
