import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/search.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/search_result.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../flows/flows.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/day_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import '../events/event_sheet.dart';
import '../finance/subscriptions_screen.dart';
import '../finance/tx_detail_sheet.dart';
import '../habits/habit_detail_sheet.dart';

/// Global search (`/search?q=`, design-analysis §6.8, §7.14; WP-16).
///
/// The app bar is the field: it has the keyboard as the page opens, and
/// what is typed is searched once typing pauses for 250 ms and is at least
/// two characters long (`SearchNotifier`). Results come grouped by type —
/// İşlemler, Görevler, Etkinlikler, Günlük, Hedefler, Alışkanlıklar,
/// Abonelikler, at most five each — under day-header-style headings, each
/// row the server's own title and subtitle with the typed text picked out
/// in gold. The previous results stay until the next ones arrive, then
/// cross-fade to them.
///
/// A row opens its record's own surface: a transaction's, todo's, event's
/// or habit's sheet (read from its endpoint first), a subscription's
/// sheet, or the journal entry's and goal's pages. A record deleted since
/// the search drops out of the results. Whatever was opened, the query is
/// searched again when it closes: the server does not cache results.
///
/// Before anything is typed, the last five searches (tap: search it again;
/// long press or ×: forget it). Nothing found, a server that cannot be
/// reached, one that failed and one without search (from before WP-15)
/// each have their own state.
class SearchScreen extends ConsumerStatefulWidget {
  /// The query it was opened with.
  final String query;

