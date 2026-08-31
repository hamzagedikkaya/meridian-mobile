import 'package:flutter/material.dart';

import '../../../../l10n/app_l10n.dart';
import '../../../../models/todo.dart';
import '../../../../theme/app_colors.dart';
import '../../../widgets/check_pop.dart';
import 'today_common.dart';

/// Today todo row: 24dp checkbox + 3dp priority edge bar + title + due date.
/// [done] reflects the optimistic checked state; the whole row toggles.
class TodoRow extends StatelessWidget {
  final Todo todo;
  final bool done;
  final VoidCallback onToggle;

  const TodoRow({
    super.key,
    required this.todo,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final edge = priorityEdgeColor(c, todo.priority);

    final due = todo.dueAt;
    final dueLabel = due == null ? null : context.l10n.relativeDay(due);
    final overdue = todo.overdue && !done;

    return InkWell(
      onTap: onToggle,
      splashColor: c.gold.withValues(alpha: 0.08),
      child: SizedBox(
        height: 60,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  CheckPop.checkbox(
                    checked: done,
                    color: c.gold,
                    onTap: onToggle,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todo.title,
                          style: text.titleSmall!.copyWith(
                            color: done ? c.inkLow : c.inkHi,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            decorationColor: c.inkLow,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dueLabel != null)
                          Text(
                            dueLabel,
                            style: text.bodySmall!.copyWith(
                              color: overdue ? c.error : c.inkMid,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
