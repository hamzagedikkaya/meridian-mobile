import 'package:flutter/material.dart';

import '../../../../core/haptics.dart';
import '../../../../theme/app_colors.dart';

/// Mood scale used across Günlük — keys match the API `mood`/`mood_counts`.
const journalMoodOrder = ['great', 'good', 'neutral', 'bad', 'awful'];

const journalMoodEmojis = <String, String>{
  'great': '😄',
  'good': '🙂',
  'neutral': '😐',
  'bad': '🙁',
  'awful': '😢',
};

const journalMoodLabels = <String, String>{
  'great': 'Harika',
  'good': 'İyi',
  'neutral': 'Normal',
  'bad': 'Kötü',
  'awful': 'Berbat',
};

/// Prefer the server-provided emoji, fall back to the local map.
String moodEmojiFor(String? mood, {String? serverEmoji}) {
  if (serverEmoji != null && serverEmoji.isNotEmpty) return serverEmoji;
  if (mood == null) return '';
  return journalMoodEmojis[mood] ?? '';
}

/// A single mood glyph. [dimmed] halves opacity (mood-strip filter state).
class MoodEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  final bool dimmed;

  const MoodEmoji({
    super.key,
    required this.emoji,
    this.size = 24,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: Text(emoji, style: TextStyle(fontSize: size, height: 1.1)),
    );
  }
}

/// The 5-emoji check-in row (editor step 1). 56dp emoji + Turkish label.
class MoodPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  final double size;

  const MoodPicker({
    super.key,
    this.selected,
    required this.onSelected,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final mood in journalMoodOrder)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tick();
              onSelected(mood);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoodEmoji(
                  emoji: journalMoodEmojis[mood]!,
                  size: size,
                  dimmed: selected != null && selected != mood,
                ),
                const SizedBox(height: 8),
                Text(
                  journalMoodLabels[mood]!,
                  style: text.labelSmall!.copyWith(
                    color: selected == mood ? c.gold : c.inkLow,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
