import 'package:flutter/material.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/app_colors.dart';

/// 96×40 "− n/target ＋" for multi-count habits (target_count > 1). Fills the
/// habit color when count reaches target (design §4.5).
///
/// The − and + each answer a 48×48 dp touch (design-research §6.2), more
/// than the pill shows of them: their targets reach [_reach] past the
/// pill's ends and 4 dp above and below it, so the pill looks as it did.
class CounterPill extends StatelessWidget {
  final int count;
  final int target;
  final Color color;
  final void Function(int delta) onDelta;

  /// What a screen reader says for the count ("Su, 1 / 3"); the bare
  /// numbers otherwise.
  final String? semanticLabel;

  const CounterPill({
    super.key,
    required this.count,
    required this.target,
    required this.color,
    required this.onDelta,
    this.semanticLabel,
  });

  /// The minimum touch target, each way.
  static const _target = 48.0;

  /// The pill's height as drawn.
  static const _pillHeight = 40.0;

  /// How far a button's target reaches past the end of the pill: the pill
  /// shows 32 dp of each button.
  static const _reach = 8.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final complete = count >= target;
    // On the colored complete-state fill, pick white or a dark ink by the fill
    // brightness so the number stays legible on any habit color.
    final onFill = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF221805);
    final fg = complete ? onFill : c.inkHi;
    const inset = (_target - _pillHeight) / 2;

    return SizedBox(
      height: _target,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The pill as drawn, inside the touch targets.
          Positioned.fill(
            left: _reach,
            right: _reach,
            top: inset,
            bottom: inset,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: complete ? color : c.surface2,
                borderRadius: BorderRadius.circular(999),
                border: complete ? null : Border.all(color: c.hairline),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.remove, count > 0, fg, c, () => onDelta(-1),
                  context.l10n.habitLogDecrease),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Semantics(
                    key: ValueKey('$count/$target'),
                    label: semanticLabel,
                    excludeSemantics: semanticLabel != null,
                    liveRegion: true,
                    child: Text(
                      '$count/$target',
                      style: text.titleSmall!
                          .copyWith(color: fg, fontFeatures: tabularFigures),
                    ),
                  ),
                ),
              ),
              _btn(Icons.add, count < target, fg, c, () => onDelta(1),
                  context.l10n.habitLogIncrease),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(
    IconData icon,
    bool enabled,
    Color fg,
    NokturnColors c,
    VoidCallback onTap,
    String label,
  ) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox.square(
          dimension: _target,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? fg : c.inkFaint,
          ),
        ),
      ),
    );
  }
}
