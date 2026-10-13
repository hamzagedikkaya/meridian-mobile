import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../../core/haptics.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../../ui/widgets/pressable_scale.dart';

/// Mood scale used across Günlük — keys match the API `mood`/`mood_counts`.
const journalMoodOrder = ['great', 'good', 'neutral', 'bad', 'awful'];

const journalMoodEmojis = <String, String>{
  'great': '😄',
  'good': '🙂',
  'neutral': '😐',
  'bad': '🙁',
  'awful': '😞',
};

/// Prefer the server-provided emoji, fall back to the local map.
String moodEmojiFor(String? mood, {String? serverEmoji}) {
  if (serverEmoji != null && serverEmoji.isNotEmpty) return serverEmoji;
  if (mood == null) return '';
  return journalMoodEmojis[mood] ?? '';
}

/// Greyscale, for the moods a filter leaves out — never half opacity
/// (design-analysis §3.4 rule 7).
const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// A single mood glyph — content, not an icon. [greyscale] for a mood the
/// filter leaves out.
class MoodEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  final bool greyscale;

  const MoodEmoji({
    super.key,
    required this.emoji,
    this.size = 24,
    this.greyscale = false,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = Text(
      emoji,
      style: TextStyle(fontSize: size, height: 1.1),
      textScaler: TextScaler.noScaling,
    );
    if (!greyscale) return glyph;
    return ColorFiltered(colorFilter: _greyscale, child: glyph);
  }
}

/// Grows its child to [scale] on the `defaultSpatial` spring (no
/// overshoot past the target worth seeing), straight there under reduced
/// motion. A leaf transition: the child is not rebuilt per tick.
class SpringScale extends StatefulWidget {
  final double scale;
  final Widget child;

  const SpringScale({super.key, required this.scale, required this.child});

  @override
  State<SpringScale> createState() => _SpringScaleState();
}

class _SpringScaleState extends State<SpringScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.scale,
    animationBehavior: AnimationBehavior.normal,
  );

  @override
  void didUpdateWidget(SpringScale old) {
    super.didUpdateWidget(old);
    if (old.scale == widget.scale) return;
    if (Motion.reduced(context)) {
      _c.value = widget.scale;
      return;
    }
    _c.animateWith(
      SpringSimulation(
        Motion.defaultSpatial,
        _c.value,
        widget.scale,
        _c.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _c, child: widget.child);
}

/// One of the five mood choices: the emoji in a 48 dp target, its name
/// under it when [showLabel]. Presses to 0.92; [selected] grows the emoji
/// to 1.15 and gilds the name.
class MoodButton extends StatelessWidget {
  final String mood;
  final bool selected;
  final bool showLabel;
  final double size;
  final VoidCallback onTap;

  const MoodButton({
    super.key,
    required this.mood,
    required this.onTap,
    this.selected = false,
    this.showLabel = true,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: l.moodLabel(mood),
      excludeSemantics: true,
      onTap: () {
        Haptics.tick();
        onTap();
      },
      child: PressableScale(
        pressedScale: 0.92,
        excludeFromSemantics: true,
        onTap: () {
          Haptics.tick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: Hit.min,
            minHeight: Hit.min,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpringScale(
                scale: selected ? 1.15 : 1,
                child: MoodEmoji(emoji: journalMoodEmojis[mood]!, size: size),
              ),
              if (showLabel) ...[
                const SizedBox(height: Gap.xs),
                // Only the name shrinks to its slot (large text): the
                // 48 dp target is never scaled.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l.moodLabel(mood),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: text.labelSmall!.copyWith(
                      color: selected ? c.gold : c.inkMid,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The five moods side by side — the editor's inline strip and the
/// journal's "Bugün nasıldı?" card.
class MoodStrip extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool showLabels;

  const MoodStrip({
    super.key,
    this.selected,
    required this.onSelected,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final mood in journalMoodOrder)
          Expanded(
            child: MoodButton(
              mood: mood,
              selected: selected == mood,
              showLabel: showLabels,
              onTap: () => onSelected(mood),
            ),
          ),
      ],
    );
  }
}

/// One chip of the journal's mood filter (design-analysis §7.12): the
/// emoji in a 32 dp surface2 circle and its count, 40 dp drawn in a 48 dp
/// target.
///
/// * [selected]: a gold edge, the count in gold, the emoji grown to 1.12.
/// * [muted] (another mood is the filter): the emoji in greyscale and an
///   inkDisabled edge — never half opacity.
class MoodFilterChip extends StatelessWidget {
  final String mood;
  final int count;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  const MoodFilterChip({
    super.key,
    required this.mood,
    required this.count,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  static const _padStart = 3.0;
  static const _padEnd = 8.0;
  static const _circle = 32.0;
  static const _gap = 4.0;

  static TextStyle _numStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// The chip's drawn width with [count] — at its widest (selected) weight
  /// and the current text scale. The filter row uses it to tell whether the
  /// five chips fit side by side.
  static double widthFor(BuildContext context, int count) {
    final painter = TextPainter(
      text: TextSpan(
        text: '$count',
        style: _numStyle(context).copyWith(fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _padStart + _circle + _gap + width + _padEnd;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final numStyle = _numStyle(context);
    final edge = selected
        ? c.gold
        : muted
        ? c.inkDisabled
        : c.hairline;
    final duration = Motion.orInstant(context, Motion.pressOut);
    return Semantics(
      button: true,
      selected: selected,
      label: '${l.moodLabel(mood)}, ${l.journalEntriesCount(count)}',
      excludeSemantics: true,
      onTap: () {
        Haptics.tick();
        onTap();
      },
      child: PressableScale(
        pressedScale: 0.92,
        excludeFromSemantics: true,
        onTap: () {
          Haptics.tick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.fromLTRB(_padStart, 3, _padEnd, 3),
              decoration: ShapeDecoration(
                color: c.surface1,
                shape: StadiumBorder(
                  side: BorderSide(color: edge, width: selected ? 1.5 : 1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _circle,
                    height: _circle,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: SpringScale(
                      scale: selected ? 1.12 : 1,
                      child: MoodEmoji(
                        emoji: journalMoodEmojis[mood]!,
                        size: 18,
                        greyscale: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    style: numStyle.copyWith(
                      color: selected ? c.gold : c.inkMid,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: Text('$count'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
