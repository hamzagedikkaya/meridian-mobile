import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/current_day.dart';
import '../../../../data/data_scope.dart';
import '../../../../data/deferred_deletes.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/journal.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../widgets/nokturn_card.dart';
import '../../../widgets/nokturn_row.dart';
import '../../../widgets/section_header.dart';
import '../../journal/journal_editor.dart';
import '../../journal/widgets/mood.dart';
import 'start_card.dart';

/// Today's journal card (design-analysis §7.2.6).
///
/// * No entry today: "Bugün nasıldı?" with "Yaz", and the five moods as
///   48 dp buttons (a 28 sp emoji over its name) — a mood opens the editor
///   with it picked.
/// * An entry today: "Bugün yazdın" with its title or first sentence; a tap
///   opens it.
///
/// It reads the week's entries (`GET /journal_entries?range=7d`) for
/// today's only; until they are in, it shows nothing.
class TodayJournalSection extends ConsumerWidget {
  const TodayJournalSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final today =
        ref.watch(homeProvider.select((a) => a.value?.data.today)) ??
        ref.watch<DateTime>(currentDayProvider);
    final day = dateOnly(today);
    final loaded = ref.watch(
      journalProvider(todayJournalRange).select((a) => a.value != null),
    );
    // An entry whose delete waits out its undo is gone already (§6.6): the
    // card asks about today again, and never opens it.
    final hidden = ref.watch(deferredDeletesProvider);
    final entry = ref.watch(
      journalProvider(todayJournalRange).select((a) {
        for (final e in withoutDeleted(
          a.value?.data.entries ?? const <JournalEntry>[],
          hidden,
          DataScope.journal,
          (e) => e.id,
        )) {
          if (dateOnly(e.date) == day) return e;
        }
        return null;
      }),
    );
    // The first-run card has its own "Bugünü yaz".
    final starting = ref.watch(todayStartProvider.select((p) => p != null));
    if (!loaded || (starting && entry == null)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l.titleJournal),
        if (entry != null)
          NokturnCard(
            variant: NokCardVariant.list,
            child: NokturnRow(
              title: l.todayJournalWritten,
              meta: _gist(entry),
              chevron: true,
              onTap: () => context.push('/journal/${entry.id}'),
            ),
          )
        else
          const _HowWasToday(),
      ],
    );
  }

  /// The entry's title, else the first sentence of its text.
  static String? _gist(JournalEntry entry) {
    final title = entry.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final body = entry.bodyPlain?.trim() ?? '';
    if (body.isEmpty) return null;
    final end = body.indexOf(RegExp(r'[.!?\n]'));
    return end < 0 ? body : body.substring(0, end + 1).trim();
  }
}

class _HowWasToday extends StatelessWidget {
  const _HowWasToday();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xs, Gap.sm, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Hit.min),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.journalHowWasToday, style: text.titleMedium),
                ),
                TextButton(
                  onPressed: () => openJournalEditor(context),
                  child: Text(l.todayJournalWrite),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
          Padding(
            padding: const EdgeInsets.only(right: Gap.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final mood in journalMoodOrder)
                  Flexible(
                    child: _MoodButton(
                      emoji: journalMoodEmojis[mood]!,
                      label: l.moodLabel(mood),
                      onTap: () =>
                          openJournalEditor(context, initialMood: mood),
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

class _MoodButton extends StatelessWidget {
  const _MoodButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      // excludeSemantics drops the InkResponse's own tap: say it here.
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: Hit.min),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: Hit.min,
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 28, height: 1),
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: text.labelSmall!.copyWith(color: c.inkMid),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
