import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/collapsing_fab.dart';
import '../../../ui/widgets/day_header.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/entrance.dart';
import '../../../ui/widgets/load_phase_switcher.dart';
import '../../../ui/widgets/nok_chip.dart';
import '../../../ui/widgets/nok_sheet.dart';
import '../../../ui/widgets/nokturn_card.dart';
import '../../../ui/widgets/offline_banner.dart';
import '../../../ui/widgets/picker_sheet.dart';
import '../../../ui/widgets/streak_flame.dart';
import '../../../ui/widgets/sync_hint.dart';
import '../shell/app_tabs.dart';
import 'journal_editor.dart';
import 'widgets/journal_card.dart';
import 'widgets/mood.dart';

const _rangeKeys = ['7d', '30d', '6mo', '1y', 'all'];

/// Ranges long enough to group their entries under month headings.
const _monthlyRanges = {'6mo', '1y', 'all'};

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The Journal tab (design-analysis §7.12): the range chip in the app bar,
/// "n kayıt · 6 haftadır yazıyorsun", today's card first — "Bugün
/// nasıldı?" with five moods, or today's entry under a gold "BUGÜN" — the
/// mood filter, a tag filter from any card's tag, the entries (by month
/// for six months and more) and the "Yaz" FAB.
///
/// The entrance plays once, with the first data; a new range or filter
/// changes the cards in place.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen>
    with TabRootScroll<JournalScreen> {
  @override
  AppTab get tab => AppTab.journal;

  String _range = '30d';

  /// The filters as the chips show them — at once, on a tap.
  String? _mood;
  String? _tag;

  /// The filters the list shows: they follow the chips once the old cards
  /// have faded out ([Motion.filterOut]).
  String? _listMood;
  String? _listTag;
  bool _listHidden = false;
  Timer? _filterTimer;

  /// The last range that had data. While a newly picked range loads, it
  /// stays on screen instead of a skeleton.
  JournalBundle? _lastShown;

  @override
  void dispose() {
    _filterTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    Haptics.armed();
    refreshTab(ref, AppTab.journal);
    await settleRefresh([ref.read(journalProvider(_range).future)]);
  }

  void _setRange(String range) {
    if (range == _range) return;
    _filterTimer?.cancel();
    setState(() {
      _range = range;
      _mood = _listMood = null;
      _tag = _listTag = null;
      _listHidden = false;
    });
  }

  Future<void> _pickRange() async {
    final l = context.l10n;
    final picked = await showPickerSheet<String>(
      context,
      title: l.journalRangeTitle,
      selected: _range,
      options: [
        for (final key in _rangeKeys)
          PickerOption(value: key, label: l.journalRangeLong(key)),
      ],
    );
    if (picked != null && mounted) _setRange(picked);
  }

  /// The chips change now; the list fades out in 90 ms, swaps its cards,
  /// and fades back in over 160 ms (§5.4) — no entrance replays.
  void _setFilters({required String? mood, required String? tag}) {
    _filterTimer?.cancel();
    if (Motion.reduced(context)) {
      setState(() {
        _mood = _listMood = mood;
        _tag = _listTag = tag;
        _listHidden = false;
      });
      return;
    }
    setState(() {
      _mood = mood;
      _tag = tag;
      _listHidden = true;
    });
    _filterTimer = Timer(Motion.filterOut, () {
      if (!mounted) return;
      setState(() {
        _listMood = _mood;
        _listTag = _tag;
        _listHidden = false;
      });
    });
  }

  void _toggleMood(String mood) =>
      _setFilters(mood: _mood == mood ? null : mood, tag: _tag);

  void _filterTag(String tag) => _setFilters(mood: _mood, tag: tag);

  void _clearFilters() => _setFilters(mood: null, tag: null);

  void _open(JournalEntry entry) => context.push('/journal/${entry.id}');

  void _delete(JournalEntry entry) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    deleteWithUndo(
      context,
      ref.read(deferredDeletesProvider.notifier),
      record: (scope: DataScope.journal, id: entry.id),
      message: l.journalDeleted,
      send: () => repo.deleteJournalEntry(entry.id),
      failedMessage: l.journalDeleteFailed,
    );
  }

  /// A card's long press (IA-20): Düzenle · Sil.
  Future<void> _actions(JournalEntry entry) async {
    final l = context.l10n;
    final action = await showNokSheet<String>(
      context,
      title: formatDate(entry.date, withYear: true),
      builder: (sheet) {
        final c = sheet.nok;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.actionEdit),
                onTap: () => Navigator.of(sheet).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: c.error),
                title: Text(l.actionDelete, style: TextStyle(color: c.error)),
                onTap: () => Navigator.of(sheet).pop('delete'),
              ),
              const SizedBox(height: Gap.lg),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    await _runAction(entry, action);
  }

  Future<void> _runAction(JournalEntry entry, String action) async {
    switch (action) {
      case 'edit':
        await openJournalEditor(context, entry: entry);
      case 'delete':
        _delete(entry);
    }
  }

  /// [_actions]' choices as screen-reader actions (§6.4: every long-press
  /// action is a custom semantics action too), running the same handlers.
  Map<CustomSemanticsAction, VoidCallback> _semanticActions(
    JournalEntry entry,
  ) {
    final l = context.l10n;
    return {
      CustomSemanticsAction(label: l.actionEdit): () =>
          _runAction(entry, 'edit'),
      CustomSemanticsAction(label: l.actionDelete): () =>
          _runAction(entry, 'delete'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(journalProvider(_range));
    final fetched = async.value;
    final bundle = fetched?.data;
    if (bundle != null) _lastShown = bundle;
    // A newly picked range is loading: keep the previous one up.
    final previous = async.isFirstLoad ? _lastShown : null;
    final shown = _withoutDeleted(bundle ?? previous);
    final phase = async.hasFailed
        ? LoadPhase.error
        : shown == null
        ? LoadPhase.waiting
        : LoadPhase.content;

    return primaryScroll(
      CollapsingFabScope(
        child: Scaffold(
          appBar: AppBar(
            // Whole at 200 % text: scaled down beside the range chip,
            // never cut.
            title: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l.titleJournal,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: Gap.sm),
                child: TextButton.icon(
                  onPressed: _pickRange,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  // Large text: the short form ("30g") leaves the title room.
                  label: Text(
                    MediaQuery.textScalerOf(context).scale(10) > 13
                        ? l.journalRange(_range)
                        : l.journalRangeLong(_range),
                    semanticsLabel: l.journalRangeLong(_range),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: CollapsingFab(
            icon: Icons.edit_outlined,
            label: l.journalFabWrite,
            onPressed: () => openJournalEditor(context),
          ),
          body: EntranceHost(
            child: SyncHint.over(
              active: async.isRefetching || previous != null,
              child: LoadPhaseSwitcher(
                phase: phase,
                skeleton: _skeleton,
                error: (context) => _scroll(context, [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState.error(onRetry: _refresh),
                  ),
                ]),
                content: (context) => _StaleDim(
                  stale: previous != null,
                  child: _scroll(context, [
                    if (async.refreshFailed)
                      SliverToBoxAdapter(
                        child: OfflineBanner(
                          lastUpdated: fetched!.at,
                          onRetry: _refresh,
                        ),
                      ),
                    ..._contentSlivers(context, shown!),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scroll(BuildContext context, List<Widget> slivers) {
    return RefreshIndicator.adaptive(
      color: context.nok.gold,
      onRefresh: _refresh,
      child: CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ...slivers,
          SliverToBoxAdapter(
            child: SizedBox(height: CollapsingFab.clearance(context)),
          ),
        ],
      ),
    );
  }

  /// [bundle] without the entries being deleted — they leave the list, its
  /// count and the mood strip at once — or null.
  JournalBundle? _withoutDeleted(JournalBundle? bundle) {
    final hidden = ref.watch(deferredDeletesProvider);
    if (bundle == null || hidden.isEmpty) return bundle;
    final kept = withoutDeleted(
      bundle.entries,
      hidden,
      DataScope.journal,
      (e) => e.id,
    );
    if (kept.length == bundle.entries.length) return bundle;
    final moods = {...bundle.moodCounts};
    for (final gone in bundle.entries) {
      if (kept.contains(gone)) continue;
      final mood = gone.mood;
      if (mood != null && (moods[mood] ?? 0) > 0) {
        moods[mood] = moods[mood]! - 1;
      }
    }
    return JournalBundle(
      entries: kept,
      entriesCount: bundle.entriesCount - (bundle.entries.length - kept.length),
      journalStreak: bundle.journalStreak,
      journalStreakWeeks: bundle.journalStreakWeeks,
      moodCounts: moods,
      range: bundle.range,
    );
  }

  List<Widget> _contentSlivers(BuildContext context, JournalBundle bundle) {
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    final filtered = _listMood != null || _listTag != null;
    final todays = bundle.entries
        .where((e) => _sameDay(e.date, today))
        .toList();
    final entries = bundle.entries
        .where((e) => _listMood == null || e.mood == _listMood)
        .where((e) => _listTag == null || e.tags.contains(_listTag))
        // Unfiltered, today's entries lead the page in the today slot.
        .where((e) => filtered || !_sameDay(e.date, today))
        .toList();
    final empty = bundle.entriesCount == 0 && bundle.entries.isEmpty;

    // One stagger through the page: the today slot first, then the cards.
    Widget card(JournalEntry entry, int index) => Entrance.staggered(
      key: ValueKey('entry-${entry.id}'),
      play: true,
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          0,
          Insets.gutter,
          Gap.md,
        ),
        child: JournalCard(
          entry: entry,
          isToday: _sameDay(entry.date, today),
          onTap: () => _open(entry),
          onLongPress: () => _actions(entry),
          onTag: _filterTag,
          semanticActions: _semanticActions(entry),
        ),
      ),
    );

    final todaySlot = <Widget>[
      if (!filtered && todays.isEmpty)
        Entrance.staggered(
          key: const ValueKey('today-prompt'),
          play: true,
          index: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              0,
              Insets.gutter,
              Gap.md,
            ),
            child: _TodayPrompt(
              onMood: (mood) => openJournalEditor(context, initialMood: mood),
            ),
          ),
        )
      else if (!filtered)
        for (final (i, entry) in todays.indexed) card(entry, i),
    ];

    return [
      SliverToBoxAdapter(child: _metaLine(context, bundle)),
      SliverList.list(children: todaySlot),
      if (!empty)
        SliverToBoxAdapter(
          child: _MoodDistribution(
            counts: bundle.moodCounts,
            active: _mood,
            onTap: _toggleMood,
          ),
        ),
      if (_tag != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              0,
              Insets.gutter,
              Gap.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: NokChip(
                label: l.journalTagFilter(_tag!),
                selected: true,
                icon: Icons.close_rounded,
                onTap: () => _setFilters(mood: _mood, tag: null),
              ),
            ),
          ),
        ),
      if (empty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _range == 'all'
              ? EmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: l.journalEmptyRange,
                  subtitle: l.journalWriteFirst,
                )
              : EmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: l.journalEmptyRange,
                  actionLabel: l.journalAllEntries,
                  onAction: () => _setRange('all'),
                ),
        )
      else
        SliverAnimatedOpacity(
          opacity: _listHidden ? 0 : 1,
          duration: _listHidden ? Motion.filterOut : Motion.filterIn,
          curve: _listHidden ? Curves.easeIn : Curves.easeOut,
          sliver: SliverPadding(
            padding: const EdgeInsets.only(top: Gap.sm),
            sliver: entries.isEmpty
                ? SliverToBoxAdapter(child: _noMatch(context, filtered))
                : _entryList(
                    context,
                    entries,
                    (entry, i) => card(entry, todaySlot.length + i),
                  ),
          ),
        ),
    ];
  }

  Widget _noMatch(BuildContext context, bool filtered) {
    if (!filtered) return const SizedBox.shrink();
    final c = context.nok;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.xxl,
        Insets.gutter,
        Gap.xxl,
      ),
      child: Column(
        children: [
          Text(
            l.journalNoEntryForFilter,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.sm),
          TextButton(
            onPressed: _clearFilters,
            child: Text(l.journalClearFilters),
          ),
        ],
      ),
    );
  }

  /// The cards — under pinned month headings for six months and more.
  Widget _entryList(
    BuildContext context,
    List<JournalEntry> entries,
    Widget Function(JournalEntry entry, int index) card,
  ) {
    SliverList list(List<JournalEntry> items, int offset) => SliverList.builder(
      itemCount: items.length,
      // A new entry at the top must not remount every card below it.
      findChildIndexCallback: (key) {
        final i = items.indexWhere((e) => ValueKey('entry-${e.id}') == key);
        return i < 0 ? null : i;
      },
      itemBuilder: (context, i) => card(items[i], offset + i),
    );
    if (!_monthlyRanges.contains(_range)) return list(entries, 0);
    final months = <(int, int), List<JournalEntry>>{};
    for (final e in entries) {
      months.putIfAbsent((e.date.year, e.date.month), () => []).add(e);
    }
    var offset = 0;
    final groups = <Widget>[];
    for (final MapEntry(key: (year, month), value: items) in months.entries) {
      groups.add(
        DayHeader.group(
          key: ValueKey('month-$year-$month'),
          header: DayHeader(label: formatMonthYear(DateTime(year, month))),
          slivers: [list(items, offset)],
        ),
      );
      offset += items.length;
    }
    return SliverMainAxisGroup(slivers: groups);
  }

  /// "12 kayıt · 6 haftadır yazıyorsun" — the streak only while there is
  /// one; the day streak ([StreakFlame]) from a server without the week
  /// count (WP-15). Never a flame by a zero.
  Widget _metaLine(BuildContext context, JournalBundle bundle) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final meta = text.bodySmall!.copyWith(color: c.inkMid);
    final weeks = bundle.journalStreakWeeks;
    final days = bundle.journalStreak;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.xs,
        Insets.gutter,
        Gap.lg,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.journalEntriesCount(bundle.entriesCount), style: meta),
          if (weeks != null && weeks > 0) ...[
            Text('  ·  ', style: meta),
            // The week streak in words, led by the app's one flame.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    size: 14,
                    color: c.goldBright,
                  ),
                ),
                const SizedBox(width: Gap.xxs),
                Text(l.journalStreakWeeks(weeks), style: meta),
              ],
            ),
          ] else if (weeks == null && days > 0) ...[
            Text('  ·  ', style: meta),
            StreakFlame(days: days, color: c.inkMid),
          ],
        ],
      ),
    );
  }

  Widget _skeleton(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.x3,
        Insets.gutter,
        0,
      ),
      children: [
        for (var i = 0; i < 3; i++) ...const [
          JournalCardSkeleton(),
          SizedBox(height: Gap.md),
        ],
      ],
    );
  }
}

