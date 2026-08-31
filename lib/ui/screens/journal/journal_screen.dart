import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/nokturn_card.dart';
import '../../../ui/widgets/offline_banner.dart';
import '../../../ui/widgets/segmented_pill.dart';
import '../../../ui/widgets/skeletons.dart';
import '../../../l10n/app_l10n.dart';
import 'journal_editor.dart';
import 'widgets/journal_card.dart';
import 'widgets/mood.dart';

const _rangeKeys = ['7d', '30d', '6mo', '1y', 'all'];

List<(String, String)> _rangeOptionsFor(AppL10n l) =>
    [for (final key in _rangeKeys) (key, l.journalRange(key))];

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String _range = '30d';
  String? _moodFilter;
  bool _staggerDone = false;
  bool _staggerScheduled = false;

  Future<void> _refresh() async {
    Haptics.celebrate();
    ref.invalidate(journalProvider(_range));
    await ref.read(journalProvider(_range).future);
  }

  void _setRange(String range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _moodFilter = null;
      _staggerDone = false;
      _staggerScheduled = false;
    });
  }

  void _toggleMood(String mood) {
    Haptics.tick();
    setState(() => _moodFilter = _moodFilter == mood ? null : mood);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider(_range));
    final fetched = async.value;
    final bundle = fetched?.data;
    final firstLoading = async.isLoading && bundle == null;
    final showOffline = async.hasError && bundle != null;
    final showErrorState = async.hasError && bundle == null;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.titleJournal)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openJournalEditor(context),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator.adaptive(
        color: context.nok.gold,
        onRefresh: _refresh,
        child: showErrorState
            ? _errorView(context)
            : CustomScrollView(
                slivers: [
                  if (showOffline)
                    SliverToBoxAdapter(
                      child: OfflineBanner(
                        lastUpdated: fetched!.at,
                        onRetry: _refresh,
                      ),
                    ),
                  SliverToBoxAdapter(child: _header(context, bundle)),
                  if (firstLoading)
                    SliverToBoxAdapter(child: _skeleton(context))
                  else if (bundle == null || bundle.entriesCount == 0)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyView(context),
                    )
                  else
                    ..._entrySlivers(context, bundle),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
      ),
    );
  }

  Widget _header(BuildContext context, JournalBundle? bundle) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final count = bundle?.entriesCount ?? 0;
    final streak = bundle?.journalStreak ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedPill<String>(
              options: _rangeOptionsFor(context.l10n),
              selected: _range,
              onChanged: _setRange,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l.journalEntriesCount(count),
                  style: text.bodySmall!.copyWith(color: c.inkMid)),
              if (streak > 0) ...[
                const SizedBox(width: 8),
                _FlamePill(streak),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _entrySlivers(BuildContext context, JournalBundle bundle) {
    final entries = _moodFilter == null
        ? bundle.entries
        : bundle.entries.where((e) => e.mood == _moodFilter).toList();

    final stagger = !_staggerDone;
    if (stagger && !_staggerScheduled) {
      _staggerScheduled = true;
      // Retire the stagger only after the last card's entrance finishes
      // (5*50ms delay + 300ms), so rebuilds don't snap it mid-animation.
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted && !_staggerDone) setState(() => _staggerDone = true);
      });
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _MoodDistribution(
            counts: bundle.moodCounts,
            active: _moodFilter,
            onTap: _toggleMood,
          ),
        ),
      ),
      if (entries.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Text(
              context.l10n.journalNoEntryForMood,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: context.nok.inkLow),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            Widget item = Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: JournalCard(
                entry: entry,
                onTap: () => context.push('/journal/${entry.id}'),
              ),
            );
            if (stagger && index < 6) {
              item = item
                  .animate(delay: (50 * index).ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.06, duration: 300.ms);
            }
            return item;
          },
        ),
    ];
  }

  Widget _skeleton(BuildContext context) {
    final placeholder = JournalEntry(
      id: 0,
      date: DateTime.now(),
      // Skeleton bones are covered by shimmer, so the placeholder text only
      // needs the right shape, not the right language.
      title: '████████ ███████',
      bodyPlain: '████ ███████ ████ ██████ ███████ ████ ████████ ██ '
          '███ ████ ██████ ████ ██████ ████ ████ ███████ ██ █████ ██████.',
      mood: 'good',
      moodEmoji: '🙂',
      energyLevel: 3,
      tags: const ['█████', '████'],
      hasGratitude: true,
    );
    return NokSkeleton(
      enabled: true,
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: JournalCard(entry: placeholder, onTap: () {}),
            ),
        ],
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    final l = context.l10n;
    return EmptyState(
      icon: Icons.auto_stories_outlined,
      title: l.journalHowWasToday,
      subtitle: l.journalWriteFirst,
      actionLabel: l.journalCreateEntry,
      onAction: () => openJournalEditor(context),
    );
  }

  Widget _errorView(BuildContext context) {
    final l = context.l10n;
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: EmptyState(
            icon: Icons.cloud_off,
            title: l.errServerUnreachable,
            subtitle: l.errCheckWifi,
            actionLabel: l.actionRetry,
            onAction: _refresh,
          ),
        ),
      ],
    );
  }
}

class _FlamePill extends StatelessWidget {
  final int streak;
  const _FlamePill(this.streak);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '🔥 $streak',
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: c.onGoldContainer),
      ),
    );
  }
}

class _MoodDistribution extends StatelessWidget {
  final Map<String, int> counts;
  final String? active;
  final ValueChanged<String> onTap;

  const _MoodDistribution({
    required this.counts,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final mood in journalMoodOrder)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(mood),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MoodEmoji(
                    emoji: journalMoodEmojis[mood]!,
                    size: 26,
                    dimmed: active != null && active != mood,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${counts[mood] ?? 0}',
                    style: text.labelSmall!.copyWith(
                      color: active == mood ? c.gold : c.inkMid,
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
