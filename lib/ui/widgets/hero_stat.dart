import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'nokturn_card.dart';

/// A screen's hero figure in its card — Finance's "BU AY NET"
/// (design-analysis §4.20). Top to bottom:
///
/// 1. [overline] — labelMedium inkMid, already UPPERCASE in l10n;
/// 2. 8 dp, the [value] — a `MoneyText` in its hero variant;
/// 3. 8 dp, the [support] line — usually a [HeroStatSupport];
/// 4. 4 dp, the [footnote] — bodySmall inkMid ("Bu yıl +₺21.200");
/// 5. 12 dp, the [insight] — one sentence, bodyMedium inkHi, ≤ 2 lines;
/// 6. 16 dp, the [chart] slot (a 96 dp `PaceLine`) — left out when there
///    is no data to draw.
///
/// Every part after the value is optional and takes its gap with it.
class HeroStat extends StatelessWidget {
  final String overline;
  final Widget value;
  final Widget? support;
  final String? footnote;
  final String? insight;
  final Widget? chart;

  /// The card's tap: opens the detail behind the figure.
  final VoidCallback? onTap;

  const HeroStat({
    super.key,
    required this.overline,
    required this.value,
    this.support,
    this.footnote,
    this.insight,
    this.chart,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      variant: NokCardVariant.hero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(overline, style: text.labelMedium),
          const SizedBox(height: Gap.sm),
          value,
          if (support != null) ...[
            const SizedBox(height: Gap.sm),
            support!,
          ],
          if (footnote != null) ...[
            const SizedBox(height: Gap.xs),
            Text(footnote!, style: text.bodySmall),
          ],
          if (insight != null) ...[
            const SizedBox(height: Gap.md),
            Text(
              insight!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium!.copyWith(color: c.inkHi),
            ),
          ],
          if (chart != null) ...[
            const SizedBox(height: Gap.lg),
            chart!,
          ],
        ],
      ),
    );
  }
}

/// The hero's support line: labelled figures joined by " · " — "Gelir
/// +₺57.800 · Gider −₺33.200" — labels in bodyMedium inkMid, figures as
/// given (`MoneyText` row). It shrinks to fit rather than wrap.
class HeroStatSupport extends StatelessWidget {
  /// (label, figure) pairs.
  final List<(String, Widget)> parts;

  const HeroStatSupport({super.key, required this.parts});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.nok;
    final label = text.bodyMedium!.copyWith(color: c.inkMid);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) Text('  ·  ', style: label),
            Text(parts[i].$1, style: label),
            const SizedBox(width: Gap.xs + 2),
            parts[i].$2,
          ],
        ],
      ),
    );
  }
}
