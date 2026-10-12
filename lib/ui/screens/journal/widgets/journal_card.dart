import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/journal.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../ui/widgets/nokturn_card.dart';
import '../../../../ui/widgets/skeletons.dart';
import 'energy_bars.dart';
import 'mood.dart';

/// A tag pill (labelSmall on surface2, a hairline edge). With [onTap] it
/// filters the journal by the tag, inside a 48 × 48 dp target. The tap is
/// gesture-only: the pill sits in a card's merged node, which offers the
/// filter as a custom semantics action instead (see [JournalCard]).
class TagPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const TagPill(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: c.surface2,
        shape: StadiumBorder(side: BorderSide(color: c.hairline)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall!.copyWith(color: c.inkMid),
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return pill;
    return Semantics(
      label: context.l10n.journalTagFilter(label),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: Hit.min,
            minWidth: Hit.min,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// What a card shows as the entry's title and body: the title; or, with
/// none, the body's first sentence, and the rest of the body under it.
/// Null title: there is no text at all ("Adsız").
({String? title, String body}) journalCardText(JournalEntry entry) {
  final title = (entry.title ?? '').trim();
  final body = (entry.bodyPlain ?? '').trim();
  if (title.isNotEmpty) return (title: title, body: body);
  if (body.isEmpty) return (title: null, body: '');
  // The first sentence: up to a . ! ? or … followed by a space, or the
  // first line break — whichever comes first.
  final end = RegExp(r'[.!?…](?=\s)|\n').firstMatch(body);
  if (end == null) return (title: body, body: '');
  final cut = body[end.start] == '\n' ? end.start : end.end;
  return (
    title: body.substring(0, cut).trim(),
    body: body.substring(cut).trim(),
  );
}

/// A journal entry in the list (design-analysis §7.12): a standard card —
/// the weekday over the day number (Fraunces 28), the mood and its
/// [EnergyBars] top right, the title (or the first sentence), up to four
/// lines of the body, up to three tags and the gratitude heart.
///
/// [isToday] puts a gold "BUGÜN" overline on top. Tags filter the journal
/// through [onTag]. A tap opens the entry; a long press its actions.
///
/// The card is one merged button for a screen reader, so the long press's
/// actions ([semanticActions]: Düzenle · Sil) and each shown tag's filter
/// are its custom semantics actions (§6.4, §8.4).
class JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onTag;
  final bool isToday;

  /// The long press's actions, offered to TalkBack as custom actions.
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  const JournalCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.onTag,
    this.isToday = false,
    this.semanticActions,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final (:title, :body) = journalCardText(entry);
    final tags = entry.tags.take(3).toList();
    final energy = entry.energyLevel ?? 0;
    final onTag = this.onTag;
    final actions = <CustomSemanticsAction, VoidCallback>{
      ...?semanticActions,
      if (onTag != null)
        for (final t in tags)
          CustomSemanticsAction(label: l.journalTagFilter(t)): () => onTag(t),
    };

    return NokturnCard(
      onTap: onTap,
      onLongPress: onLongPress,
      // Merged into the card's one button.
      child: Semantics(
        customSemanticsActions: actions.isEmpty ? null : actions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isToday) ...[
              Text(
                l.journalTodayOverline,
                style: text.labelMedium!.copyWith(color: c.gold),
              ),
              const SizedBox(height: Gap.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _DateBlock(entry.date)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (entry.mood != null)
                      Semantics(
                        label: l.moodLabel(entry.mood!),
                        excludeSemantics: true,
                        child: MoodEmoji(
                          emoji: moodEmojiFor(
                            entry.mood,
                            serverEmoji: entry.moodEmoji,
                          ),
                          size: 24,
                        ),
                      ),
                    if (energy > 0) ...[
                      const SizedBox(height: Gap.sm),
                      EnergyBars(level: energy),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              title ?? l.journalUntitled,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: title != null
                  ? text.titleMedium
                  : text.titleMedium!.copyWith(color: c.inkLow),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Text(
                body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ],
            if (tags.isNotEmpty || entry.hasGratitude) ...[
              SizedBox(
                height: onTag != null && tags.isNotEmpty ? Gap.xs : Gap.md,
              ),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: Gap.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final t in tags)
                          TagPill(
                            t,
                            onTap: onTag == null ? null : () => onTag(t),
                          ),
                      ],
                    ),
                  ),
                  if (entry.hasGratitude) ...[
                    const SizedBox(width: Gap.sm),
                    Icon(Icons.favorite_rounded, size: 14, color: c.goldDim),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  final DateTime date;
  const _DateBlock(this.date);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatWeekdayShort(date),
          style: text.labelSmall!.copyWith(color: c.inkMid),
        ),
        Text('${date.day}', style: text.displaySmall),
      ],
    );
  }
}

/// A journal card's skeleton: the same frame, in bones.
class JournalCardSkeleton extends StatelessWidget {
  const JournalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone.text(width: 28, lineHeight: 14),
                    SizedBox(height: Gap.xs),
                    Bone.text(width: 32, lineHeight: 34),
                  ],
                ),
              ),
              Bone.circle(size: 24),
            ],
          ),
          SizedBox(height: Gap.md),
          Bone.text(width: 180, lineHeight: 22),
          SizedBox(height: Gap.sm),
          Bone.text(width: double.infinity, lineHeight: 20),
          SizedBox(height: Gap.xs),
          Bone.text(width: double.infinity, lineHeight: 20),
          SizedBox(height: Gap.xs),
          Bone.text(width: 160, lineHeight: 20),
        ],
      ),
    );
  }
}
