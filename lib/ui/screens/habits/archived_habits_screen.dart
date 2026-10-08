import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'habit_detail_sheet.dart';
import 'widgets/habit_visuals.dart';

/// The habits archived so far (`GET /habits?archived=true`), most recently
/// archived first: each one restores in a tap, and opens — its history, an
/// edit, a delete — like an active one.
class ArchivedHabitsScreen extends ConsumerStatefulWidget {
  const ArchivedHabitsScreen({super.key});

  @override
  ConsumerState<ArchivedHabitsScreen> createState() =>
      _ArchivedHabitsScreenState();
}

class _ArchivedHabitsScreenState extends ConsumerState<ArchivedHabitsScreen> {
  /// Habits whose restore is on its way.
  final _restoring = <int>{};

  Future<void> _refresh() async {
    ref.read(dataSyncProvider).refresh([archivedHabitsProvider]);
    await settleRefresh([ref.read(archivedHabitsProvider.future)]);
  }

  Future<void> _restore(Habit habit) async {
    setState(() => _restoring.add(habit.id));
    await restoreHabit(ref, context, habit);
    if (mounted) setState(() => _restoring.remove(habit.id));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(archivedHabitsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final habits = async.value == null
        ? null
        : withoutDeleted(
            async.value!.data,
            hidden,
            DataScope.habits,
            (h) => h.id,
          );

    final Widget body;
    if (async.isFirstLoad) {
      body = const _Skeleton();
    } else if (habits == null) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: l.errServerUnreachable,
        subtitle: l.errCheckWifi,
        actionLabel: l.actionRetry,
        onAction: _refresh,
      );
    } else {
      body = RefreshIndicator.adaptive(
        color: context.nok.gold,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (async.refreshFailed)
              SliverToBoxAdapter(
                child: OfflineBanner(
                  lastUpdated: async.value!.at,
                  onRetry: _refresh,
                ),
              ),
            if (habits.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.archive_outlined,
                  title: l.habitsArchivedEmpty,
                  subtitle: l.habitsArchivedEmptyBody,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                sliver: SliverList.separated(
                  itemCount: habits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _row(context, habits[i]),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.habitsArchivedTitle)),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }

  Widget _row(BuildContext context, Habit habit) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final restoring = _restoring.contains(habit.id);
    return NokturnCard(
      key: ValueKey('archived-habit-${habit.id}'),
      padding: EdgeInsets.zero,
      // The ripple shows on the card, not under it.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showHabitDetailSheet(context, habit),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: hexColor(habit.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        archivedOnLabel(l, habit),
                        style: text.bodySmall!.copyWith(color: c.inkMid),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: restoring ? null : () => _restore(habit),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(l.habitsUnarchive),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NokturnCard(
                child: Text('██████ ████', style: text.titleMedium),
              ),
            ),
        ],
      ),
    );
  }
}
