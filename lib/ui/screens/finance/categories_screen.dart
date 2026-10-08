import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/finance_category.dart';
import '../../../models/transaction.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/sync_hint.dart';
import 'category_sheet.dart';
import 'finance_utils.dart';

/// The Kategoriler page: the expense and the income categories, each
/// top-level one followed by its subcategories. A tap edits (or deletes) a
/// category; the button adds one of the type on show.
class CategoriesScreen extends ConsumerStatefulWidget {
  final String initialKind;

  const CategoriesScreen({super.key, this.initialKind = 'expense'});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  late String _kind = widget.initialKind;
  bool _seeding = false;

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([categoriesProvider]);
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
      Haptics.success();
      showAppSnack(context, l.categoriesStarterAdded);
    }
  }

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

    return Scaffold(
      appBar: AppBar(title: Text(l.titleCategories)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showCategorySheet(context, kind: _kind),
        icon: const Icon(Icons.add),
        label: Text(l.categoriesAddFab),
      ),
      body: Column(
        children: [
          if (async.refreshFailed)
            OfflineBanner(lastUpdated: async.value!.at, onRetry: _refresh),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedPill<String>(
                options: [
                  ('expense', l.financeExpense),
                  ('income', l.financeIncome),
                ],
                selected: _kind,
                onChanged: (kind) => setState(() => _kind = kind),
              ),
            ),
          ),
          Expanded(
            child: SyncHint.over(
              active: async.isRefetching || _seeding,
              child: RefreshIndicator.adaptive(
                color: c.gold,
                onRefresh: _refresh,
                child: _body(context, async, all),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<Object?> async,
    List<TxCategory> all,
  ) {
    final c = context.nok;
    final l = context.l10n;
    if (async.isFirstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (async.hasFailed) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
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
    final tree = categoryTree(all, kind: _kind);
    if (tree.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.category_outlined,
            title: _kind == 'income'
                ? l.categoriesEmptyIncome
                : l.categoriesEmptyExpense,
            subtitle: l.categoriesEmptyBody,
            actionLabel: l.categoryNew,
            onAction: () => showCategorySheet(context, kind: _kind),
            // A brand-new user gets a set to start from.
            secondaryLabel: all.isEmpty && !_seeding ? l.categoriesStarter : null,
            onSecondary: all.isEmpty && !_seeding ? _seed : null,
          ),
        ],
      );
    }
    final childCounts = <int, int>{};
    for (final cat in all) {
      final parent = cat.parentId;
      if (parent != null) childCounts[parent] = (childCounts[parent] ?? 0) + 1;
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        NokturnCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < tree.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: tree[i].child ? 96 : 72,
                    color: c.divider,
                  ),
                Padding(
                  padding: EdgeInsets.only(left: tree[i].child ? 24 : 0),
                  child: NokturnRow(
                    leading: LeadingCircle(
                      color: hexColor(tree[i].category.color),
                      icon: tree[i].child
                          ? Icons.subdirectory_arrow_right
                          : Icons.label_outline,
                    ),
                    title: tree[i].category.name,
                    meta: tree[i].child
                        ? null
                        : switch (childCounts[tree[i].category.id] ?? 0) {
                            0 => null,
                            final n => l.categoryChildren(n),
                          },
                    trailing: Icon(Icons.chevron_right, color: c.inkLow),
                    onTap: () => showCategorySheet(
                      context,
                      existing: tree[i].category,
                      kind: tree[i].category.kind,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
