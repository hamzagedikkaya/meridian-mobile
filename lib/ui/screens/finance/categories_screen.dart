import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/turkish_case.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/finance_category.dart';
import '../../../models/finance_dashboard.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'category_sheet.dart';

/// How far a subcategory's row is indented, past its parent's circle
/// (design-analysis §7.9): its content starts 56 dp in from the card.
const _childIndent = 56.0 - Insets.rowH;

/// The Kategoriler page while it first loads (§4.26): a heading and a card
/// of rows — circle and name, a meta line under every other one — in bones.
class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row(bool meta) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.rowH, vertical: Insets.rowV),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const Bone.circle(size: LeadingCircle.size),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Bone.text(width: 112, lineHeight: 22),
                      if (meta) ...[
                        const SizedBox(height: Gap.xxs),
                        const Bone.text(width: 96),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, Gap.x5),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: Gap.sm, bottom: Gap.xs),
          child: SizedBox(
            height: Hit.min,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Bone.text(width: 72, lineHeight: 22),
            ),
          ),
        ),
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            children: [for (var i = 0; i < 5; i++) row(i.isEven)],
          ),
        ),
      ],
    );
  }
}

/// The Kategoriler page (design-analysis §7.9): the expense categories,
/// then the income ones, each under its heading — every top-level category
/// with its spend this month and how many subcategories it has, followed by
/// those subcategories, indented. A tap edits (or deletes) a category; the
/// button adds one ([initialKind] first). With no category at all, the
/// starter set is one tap away.
class CategoriesScreen extends ConsumerStatefulWidget {
  final String initialKind;

  const CategoriesScreen({super.key, this.initialKind = 'expense'});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _seeding = false;

  Future<void> _refresh() async {
    ref
        .read(dataSyncProvider)
        .refresh([categoriesProvider, financeDashboardProvider]);
    await settleRefresh([ref.read(categoriesProvider.future)]);
  }

