import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_typography.dart';

/// One figure with its caption — a habit's best streak, a goal's pace
/// (design-analysis §4.20).
///
/// surface1 with a hairline and 12 dp corners, 12 dp at the sides and 14 dp
/// top and bottom, at least 64 dp tall: the [value] in numStat (an optional
/// [leading] before it — a `StreakFlame` icon) over the [label] in
/// labelSmall inkMid (up to two lines). With [onTap] it ripples gold.
///
/// Lay several out with [StatTileRow]. One screen-reader stop reading the
/// value and the label ([semanticLabel] replaces both).
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Widget? leading;
  final VoidCallback? onTap;

  /// What a screen reader says instead of "[value], [label]".
  final String? semanticLabel;

  /// The value's colour; inkHi by default.
  final Color? valueColor;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.leading,
    this.onTap,
    this.semanticLabel,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: Gap.xs),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: context.nokText.numStat
                          .copyWith(color: valueColor ?? c.inkHi),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall,
            ),
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: Material(
          color: c.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.mdAll,
            side: BorderSide(color: c.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: onTap == null ? content : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// [tiles] side by side, 8 dp apart and equally wide — three across; in two
/// columns above 1.3× text so the figures keep their size (§8.3). The tiles
/// of a line are equally tall too: a date ("26 Kasım") beside a two-line
/// caption does not leave its tile short.
class StatTileRow extends StatelessWidget {
  final List<Widget> tiles;

  const StatTileRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final most = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 3;
    final columns = tiles.length < most ? tiles.length : most;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += columns) ...[
          if (i > 0) const SizedBox(height: Gap.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) const SizedBox(width: Gap.sm),
                  Expanded(
                    child: i + j < tiles.length
                        ? tiles[i + j]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
