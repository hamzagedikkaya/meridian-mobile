import 'package:flutter/material.dart';

import '../../../../core/haptics.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';

/// `energy_level` (1–5) as five rising bars (design-analysis §7.12) —
/// 3 dp wide, 6/8/10/12/14 dp tall, 2 dp apart, 1.5 dp corners. A bar up
/// to [level] is filled gold; the rest are a 1 dp inkDisabled outline, so
/// the level reads by shape, not only by colour. A screen reader hears
/// "Enerji 3 / 5".
///
/// With [onChanged] it is the editor's picker: drawn [scale] times larger,
/// each bar in its own 48 dp target; tapping the current level clears it
/// (0).
class EnergyBars extends StatelessWidget {
  final int level;
  final ValueChanged<int>? onChanged;

  /// How much larger than the 3 × 14 dp card size the bars are drawn.
  final double scale;

  const EnergyBars({
    super.key,
    required this.level,
    this.onChanged,
    this.scale = 1,
  });

  static const _heights = [6.0, 8.0, 10.0, 12.0, 14.0];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return Semantics(
        label: l.journalEnergyValue(level),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) SizedBox(width: Gap.xxs * scale),
              _Bar(filled: i < level, height: _heights[i], scale: scale),
            ],
          ],
        ),
      );
    }
    void pick(int value) {
      Haptics.tick();
      onChanged(level == value ? 0 : value);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Semantics(
            button: true,
            selected: i + 1 == level,
            inMutuallyExclusiveGroup: true,
            label: l.journalEnergyValue(i + 1),
            excludeSemantics: true,
            onTap: () => pick(i + 1),
            child: InkResponse(
              radius: Hit.min / 2,
              excludeFromSemantics: true,
              onTap: () => pick(i + 1),
              child: SizedBox(
                width: Hit.min,
                height: Hit.min,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: _Bar(
                      filled: i < level,
                      height: _heights[i],
                      scale: scale,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final bool filled;
  final double height;
  final double scale;

  const _Bar({required this.filled, required this.height, required this.scale});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Container(
      width: 3 * scale,
      height: height * scale,
      decoration: BoxDecoration(
        color: filled ? c.gold : null,
        borderRadius: BorderRadius.circular(1.5 * scale),
        border: filled ? null : Border.all(color: c.inkDisabled),
      ),
    );
  }
}
