import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';
import 'pressable_scale.dart';

/// The app's chip (design-analysis §4.12): a 36 dp pill inside a 48 dp
/// target, for filters, choices and starter templates.
///
/// | State | Look |
/// |---|---|
/// | not selected | surface2, hairline; label inkMid w500 |
/// | [selected] | goldContainer, a goldDim edge (3.33:1 on surface2); label onGoldContainer w600 and a leading `check_rounded` — unless the chip shows a [dot] or an [icon] |
/// | [dropdown] | a trailing `keyboard_arrow_down_rounded` |
/// | not [enabled] | label inkDisabled (a selected one keeps its look) |
///
/// Selection is told by colour **and** shape: the tick and the edge.
/// Colours change in [Motion.quick]; the chip presses to 0.95. A tap plays
/// the selection tick.
///
/// Screen readers hear one button with its [label], whether it is
/// [selected], and — with [exclusive] (one choice of a group) — that it is
/// one of a mutually exclusive set.
class NokChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// A 16 dp icon before the label.
  final IconData? icon;

  /// A 10 dp colour dot before the label (a category's colour).
  final Color? dot;

  /// Opens a picker: a trailing arrow.
  final bool dropdown;

  /// Shown but not changeable (a locked currency).
  final bool enabled;

  /// One choice of a single-choice group.
  final bool exclusive;

  const NokChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dot,
    this.dropdown = false,
    this.enabled = true,
    this.exclusive = false,
  });

  /// The drawn height; the target is [Hit.min].
  static const height = 36.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final active = enabled && onTap != null;
    final duration = Motion.orInstant(context, Motion.quick);
    // A locked choice still shows which one it is.
    final fg = selected
        ? c.onGoldContainer
        : enabled
            ? c.inkMid
            : c.inkDisabled;
    final tick = selected && dot == null && icon == null;

    final pill = AnimatedContainer(
      duration: duration,
      curve: Motion.enter,
      // 14 / 8 dp inside, the 1 dp edge included: 36 dp tall.
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: ShapeDecoration(
        color: selected ? c.goldContainer : c.surface2,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.goldDim : c.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tick) ...[
            Icon(Icons.check_rounded, size: 16, color: fg),
            const SizedBox(width: 6),
          ] else if (dot != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: Gap.sm),
          ] else if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: text.labelLarge!.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (dropdown) ...[
            const SizedBox(width: Gap.xs),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg),
          ],
        ],
      ),
    );

    void tap() {
      Haptics.tick();
      onTap!();
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      inMutuallyExclusiveGroup: exclusive ? true : null,
      label: label,
      onTap: active ? tap : null,
      excludeSemantics: true,
      child: PressableScale.small(
        onTap: active ? tap : null,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        ),
      ),
    );
  }
}
