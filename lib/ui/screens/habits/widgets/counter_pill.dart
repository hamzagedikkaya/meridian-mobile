import 'package:flutter/material.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/app_colors.dart';

/// 96×40 "− n/target ＋" for multi-count habits (target_count > 1). Fills the
/// habit color when count reaches target (design §4.5).
class CounterPill extends StatelessWidget {
  final int count;
  final int target;
  final Color color;
  final void Function(int delta) onDelta;

  const CounterPill({
    super.key,
    required this.count,
    required this.target,
    required this.color,
    required this.onDelta,
  });

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

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: complete ? color : c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: complete ? null : Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove, count > 0, fg, c, () => onDelta(-1)),
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
              child: Text(
                '$count/$target',
                key: ValueKey('$count/$target'),
                style: text.titleSmall!
                    .copyWith(color: fg, fontFeatures: tabularFigures),
              ),
            ),
          ),
          _btn(Icons.add, count < target, fg, c, () => onDelta(1)),
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
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 32,
        height: 40,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? fg : c.inkFaint,
        ),
      ),
    );
  }
}
