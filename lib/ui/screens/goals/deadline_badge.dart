import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart' as models;
import '../../../theme/app_colors.dart';

/// Deadline pill for a goal — maps `goal.deadlineBadge.state` to the
/// errorContainer / warningContainer / surface2 palettes (design §4.6).
class DeadlineBadgeChip extends StatelessWidget {
  final models.DeadlineBadge? badge;
  final DateTime? deadline;

  const DeadlineBadgeChip({super.key, this.badge, this.deadline});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final b = badge;
    if (b == null && deadline == null) return const SizedBox.shrink();

    final Color bg;
    final Color fg;
    final String label;
    switch (b?.state ?? 'far') {
      case 'overdue':
        bg = c.errorContainer;
        fg = c.error;
        label = l.goalsOverdueBadge(b!.days);
      case 'today':
        bg = c.warningContainer;
        fg = c.warning;
        label = l.goalsDueTodayBadge;
      case 'soon':
        bg = c.warningContainer;
        fg = c.warning;
        label = l.goalsDaysLeftBadge(b!.days);
      default:
        bg = c.surface2;
        fg = c.inkMid;
        label = deadline == null ? '—' : formatDate(deadline!);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: text.labelSmall!.copyWith(color: fg)),
    );
  }
}