  /// Adds the starter set in the app's language — both types — for a
  /// user with no categories at all. A name already taken (added on the
  /// web meanwhile) is skipped.
  Future<void> _seed() async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    setState(() => _seeding = true);
    var failed = false;
    var index = 0;
    for (final kind in categoryKinds) {
      for (final name in l.starterCategories(kind)) {
        try {
          await repo.createCategory(CategoryInput(
            name: name,
            kind: kind,
            color: rotatingSwatch(index++),
          ));
        } on ApiException catch (e) {
          final taken = e.details['name']?.any((d) => d.error == 'taken');
          if (taken != true) failed = true;
        } catch (_) {
          failed = true;
        }
      }
    }
    if (!mounted) return;
    setState(() => _seeding = false);
    if (failed) {
      showAppSnack(context, l.categoriesStarterFailed, isError: true);
    } else {
      Haptics.confirm();
      showAppSnack(context, l.categoriesStarterAdded, tone: SnackTone.success);
    }
  }

  void _add([String? kind]) =>
      showCategorySheet(context, kind: kind ?? widget.initialKind);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(categoriesProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final all = withoutDeleted(
      async.value?.data ?? const <TxCategory>[],
      hidden,
      DataScope.categories,
      (cat) => cat.id,
    );
    final empty = async.hasValue && !async.hasFailed && all.isEmpty;

    return CollapsingFabScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l.titleCategories)),
        floatingActionButton: CollapsingFab(
          icon: Icons.add_rounded,
          label: l.categoriesAddFab,
          // The empty state carries the same action.
          hidden: empty,
          onPressed: _add,
        ),
        body: Column(
          children: [
            if (async.refreshFailed)
              OfflineBanner(lastUpdated: async.value!.at, onRetry: _refresh),
            Expanded(
              child: SyncHint.over(
                active: async.isRefetching || _seeding,
                child: RefreshIndicator.adaptive(
                  color: c.gold,
                  // Armed (§5.8): the pull let go past its threshold.
                  onRefresh: () {
                    Haptics.armed();
                    return _refresh();
                  },
                  child: LoadPhaseSwitcher(
                    phase: async.isFirstLoad
                        ? LoadPhase.waiting
                        : async.hasFailed
                            ? LoadPhase.error
                            : LoadPhase.content,
                    skeleton: (_) => const _CategoriesSkeleton(),
                    content: (context) => _body(context, async, all),
                    error: (_) => _failed(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed() => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState.error(onRetry: _refresh),
          ),
        ],
      );

  Widget _body(
    BuildContext context,
    AsyncValue<Object?> async,
    List<TxCategory> all,
  ) {
    final l = context.l10n;
    if (async.hasFailed) return _failed();
    if (all.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.category_outlined,
              title: l.categoriesEmpty,
              subtitle: l.categoriesEmptyBody,
              // A brand-new user starts from a set; one of their own is the
              // second way.
              actionLabel: l.categoriesStarter,
              onAction: _seeding ? null : _seed,
              secondaryLabel: l.categoryNew,
              onSecondary: _seeding ? null : _add,
            ),
          ),
        ],
      );
    }
    // This month's spend per expense root, from the dashboard's slices
    // (a root's slice counts its subcategories too).
    final dashboard = ref.watch(financeDashboardProvider).value?.data;
    final childCounts = <int, int>{};
    for (final cat in all) {
      final parent = cat.parentId;
      if (parent != null) childCounts[parent] = (childCounts[parent] ?? 0) + 1;
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          Insets.gutter, 0, Insets.gutter, CollapsingFab.clearance(context)),
      children: [
        for (final kind in categoryKinds) ...[
          SectionHeader(
            kind == 'income' ? l.financeIncome : l.financeExpense,
            padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.xs),
          ),
          _group(context, all, kind, childCounts, dashboard),
        ],
      ],
    );
  }

  Widget _group(
    BuildContext context,
    List<TxCategory> all,
    String kind,
    Map<int, int> childCounts,
    FinanceDashboard? dashboard,
  ) {
    final c = context.nok;
    final l = context.l10n;
    final tree = categoryTree(all, kind: kind);
    if (tree.isEmpty) {
      return EmptyState.inline(
        icon: Icons.category_outlined,
        message: kind == 'income'
            ? l.categoriesEmptyIncome
            : l.categoriesEmptyExpense,
        actionLabel: l.categoryNew,
        onAction: () => _add(kind),
      );
    }
    String? spendOf(int id) {
      if (dashboard == null || kind != 'expense') return null;
      for (final slice in dashboard.pie) {
        if (slice.id == id && slice.amountCents > 0) {
          return l.categoryMonthSpend(formatMoney(
            slice.amountCents,
            dashboard.currency,
            dashboard.subunitToUnit,
            decimals: MoneyDecimals.auto,
          ));
        }
      }
      return null;
    }

    return NokturnCard(
      variant: NokCardVariant.list,
      child: Column(
        children: [
          for (var i = 0; i < tree.length; i++) ...[
            if (i > 0)
              NokturnRow.divider(
                indent: tree[i].child
                    ? _childIndent + NokturnRow.dividerIndent
                    : NokturnRow.dividerIndent,
              ),
            Padding(
              padding:
                  EdgeInsetsDirectional.only(start: tree[i].child ? _childIndent : 0),
              child: _row(
                context,
                tree[i].category,
                child: tree[i].child,
                meta: tree[i].child
                    ? null
                    : [
                        ?spendOf(tree[i].category.id),
                        if ((childCounts[tree[i].category.id] ?? 0) > 0)
                          l.categoryChildren(childCounts[tree[i].category.id]!),
                      ].join(' · '),
                c: c,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    TxCategory category, {
    required bool child,
    required String? meta,
    required NokturnColors c,
  }) {
    final name = category.name;
    return NokturnRow(
      leading: LeadingCircle.tone(
        entityTone(category.color, c),
        initial: name.isEmpty
            ? null
            : trUpper(String.fromCharCode(name.runes.first)),
        icon: name.isEmpty ? Icons.label_outline_rounded : null,
      ),
      title: name,
      meta: meta == null || meta.isEmpty ? null : meta,
      chevron: true,
      onTap: () => showCategorySheet(
        context,
        existing: category,
        kind: category.kind,
      ),
    );
  }
}
