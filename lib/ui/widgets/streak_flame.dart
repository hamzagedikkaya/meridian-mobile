import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_typography.dart';

/// Where a [StreakFlame] sits, which sets its size.
enum StreakFlameSize {
  /// In a row's meta line: 14 dp flame, numMeta.
  meta,

  /// In a stat tile: 16 dp flame, numStat.
  stat,

  /// On a detail screen: 20 dp flame, numStat.
  detail,
}

/// A running streak: a goldBright `local_fire_department_rounded` and the
/// day count (design-analysis §4.20) — the one flame of the app; no emoji.
///
/// A broken streak (`days` 0) never shows a flame by a zero: it reads
/// "Yeni seri · Rekor 21" (bodySmall inkMid) when there is a [record], and
/// nothing when there is not. A screen reader hears "12 günlük seri".
class StreakFlame extends StatelessWidget {
  final int days;

  /// The best streak so far, shown once the streak is broken.
  final int? record;
  final StreakFlameSize size;

  /// The number's colour; inkHi by default.
  final Color? color;

  const StreakFlame({
    super.key,
    required this.days,
    this.record,
    this.size = StreakFlameSize.meta,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final record = this.record;
    if (days <= 0) {
      if (record == null || record <= 0) return const SizedBox.shrink();
      return Text(
        l.streakNewRecord(record),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final nokText = context.nokText;
    final (double icon, TextStyle style) = switch (size) {
      StreakFlameSize.meta => (14.0, nokText.numMeta),
      StreakFlameSize.stat => (16.0, nokText.numStat),
      StreakFlameSize.detail => (20.0, nokText.numStat),
    };
    return Semantics(
      label: l.streakDays(days),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: icon,
            color: c.goldBright,
          ),
          const SizedBox(width: Gap.xxs),
          Text('$days', style: style.copyWith(color: color ?? c.inkHi)),
        ],
      ),
    );
  }
}