/// "Bugün nasıldı?" and the five moods — a tap opens the editor with that
/// mood. No "Yaz" here: the FAB is the one write button (D31).
class _TodayPrompt extends StatelessWidget {
  final ValueChanged<String> onMood;
  const _TodayPrompt({required this.onMood});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.nok;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.journalTodayOverline,
            style: text.labelMedium!.copyWith(color: c.gold),
          ),
          const SizedBox(height: Gap.xs),
          Semantics(
            header: true,
            child: Text(
              context.l10n.journalHowWasToday,
              style: text.headlineSmall,
            ),
          ),
          const SizedBox(height: Gap.md),
          MoodStrip(onSelected: onMood),
        ],
      ),
    );
  }
}

/// The mood filter: one chip per mood with its count in the range.
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
    // Spread across the width when the five fit (spaceBetween spaces them);
    // scroll sideways, a Gap.xs apart, when they do not (large text).
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth - 2 * Insets.gutter;
        var natural = 0.0;
        for (final mood in journalMoodOrder) {
          natural += MoodFilterChip.widthFor(context, counts[mood] ?? 0);
        }
        final gap = natural <= slot ? 0.0 : Gap.xs;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: slot),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (i, mood) in journalMoodOrder.indexed)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                    child: MoodFilterChip(
                      mood: mood,
                      count: counts[mood] ?? 0,
                      selected: active == mood,
                      muted: active != null && active != mood,
                      onTap: () => onTap(mood),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A range still loading under the last one: the old cards stay at full
/// strength and ignore taps; only past [Motion.spinnerDelay] do they dim,
/// over 150 ms — a quick switch never flickers (§4.27).
class _StaleDim extends StatefulWidget {
  final bool stale;
  final Widget child;
  const _StaleDim({required this.stale, required this.child});

  @override
  State<_StaleDim> createState() => _StaleDimState();
}

class _StaleDimState extends State<_StaleDim> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    if (widget.stale) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(Motion.spinnerDelay, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  @override
  void didUpdateWidget(_StaleDim old) {
    super.didUpdateWidget(old);
    if (widget.stale && !old.stale) _arm();
    if (!widget.stale && old.stale) {
      _timer?.cancel();
      _dim = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.stale,
      child: AnimatedOpacity(
        opacity: _dim ? 0.5 : 1,
        duration: Motion.orInstant(context, Motion.pressOut),
        child: widget.child,
      ),
    );
  }
}
