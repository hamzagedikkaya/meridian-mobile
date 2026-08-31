import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/journal.dart';
import '../../../../theme/app_colors.dart';
import '../../../../ui/widgets/nokturn_card.dart';
import 'energy_dots.dart';
import 'mood.dart';

/// Small surface2 tag pill (labelSmall). Reused by the detail screen.
class TagPill extends StatelessWidget {
  final String label;
  const TagPill(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.inkMid),
      ),
    );
  }
}

/// Full-width journal entry card (design §4.7).
class JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onTap;

  const JournalCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final hasTitle = (entry.title ?? '').trim().isNotEmpty;
    final body = (entry.bodyPlain ?? '').trim();
    final tags = entry.tags.take(3).toList();

    return NokturnCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateBlock(entry.date),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entry.mood != null)
                    MoodEmoji(
                      emoji: moodEmojiFor(entry.mood, serverEmoji: entry.moodEmoji),
                      size: 24,
                    ),
                  if (entry.energyLevel != null) ...[
                    const SizedBox(height: 8),
                    EnergyDots(level: entry.energyLevel!),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hasTitle ? entry.title! : context.l10n.journalUntitled,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: hasTitle
                ? text.titleMedium
                : text.titleMedium!.copyWith(
                    color: c.inkLow,
                    fontStyle: FontStyle.italic,
                  ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
          ],
          if (tags.isNotEmpty || entry.hasGratitude) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final t in tags) TagPill(t)],
                  ),
                ),
                if (entry.hasGratitude) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.favorite, size: 14, color: c.goldDim),
                ],
              ],
            ),
          ],
        ],
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
        Text(
          '${date.day}',
          style: text.headlineMedium,
        ),
      ],
    );
  }
}
