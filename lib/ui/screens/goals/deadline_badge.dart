import 'package:flutter/material.dart';

import '../../../core/formats.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart' as models;
import '../../../theme/app_colors.dart';

/// A goal's deadline pill (design-analysis §7.11), 8/3 dp inside, labelSmall
/// w600:
///
/// | State | Fill / text |
/// |---|---|
/// | overdue | errorContainer / error, "3g gecikti" |
/// | ≤ 7 days | warningContainer / warning, "5g kaldı" |
/// | today | warningContainer / warning, "bugün" |
/// | far | surface2 + hairline / inkMid, "23 Eki" |
/// | no deadline | nothing |
class DeadlineBadgeChip extends StatelessWidget {
  final models.DeadlineBadge? badge;
  final DateTime? deadline;

  const DeadlineBadgeChip({super.key, this.badge, this.deadline});

  /// Whether a goal with [badge] and [deadline] shows a pill at all.
  static bool shows(models.DeadlineBadge? badge, DateTime? deadline) =>
      switch (badge?.state) {
        'overdue' || 'today' || 'soon' => true,
        _ => deadline != null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final b = badge;
    final date = deadline;
    if (!shows(b, date)) return const SizedBox.shrink();

    final Color bg;
    final Color fg;
    final String label;
    var edge = false;
    switch (b?.state) {
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
        edge = true;
        label = formatDate(date!, withYear: date.year != appToday().year);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: edge ? Border.all(color: c.hairline) : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        style: text.labelSmall!.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
