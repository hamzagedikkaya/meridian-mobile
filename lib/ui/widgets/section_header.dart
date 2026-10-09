import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_typography.dart';
import 'progress_ring.dart';

/// A section's title row (design-analysis §4.3): always at least 48 dp tall,
/// with or without actions, so sections line up.
///
/// Left to right: the [title] (titleMedium inkHi, up to two lines, a
/// screen-reader header) · an optional [count] ("2/5", numMeta inkMid) ·
/// an optional 16 dp mini ring for [progress] · flexible space · an
/// optional add button ([onAdd], `add_rounded` 22, 48 × 48, [addTooltip])
/// · an optional gold "Tümü ›" ([onSeeAll]) whose text ends at the card's
/// edge.
///
/// Rhythm (§3.8): give a header 24 dp ([Gap.xxl]) above it; it keeps 4 dp
/// ([Gap.xs]) to the card below.
class SectionHeader extends StatelessWidget {
  final String title;

  /// Anything else to show at the end of the row, before the actions.
  final Widget? trailing;
  final VoidCallback? onSeeAll;

  /// A count after the title ("2/5").
  final String? count;

  /// 0–1: a 16 dp ring after the count.
  final double? progress;

  /// The ring's colour; gold by default.
  final Color? progressColor;

  /// Adds an item to the section: a 48 dp `+` button.
  final VoidCallback? onAdd;

  /// What the `+` button adds, for its tooltip and screen readers; "Ekle"
  /// by default.
  final String? addTooltip;

  /// Around the row; 4 dp below by default.
  final EdgeInsetsGeometry padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.onSeeAll,
    this.count,
    this.progress,
    this.progressColor,
    this.onAdd,
    this.addTooltip,
    this.padding = const EdgeInsets.only(bottom: Gap.xs),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final count = this.count;
    final progress = this.progress;
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.min),
        child: Row(
          children: [
            // The title group takes the free width; the actions keep theirs
            // at the end.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: Gap.sm),
                    Text(
                      count,
                      style: context.nokText.numMeta.copyWith(color: c.inkMid),
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(width: 6),
                    ExcludeSemantics(
                      child: ProgressRing(
                        value: progress,
                        color: progressColor ?? c.gold,
                        size: 16,
                        strokeWidth: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (onAdd != null)
              IconButton(
                onPressed: onAdd,
                tooltip: addTooltip ?? l.actionAdd,
                icon: Icon(Icons.add_rounded, size: 22, color: c.inkMid),
              ),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: Gap.md),
                  minimumSize: Hit.minSize,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.actionSeeAllShort),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
