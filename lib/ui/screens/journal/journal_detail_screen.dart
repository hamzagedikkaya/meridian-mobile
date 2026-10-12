import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/formats.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_typography.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/offline_banner.dart';
import '../../../ui/widgets/skeletons.dart';
import '../../../ui/widgets/sync_hint.dart';
import 'journal_editor.dart';
import 'widgets/energy_bars.dart';
import 'widgets/journal_card.dart';
import 'widgets/mood.dart';

class JournalDetailScreen extends ConsumerStatefulWidget {
  final int entryId;
  const JournalDetailScreen({super.key, required this.entryId});

  @override
  ConsumerState<JournalDetailScreen> createState() =>
      _JournalDetailScreenState();
}

class _JournalDetailScreenState extends ConsumerState<JournalDetailScreen> {
  int get entryId => widget.entryId;

  /// The entry was found deleted (a 404) while this screen was open.
  bool _goneSeen = false;

  /// ...and the screen is on its way back.
  bool _goneHandled = false;

  /// The editor opened from here saved its text (as a new entry, once this
  /// one was gone): it said so, and going back needs no other word.
  bool _editorSaved = false;

  /// Leaves the screen and takes the entry off the journal at once, with
  /// "Geri al": the delete is sent only when the snackbar goes, so an undo
  /// just shows it again — body, mood, tags and all.
  void _delete() {
    final l = context.l10n;
    final host = Navigator.of(context, rootNavigator: true).context;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    Navigator.of(context).pop();
    deleteWithUndo(
      host,
      deletes,
      record: (scope: DataScope.journal, id: entryId),
      message: l.journalDeleted,
      send: () => repo.deleteJournalEntry(entryId),
      failedMessage: l.journalDeleteFailed,
    );
  }