  const SearchScreen({super.key, this.query = ''});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // The caret starts after the query it was opened with, so focusing the
  // field moves nothing and raises no selection handle.
  late final TextEditingController _field = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.query,
      selection: TextSelection.collapsed(offset: widget.query.length),
    ),
  );
  final _focus = FocusNode();

  /// A result is being opened (its record read, its surface up): a second
  /// tap waits.
  bool _opening = false;

  /// The last failure shown. A retry or new text clears the state's error
  /// before its answer comes, and the error view stays up until then
  /// (`LoadPhaseSwitcher`): it keeps saying what went wrong.
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    final query = widget.query.trim();
    if (query.isNotEmpty) {
      // Opened with `?q=`: searched at once. Providers change after the
      // first frame, not while it is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(searchProvider.notifier).searchNow(query);
      });
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  SearchNotifier get _search => ref.read(searchProvider.notifier);

  void _submit(String text) {
    _search.searchNow(text);
    unawaited(ref.read(recentSearchesProvider.notifier).add(text));
  }

  void _clear() {
    _field.clear();
    _search.type('');
    _focus.requestFocus();
  }

  void _useRecent(String query) {
    _field.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    _submit(query);
  }

  Future<void> _open(SearchResult result) async {
    if (_opening) return;
    _opening = true;
    final l = context.l10n;
    // Something was found and opened: the words are worth keeping.
    unawaited(ref
        .read(recentSearchesProvider.notifier)
        .add(ref.read(searchProvider).query));
    final repo = ref.read(repositoryProvider);
    try {
      switch (result.type) {
        case SearchResultType.transaction:
          final detail = await repo.fetchTransaction(result.id);
          if (!mounted) return;
          await showTransactionSheet(context, ref, detail.transaction);
        case SearchResultType.todo:
          final todo = await repo.fetchTodo(result.id);
          if (!mounted) return;
          await openTodoSheet(context, existing: todo);
        case SearchResultType.event:
          final event = await repo.fetchEvent(result.id);
          if (!mounted) return;
          await showEventSheet(context, event);
        case SearchResultType.habit:
          final habit = await repo.fetchHabit(result.id);
          if (!mounted) return;
          await showHabitDetailSheet(context, habit);
        case SearchResultType.subscription:
          await showSubscriptionSheet(context,
              id: result.id, name: result.title);
        case SearchResultType.journalEntry:
          await context.push('/journal/${result.id}');
        case SearchResultType.goal:
          await context.push('/goals/${result.id}');
      }
      // The server does not cache results (contract §13.1): what was
      // opened may have been changed.
      if (mounted) _search.refresh();
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.kind == ApiErrorKind.notFound) {
        // Deleted since the search (contract §13.1): drop the row.
        _search.drop(result);
        showAppSnack(context, l.searchResultGone);
      } else {
        showAppSnack(
          context,
          failureMessage(error, l, fallback: l.searchOpenFailed),
          isError: true,
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(searchProvider);
    final supported = ref.watch(searchSupportedProvider);

    final Widget body;
    if (!supported) {
      body = _Message(
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: l.searchUnavailableTitle,
          subtitle: l.searchUnavailableBody,
        ),
      );
    } else if (state.idle) {
      _lastError = null;
      body = _Recent(onUse: _useRecent);
    } else {
      final error = _lastError = state.error ?? _lastError;
      body = LoadPhaseSwitcher(
        phase: state.error != null
            ? LoadPhase.error
            : state.results != null
                ? LoadPhase.content
                : LoadPhase.waiting,
        skeleton: (_) => const _ResultsSkeleton(),
        content: (_) => _Results(
          results: state.results!,
          onOpen: _open,
        ),
        error: (_) => _Failure(
          error: error!,
          onRetry: _search.retry,
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        // Beside the back arrow when there is one; on the gutter otherwise.
        titleSpacing: Navigator.of(context).canPop() ? 0 : Insets.gutter,
        title: TextField(
          controller: _field,
          focusNode: _focus,
          autofocus: true,
          enabled: supported,
          textInputAction: TextInputAction.search,
          inputFormatters: [
            LengthLimitingTextInputFormatter(searchMaxLength),
          ],
          style: text.bodyLarge,
          cursorColor: c.gold,
          decoration: InputDecoration(
            hintText: l.searchHint,
            hintMaxLines: 1,
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
          ),
          onChanged: _search.type,
          onSubmitted: _submit,
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: _field,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: Gap.sm)
                : IconButton(
                    onPressed: _clear,
                    tooltip: l.searchClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          const SizedBox(width: Gap.xs),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: SyncHint(active: supported && state.searching),
        ),
      ),
      body: body,
    );
  }
}

// --- Before anything is typed --------------------------------------------------

/// The last searches (tap: search again; long press or ×: forget), or what
/// search covers when there are none yet.
class _Recent extends ConsumerWidget {
  final void Function(String query) onUse;

  const _Recent({required this.onUse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final recent = ref.watch(recentSearchesProvider);
    if (recent.isEmpty) {
      return _Message(
        child: EmptyState(
          icon: Icons.search_rounded,
          title: l.searchStartTitle,
          subtitle: l.searchStartBody,
        ),
      );
    }
    final forget = ref.read(recentSearchesProvider.notifier).remove;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: Gap.sm,
        bottom: Gap.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        DayHeader(label: l.searchRecent),
        const SizedBox(height: Gap.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                for (final (i, query) in recent.indexed) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: 56),
                  _RecentRow(
                    query: query,
                    onTap: () => onUse(query),
                    onRemove: () => forget(query),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.searchRecentRemove): onRemove,
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: onRemove,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Insets.rowH,
              end: Gap.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: c.inkMid),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                    child: Text(query, style: text.titleMedium),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: l.searchRecentRemove,
                  icon: Icon(Icons.close_rounded, size: 20, color: c.inkLow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Results -------------------------------------------------------------------

/// The scope of a result's record: a delete waiting out its "Geri al" hides
/// it here as on every other list.
DataScope _scopeOf(SearchResultType type) => switch (type) {
      SearchResultType.transaction => DataScope.transactions,
      SearchResultType.todo => DataScope.todos,
      SearchResultType.event => DataScope.events,
      SearchResultType.journalEntry => DataScope.journal,
      SearchResultType.goal => DataScope.goals,
      SearchResultType.habit => DataScope.habits,
      SearchResultType.subscription => DataScope.subscriptions,
    };

/// The leading glyph of each kind (§7.14).
IconData searchResultIcon(SearchResultType type) => switch (type) {
      SearchResultType.transaction => Icons.receipt_long_outlined,
      SearchResultType.todo => Icons.check_box_outlined,
      SearchResultType.event => Icons.event_outlined,
      SearchResultType.journalEntry => Icons.auto_stories_outlined,
      SearchResultType.goal => Icons.flag_outlined,
      SearchResultType.habit => Icons.repeat_rounded,
      SearchResultType.subscription => Icons.autorenew_rounded,
    };

class _Results extends ConsumerWidget {
  final SearchResults results;
  final void Function(SearchResult result) onOpen;

  const _Results({required this.results, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final hidden = ref.watch(deferredDeletesProvider);
    final groups = [
      for (final (type, rows) in results.groups)
        if (rows
                .where((r) =>
                    !hidden.contains((scope: _scopeOf(type), id: r.id)))
                .toList()
            case final shown when shown.isNotEmpty)
          (type, shown),
    ];
    final reduced = Motion.reduced(context);
    final Widget page;
    if (groups.isEmpty) {
      page = ListView(
        key: ValueKey('none:${results.query}'),
        padding: const EdgeInsets.fromLTRB(
            Insets.gutter, Gap.lg, Insets.gutter, Gap.xxl),
        children: [
          EmptyState.inline(
            icon: Icons.search_off_rounded,
            message: l.searchNoResults(results.query),
          ),
        ],
      );
    } else {
      page = CustomScrollView(
        key: ValueKey('found:${results.query}'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: Gap.sm)),
          for (final (type, rows) in groups)
            DayHeader.group(
              header: DayHeader(label: l.searchGroup(type.wire)),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.gutter, Gap.xs, Insets.gutter, Gap.lg),
                  sliver: SliverToBoxAdapter(
                    child: NokturnCard(
                      variant: NokCardVariant.list,
                      child: Column(
                        children: [
                          for (final (i, result) in rows.indexed) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                thickness: 1,
                                indent: Insets.rowH + 40 + Gap.md,
                              ),
                            SearchResultRow(
                              result: result,
                              query: results.query,
                              onTap: () => onOpen(result),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          SliverToBoxAdapter(
            child: SizedBox(
                height: Gap.lg + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      );
    }
    // A new answer cross-fades over the one it replaces (§7.14).
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.quick,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: page,
    );
  }
}

/// One result (§7.14): at least 56 dp, a 40 dp circle with the kind's
/// glyph, the server's title in titleMedium with the typed text in gold
/// w600 — found the way the server matches ([searchMatches]) — and its
/// subtitle in bodySmall inkMid. Screen readers hear the kind first.
class SearchResultRow extends StatelessWidget {
  final SearchResult result;

  /// What was searched: picked out in the title.
  final String query;
  final VoidCallback onTap;

  const SearchResultRow({
    super.key,
    required this.result,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = result.title;
    final base = text.titleMedium!.copyWith(color: c.inkHi);
    final hit = base.copyWith(color: c.gold, fontWeight: FontWeight.w600);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in searchMatches(title, query)) {
      if (start > at) spans.add(TextSpan(text: title.substring(at, start)));
      spans.add(TextSpan(text: title.substring(start, end), style: hit));
      at = end;
    }
    if (at < title.length) spans.add(TextSpan(text: title.substring(at)));

    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.rowH,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    searchResultIcon(result.type),
                    size: 20,
                    color: c.inkMid,
                    semanticLabel: l.searchKind(result.type.wire),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: spans),
                        style: base,
                        maxLines: large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.subtitle.isNotEmpty)
                        Text(
                          result.subtitle,
                          style: text.bodySmall!.copyWith(color: c.inkMid),
                          // Large text wraps it whole: an amount comes last
                          // and is never cut (§8.3).
                          maxLines: large ? null : 2,
                          overflow: large ? null : TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A group heading and three rows of bones, after the first search has
/// taken 400 ms (`LoadPhaseSwitcher`).
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            Insets.gutter, Gap.lg, Insets.gutter, Gap.lg),
        children: [
          const Bone.text(width: 96),
          const SizedBox(height: Gap.md),
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Insets.rowH,
                      vertical: Gap.sm,
                    ),
                    child: Row(
                      children: [
                        Bone.circle(size: 40),
                        SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Bone.text(width: 160, lineHeight: 22),
                              SizedBox(height: Gap.xs),
                              Bone.text(width: 200, lineHeight: 16),
                            ],
                          ),
                        ),
                      ],
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

// --- Failures --------------------------------------------------------------------

/// The search failed: the server could not be reached ("Tekrar dene",
/// "Sunucu ayarları"), or it answered with an error.
class _Failure extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _Failure({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final error = this.error;
    if (error is ApiException && error.isNetwork) {
      return _Message(
        child: EmptyState.error(
          onRetry: onRetry,
          onServerSettings: () => context.push('/profile/server'),
        ),
      );
    }
    // The server's reason when it gave one ("Sunucu hatası (500)" else).
    final reason = error is ApiException ? error.localized(l) : null;
    return _Message(
      child: EmptyState(
        icon: Icons.error_outline_rounded,
        title: l.searchFailed,
        subtitle: reason,
        actionLabel: l.actionRetry,
        onAction: onRetry,
      ),
    );
  }
}

/// A page-sized message, scrollable so it never overflows at large text
/// or above the keyboard.
class _Message extends StatelessWidget {
  final Widget child;

  const _Message({required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(alignment: const Alignment(0, -0.4), child: child),
          ),
        ),
      );
}
