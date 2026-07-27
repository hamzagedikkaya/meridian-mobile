import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../models/account.dart';
import '../../../models/finance_dashboard.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/charts.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/skeletons.dart';
import 'account_card.dart';
import 'para_utils.dart';
import 'transaction_form_screen.dart';
import 'tx_row.dart';

class ParaScreen extends ConsumerStatefulWidget {
  const ParaScreen({super.key});

  @override
  ConsumerState<ParaScreen> createState() => _ParaScreenState();
}

class _ParaScreenState extends ConsumerState<ParaScreen> {
  String _scope = 'month';
  final _accountsCtrl = PageController(viewportFraction: 0.88);
  int _accountPage = 0;
  bool _entered = false;

  @override
  void dispose() {
    _accountsCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    Haptics.celebrate();
    ref.invalidate(financeDashboardProvider);
    ref.invalidate(accountsProvider);
    try {
      await Future.wait([
        ref.read(financeDashboardProvider.future),
        ref.read(accountsProvider.future),
      ]);
    } catch (_) {/* keep last-good */}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final dashAsync = ref.watch(financeDashboardProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final dash = dashAsync.value?.data;
    final accounts = accountsAsync.value?.data;

    final firstLoading = dash == null && dashAsync.isLoading;
    final nothingCached = dash == null &&
        accounts == null &&
        (dashAsync.hasError || accountsAsync.hasError);
    final offline = (dashAsync.hasError && dash != null) ||
        (accountsAsync.hasError && accounts != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Para'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SegmentedPill<String>(
              options: const [('month', 'Ay'), ('year', 'Yıl')],
              selected: _scope,
              onChanged: (v) => setState(() => _scope = v),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdd(context),
        child: const Icon(Icons.add, size: 28),
      ),
      body: Column(
        children: [
          if (offline)
            OfflineBanner(
              lastUpdated: dashAsync.value?.at ?? DateTime.now(),
              onRetry: _refresh,
            ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              onRefresh: _refresh,
              child: nothingCached
                  ? _errorState()
                  : firstLoading
                      ? const _ParaSkeleton()
                      : (dash == null)
                          ? const _ParaSkeleton()
                          : _content(context, dash, accounts ?? const []),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdd(BuildContext context) async {
    final saved = await openTransactionForm(context);
    if (saved == true && context.mounted) {
      showAppSnack(context, 'İşlem kaydedildi ✓');
    }
  }

  Widget _errorState() => ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off,
            title: 'Sunucuya ulaşılamıyor',
            subtitle: 'Aynı Wi-Fi ağında olduğundan emin ol',
            actionLabel: 'Tekrar dene',
            onAction: _refresh,
          ),
        ],
      );

  Widget _content(
    BuildContext context, FinanceDashboard dash, List<Account> accounts) {
    final active = accounts.where((a) => !a.archived).toList();
    final sections = <Widget>[
      _hero(context, dash),
      _accountsCarousel(context, active),
      _sixMonthCard(context, dash),
      _categoriesCard(context, dash),
      if (dash.budgets.isNotEmpty) _budgetsCard(context, dash),
      if (dash.upcomingSubscriptions.isNotEmpty) _subscriptionsCard(context, dash),
      _recentCard(context, dash),
    ];

    final stagger = !_entered;
    if (stagger) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _entered = true);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 32),
      itemBuilder: (context, i) {
        final child = sections[i];
        if (!stagger || i >= 6) return child;
        return child
            .animate()
            .fadeIn(duration: 300.ms, delay: (50 * i).ms)
            .slideY(begin: 0.06, duration: 300.ms, delay: (50 * i).ms);
      },
    );
  }

  // --- hero ------------------------------------------------------------------

  Widget _hero(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final totals = _scope == 'year' ? dash.year : dash.month;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _scope == 'year' ? 'BU YIL NET' : 'BU AY NET',
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
                Text('Gelir ',
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
                Text('Gider ',
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

  Widget _accountsCarousel(BuildContext context, List<Account> accounts) {
    final c = context.nok;
    if (accounts.isEmpty) {
      return NokturnCard(
        child: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'İlk hesabını ekle',
          subtitle: 'Hesap ekleme yakında',
        ),
      );
    }
    final pageCount = accounts.length + 1;
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _accountsCtrl,
            itemCount: pageCount,
            onPageChanged: (i) {
              Haptics.tick();
              setState(() => _accountPage = i);
            },
            itemBuilder: (context, i) {
              final child = i < accounts.length
                  ? AccountCard(
                      account: accounts[i],
                      onTap: () =>
                          context.push('/para/hesap/${accounts[i].id}'),
                    )
                  : AccountAddCard(
                      onTap: () => showAppSnack(
                          context, 'Hesap ekleme yakında'),
                    );
              // Off-center cards shrink slightly so the active page reads as
              // the focal card in the snap carousel.
              return AnimatedBuilder(
                animation: _accountsCtrl,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: child,
                ),
                builder: (context, inner) {
                  var page = _accountPage.toDouble();
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
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pageCount; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: i == _accountPage ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _accountPage ? c.gold : c.inkFaint,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // --- six month -------------------------------------------------------------

  Widget _sixMonthCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final s = dash.sixMonthSeries;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Son 6 ay', style: text.titleMedium),
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
              Text('Gelir', style: text.labelSmall!.copyWith(color: c.inkMid)),
              const SizedBox(width: 16),
              ChartLegendDot(c.chartExpense),
              const SizedBox(width: 6),
              Text('Gider', style: text.labelSmall!.copyWith(color: c.inkMid)),
            ],
          ),
        ],
      ),
    );
  }

  // --- categories donut ------------------------------------------------------

  Widget _categoriesCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final pie = dash.pie;
    if (pie.isEmpty) {
      return NokturnCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kategoriler (bu ay)', style: text.titleMedium),
            const SizedBox(height: 12),
            Text(
              'Bu ay harcama yok',
              style: text.bodyMedium!.copyWith(color: c.inkLow),
            ),
          ],
        ),
      );
    }

    final total = pie.fold<int>(0, (a, s) => a + s.amountCents);
    final sorted = [...pie]..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final legend = sorted.take(5).toList();

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kategoriler (bu ay)', style: text.titleMedium),
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
              onSliceTap: (i) => _showBreakdown(context, dash, pie[i]),
              centerTotalCents: total,
              centerCurrency: dash.currency,
              centerSubunitToUnit: dash.subunitToUnit,
              centerLabel: 'Gider',
            ),
          ),
          const SizedBox(height: 16),
          for (final s in legend)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ChartLegendDot(hexColor(s.color)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.name, style: text.bodyMedium)),
                  Text(
                    formatMoney(s.amountCents, dash.currency, dash.subunitToUnit),
                    style: text.bodyMedium!.copyWith(fontFeatures: tabularFigures),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    total == 0
                        ? '%0'
                        : '%${(s.amountCents / total * 100).round()}',
                    style: text.labelSmall!.copyWith(color: c.inkMid),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showBreakdown(
    BuildContext context, FinanceDashboard dash, PieSlice slice) {
    final text = Theme.of(context).textTheme;
    final rows = slice.breakdown.isEmpty
        ? [PieBreakdown(id: slice.id, name: slice.name, amountCents: slice.amountCents, isRoot: true)]
        : slice.breakdown;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(slice.name, style: text.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in rows)
                    NokturnRow(
                      leading: LeadingCircle(
                        color: hexColor(slice.color),
                        icon: Icons.circle,
                      ),
                      title: b.name,
                      trailing: MoneyText(
                        b.amountCents,
                        currency: dash.currency,
                        subunitToUnit: dash.subunitToUnit,
                        negative: true,
                      ),
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

  Widget _budgetsCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    Color stateColor(String s) => switch (s) {
          'over' => c.error,
          'warning' => c.warning,
          _ => c.income,
        };

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bütçeler', style: text.titleMedium),
          const SizedBox(height: 16),
          for (var i = 0; i < dash.budgets.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _budgetRow(context, dash, dash.budgets[i], stateColor),
          ],
        ],
      ),
    );
  }

  Widget _budgetRow(BuildContext context, FinanceDashboard dash,
      BudgetStatus b, Color Function(String) stateColor) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final over = b.state == 'over';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(b.categoryName, style: text.titleSmall)),
            if (over)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('aşıldı',
                    style: text.labelSmall!.copyWith(color: c.error)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        PacedProgressBar(
          value: (b.percentUsed / 100).clamp(0.0, 1.0),
          color: stateColor(b.state),
          paceTick: (b.pacePercent / 100).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 6),
        // Single meta line; scale down so long/negative balances never overflow.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                'kalan ',
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
              MoneyText(
                b.remainingCents,
                currency: dash.currency,
                subunitToUnit: dash.subunitToUnit,
                variant: MoneyVariant.meta,
                color: over ? c.error : c.inkMid,
              ),
            ],
          ),
        ),
        if (b.projectedCents > b.limitCents)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text('Ay sonu tahmini: ',
                      style: text.bodySmall!.copyWith(color: c.warning)),
                  MoneyText(
                    b.projectedCents,
                    currency: dash.currency,
                    subunitToUnit: dash.subunitToUnit,
                    variant: MoneyVariant.meta,
                    color: c.warning,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- subscriptions ---------------------------------------------------------

  Widget _subscriptionsCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final subs = dash.upcomingSubscriptions.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Yaklaşan abonelikler'),
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
                  meta: subs[i].nextChargeOn == null
                      ? frequencyLabel(subs[i].frequency)
                      : relativeDays(subs[i].nextChargeOn!),
                  trailing: MoneyText(
                    subs[i].amountCents,
                    currency: subs[i].account.currency,
                    subunitToUnit: subs[i].account.subunitToUnit,
                    negative: true,
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

  Widget _recentCard(BuildContext context, FinanceDashboard dash) {
    final c = context.nok;
    final recent = dash.recentTransactions.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Son işlemler',
          onSeeAll: () => context.push('/para/islemler'),
        ),
        if (recent.isEmpty)
          NokturnCard(
            child: Text('Henüz işlem yok',
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
                    onTap: () => context.push('/para/islemler'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ParaSkeleton extends StatelessWidget {
  const _ParaSkeleton();

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
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          bone(120, r: 16),
          const SizedBox(height: 32),
          Row(children: [
            Expanded(flex: 8, child: bone(140, r: 16)),
            const SizedBox(width: 12),
            Expanded(flex: 1, child: bone(140, r: 16)),
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