  /// Goes back from an entry found deleted: this screen's own route only,
  /// when it is the one on top (the build runs again when it becomes so).
  void _leave(AppL10n l) {
    _goneHandled = true;
    final host = Navigator.of(context, rootNavigator: true).context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _goneHandled = false;
        return;
      }
      Navigator.of(context).maybePop();
      if (host.mounted && !_editorSaved) showAppSnack(host, l.journalGone);
    });
  }

  Future<void> _edit(JournalEntry entry) async {
    final saved = await openJournalEditor(context, entry: entry);
    if (saved == true) _editorSaved = true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(journalEntryProvider(entryId));
    // Deleted on the web or another device: say so and go back to a list
    // that no longer shows it — once this screen is on top. The editor
    // opened over it keeps its text (it offers it as a new entry); going
    // back from here must never close that instead.
    ref.listen(journalEntryProvider(entryId), (_, next) {
      if (next.isGone) _goneSeen = true;
    });
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_goneSeen && !_goneHandled && isCurrent) _leave(l);
    // Deleted on the web or another device: the copy still cached here can
    // be neither shown as current nor edited.
    final entry = async.isGone ? null : async.value?.data;

    final Widget body;
    if (async.isGone) {
      // A retry could only answer 404 again: say what happened instead of
      // blaming the connection.
      body = EmptyState(
        icon: Icons.delete_outline_rounded,
        title: l.journalGone,
        subtitle: l.errRecordGoneBody,
        actionLabel: l.actionBack,
        onAction: () => Navigator.of(context).maybePop(),
      );
    } else if (entry != null) {
      body = Column(
        children: [
          // A refresh failed: the entry shown may be out of date.
          if (async.refreshFailed)
            OfflineBanner(lastUpdated: async.value!.at, onRetry: _retry),
          Expanded(child: _DetailBody(entry: entry)),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l.journalLoadFailed,
        subtitle: l.errCheckWifi,
        actionLabel: l.actionRetry,
        onAction: _retry,
      );
    } else {
      body = _loading(context);
    }

    return Scaffold(
      appBar: AppBar(
        // The page is the entry: its date is the title (§6.4).
        title: Text(
          entry == null
              ? l.titleJournalEntry
              : '${formatDate(entry.date, withYear: true)}, '
                    '${formatWeekdayShort(entry.date)}',
        ),
        actions: [
          if (entry != null) ...[
            IconButton(
              tooltip: l.actionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(entry),
            ),
            PopupMenuButton<String>(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l.actionDelete,
                    style: TextStyle(color: context.nok.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }

  void _retry() =>
      ref.read(dataSyncProvider).refresh([journalEntryProvider(entryId)]);

  Widget _loading(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.lg,
        Insets.gutter,
        Gap.lg,
      ),
      children: [
        const Bone.text(width: 220, lineHeight: 28),
        const SizedBox(height: Gap.lg),
        const Bone.circle(size: 28),
        const SizedBox(height: Gap.xl),
        for (var i = 0; i < 6; i++)
          const Bone.text(width: double.infinity, lineHeight: 28),
        const Bone.text(width: 160, lineHeight: 28),
      ],
    );
  }
}

/// The entry, for reading (design-analysis §7.12): its title, the mood,
/// energy and weather, the body in the reading style — paragraphs as
/// paragraphs, web formatting as formatted — then the gratitude box and
/// the tags.
class _DetailBody extends StatelessWidget {
  final JournalEntry entry;
  const _DetailBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final reading = context.nokText.reading;
    final hasTitle = (entry.title ?? '').trim().isNotEmpty;
    final html = entry.bodyHtml ?? '';
    final plain = (entry.bodyText ?? entry.bodyPlain ?? '').trim();
    final paragraphs = plain
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Gap.sm,
        Insets.gutter,
        Gap.x4,
      ),
      children: [
        if (hasTitle) ...[
          Semantics(
            header: true,
            child: Text(entry.title!, style: text.headlineMedium),
          ),
          const SizedBox(height: Gap.md),
        ],
        _moodEnergyRow(context),
        if (entry.weather != null) ...[
          const SizedBox(height: Gap.sm),
          _weatherRow(context),
        ],
        const SizedBox(height: Gap.xl),
        if (html.isNotEmpty)
          HtmlWidget(html, textStyle: reading.copyWith(color: c.inkHi))
        else
          for (final (i, p) in paragraphs.indexed) ...[
            if (i > 0) const SizedBox(height: Gap.lg),
            Text(p, style: reading),
          ],
        if ((entry.gratitude ?? '').isNotEmpty) ...[
          const SizedBox(height: Gap.xxl),
          _gratitudeBox(context),
        ],
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: Gap.xxl),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [for (final t in entry.tags) TagPill(t)],
          ),
        ],
      ],
    );
  }

  Widget _moodEnergyRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final energy = entry.energyLevel ?? 0;
    final children = <Widget>[];
    if (entry.mood != null) {
      children.add(
        MoodEmoji(
          emoji: moodEmojiFor(entry.mood, serverEmoji: entry.moodEmoji),
          size: 28,
        ),
      );
      children.add(const SizedBox(width: Gap.sm));
      children.add(Text(l.moodLabel(entry.mood!), style: text.titleMedium));
    }
    if (energy > 0) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: Gap.lg));
        children.add(Container(width: 1, height: 16, color: c.divider));
        children.add(const SizedBox(width: Gap.lg));
      }
      children.add(
        Text(l.journalEnergy, style: text.bodySmall!.copyWith(color: c.inkMid)),
      );
      children.add(const SizedBox(width: Gap.sm));
      children.add(EnergyBars(level: energy));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: Gap.sm,
      children: children,
    );
  }

  Widget _weatherRow(BuildContext context) {
    final c = context.nok;
    return Row(
      children: [
        Icon(
          journalWeatherIcon(entry.weather, context.l10n),
          size: 16,
          color: c.inkMid,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            entry.weather!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: c.inkMid),
          ),
        ),
      ],
    );
  }

  /// "MİNNET": goldContainer, a 1 dp goldDim edge.
  Widget _gratitudeBox(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.goldDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 14, color: c.onGoldContainer),
              const SizedBox(width: 6),
              Text(
                context.l10n.journalGratitude,
                style: text.labelMedium!.copyWith(color: c.onGoldContainer),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            entry.gratitude!,
            style: text.bodyLarge!.copyWith(color: c.onGoldContainer),
          ),
        ],
      ),
    );
  }
}
