import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../l10n/app_l10n.dart';
import '../../../../models/todo.dart';
import '../../../../theme/app_colors.dart';
import '../../../widgets/check_pop.dart';
import 'today_common.dart';

/// A todo row — on Today and on the Todos screen: a checkbox with a 48 dp
/// target the height of the row, a 3 dp priority edge bar, the title, and
/// under it when it is due (in the error colour once overdue), its list and
/// whether it has notes.
///
/// The checkbox ticks it off or reopens it ([onToggle]); a tap on the rest
/// of the row opens it for editing ([onTap]) and a long press its actions
/// ([onLongPress]). Without [onTap] the whole row ticks it off.
///
/// For screen readers the row is one stop: what it is and when it is due,
/// whether it is done, a tap that edits it, and the tick — plus [actions],
/// the swipe actions of the list it is in — as custom actions.
class TodoRow extends StatelessWidget {
  final Todo todo;

  /// The checked state on screen (a tick shows before the server answers).
  final bool done;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether to name the todo's list (left out where the list is filtered).
  final bool showList;

  /// More actions for screen readers, by their label.
  final Map<String, VoidCallback> actions;

  const TodoRow({
    super.key,
    required this.todo,
    required this.done,
    required this.onToggle,
    this.onTap,
    this.onLongPress,
    this.showList = true,
    this.actions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final edge = priorityEdgeColor(c, todo.priority);

    final due = todo.dueDay;
    final dueLabel = due == null ? null : l.todoDue(due, todo.dueTime);
    final overdue = todo.overdue && !done;
    final list = showList ? todo.todoList : null;
    final hasNotes = (todo.body?.trim().isNotEmpty ?? false);

    final tap = onTap ?? onToggle;
    return Semantics(
      container: true,
      excludeSemantics: true,
      checked: done,
      label: l.todoSemantics(
        todo.title,
        due: dueLabel,
        overdue: overdue,
        done: done,
      ),
      onTap: tap,
      onTapHint: onTap == null ? null : l.actionEdit,
      onLongPress: onLongPress,
      customSemanticsActions: {
        // The tick is its own action when a tap edits the row.
        if (onTap != null)
          CustomSemanticsAction(label: done ? l.todoReopen : l.todoComplete):
              onToggle,
        for (final MapEntry(:key, :value) in actions.entries)
          CustomSemanticsAction(label: key): value,
      },
      child: InkWell(
        onTap: tap,
        onLongPress: onLongPress,
        splashColor: c.gold.withValues(alpha: 0.08),
        child: ConstrainedBox(
          // Taller with large text rather than clipped.
          constraints: const BoxConstraints(minHeight: 60),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: edge,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // A 48 dp target the height of the row: the box's own tap
                // wins inside it, this one around it.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: SizedBox(
                    width: 56,
                    child: Center(
                      child: CheckPop.checkbox(
                        checked: done,
                        color: c.gold,
                        onTap: onToggle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 20, 10),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dueLabel != null || list != null || hasNotes)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _Meta(
                              due: dueLabel,
                              overdue: overdue,
                              list: list,
                              notes: hasNotes,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under a todo's title: when it is due · its list · notes.
class _Meta extends StatelessWidget {
  final String? due;
  final bool overdue;
  final TodoListRef? list;
  final bool notes;

  const _Meta({
    required this.due,
    required this.overdue,
    required this.list,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: c.inkMid,
        );
    final list = this.list;
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (due != null)
          Text(
            due!,
            style: style.copyWith(color: overdue ? c.error : c.inkMid),
          ),
        if (list != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hexColor(list.color, fallback: c.inkLow),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  list.name,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        if (notes) Icon(Icons.notes, size: 14, color: c.inkLow),
      ],
    );
  }
}
