import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../models/event.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../theme/entity_color.dart';
import 'check_pop.dart';

// The agenda row family (design-analysis §4.6), shared by Today and the
// Agenda. Both rows: at least 56 dp tall, padded 20 / 8, a 56 dp leading
// slot, 12 dp, then the title (titleMedium; two lines past 1.3× text) over
// its meta (bodySmall inkMid). A 3 × 28 dp bar sits 8 dp in from the card's
// edge, centred on the row — clear of the hairline and of the rounded
// corners — at the same x in both rows, so titles line up at 88 dp.

/// The 3 × 28 dp colour or priority bar, 8 dp in from the card's edge.
class _EdgeBar extends StatelessWidget {
  const _EdgeBar({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    if (color == null) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: SizedBox(
          width: 3,
          height: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row's frame: the bar, the leading slot and the text column.
class _AgendaRowFrame extends StatelessWidget {
  const _AgendaRowFrame({
    required this.bar,
    required this.leading,
    required this.body,
    this.overlay,
    this.textSlot = false,
  });

  final Color? bar;
  final Widget leading;
  final Widget body;

  /// Laid over the row's leading area (the checkbox's tap target).
  final Widget? overlay;

  /// The slot holds text (times, "Tüm gün"): it widens with the text
  /// scale, so large text is never cut.
  final bool textSlot;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Stack(
        // A one-line row is shorter than 56 dp: centre it.
        alignment: AlignmentDirectional.centerStart,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: textSlot ? _textSlotWidth(context) : 56,
                  child: Align(alignment: Alignment.centerLeft, child: leading),
                ),
                const SizedBox(width: 12),
                Expanded(child: body),
              ],
            ),
          ),
          _EdgeBar(color: bar),
          if (overlay != null)
            Positioned(left: 0, top: 0, bottom: 0, width: 76, child: overlay!),
        ],
      ),
    );
  }
}

/// The width of a slot that holds text: 56 dp at 1×, widened as much as
/// the smallest text in it (labelSmall, then the 13 sp time) grows. Scaling
/// 56 itself is not enough: Android 14+ scales text nonlinearly, so at 200 %
/// a 56 sp size is about 61 dp while 11 sp text doubles.
double _textSlotWidth(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final sizes = [
    Theme.of(context).textTheme.labelSmall?.fontSize ?? 11,
    context.nokText.time.fontSize ?? 13,
  ];
  var factor = 1.0;
  for (final size in sizes) {
    factor = math.max(factor, scaler.scale(size) / size);
  }
  return 56 * factor;
}

/// How many lines a row title may take: one, two past 1.3× text.
int _titleLines(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13 ? 2 : 1;

/// The priority bar of a todo: urgent `error`, high `warning`, medium
/// `goldDim`; low has none (its place is kept).
Color? todoPriorityColor(NokturnColors c, String priority) =>
    switch (priority) {
      'urgent' => c.error,
      'high' => c.warning,
      'medium' => c.goldDim,
      _ => null,
    };

/// A todo row — on Today and in the Agenda (§4.6).
///
/// The leading slot holds a 24 dp [CheckPop.checkbox]; its tap target is
/// the whole 76 × 56 dp area from the card's edge, bar included. The
/// checkbox ticks it off or reopens it ([onToggle]); a tap on the rest of
/// the row opens it ([onTap]) and a long press its actions ([onLongPress]).
/// Without [onTap] the whole row ticks it off.
///
/// Done: the title turns inkLow and a 1.5 dp inkLow line strikes it
/// through, drawn left to right in [Motion.strike] once the fill is in.
/// Overdue meta is `error`; a todo with only a date shows the day, never
/// "23:59" (contract §9.1).
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
        child: _AgendaRowFrame(
          bar: todoPriorityColor(c, todo.priority),
          // The box is drawn by the overlay, which owns the 76 dp target.
          leading: const SizedBox(width: 24, height: 24),
          overlay: CheckPop.checkbox(
            checked: done,
            color: c.gold,
            onToggle: onToggle,
            expandHitArea: true,
            visualAlignment: const Alignment(-0.158, 0),
          ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StruckTitle(
                title: todo.title,
                done: done,
                style: text.titleMedium!,
                maxLines: _titleLines(context),
              ),
              if (dueLabel != null || list != null || hasNotes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _TodoMeta(
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
    );
  }
}

/// A todo title that strikes itself through when done: the colour goes
/// inkHi → inkLow in [Motion.quick] and a 1.5 dp line is drawn left to
/// right in [Motion.strike], after the check's fill. Already done when
/// built: struck at once.
class _StruckTitle extends StatefulWidget {
  const _StruckTitle({
    required this.title,
    required this.done,
    required this.style,
    required this.maxLines,
  });

  final String title;
  final bool done;
  final TextStyle style;
  final int maxLines;

  @override
  State<_StruckTitle> createState() => _StruckTitleState();
}

class _StruckTitleState extends State<_StruckTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _strike = AnimationController(
    vsync: this,
    // The fill takes [CheckPop.fillIn]; the line follows it.
    duration: CheckPop.fillIn + Motion.strike,
    value: widget.done ? 1 : 0,
  );
  late final CurvedAnimation _line = CurvedAnimation(
    parent: _strike,
    curve: Interval(
      CheckPop.fillIn.inMicroseconds /
          (CheckPop.fillIn + Motion.strike).inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );

  @override
  void didUpdateWidget(_StruckTitle old) {
    super.didUpdateWidget(old);
    if (widget.done == old.done) return;
    if (Motion.reduced(context)) {
      _strike.value = widget.done ? 1 : 0;
    } else if (widget.done) {
      _strike.forward(from: 0);
    } else {
      _strike.value = 0;
    }
  }

  @override
  void dispose() {
    _line.dispose();
    _strike.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final style = widget.style.copyWith(
      color: widget.done ? c.inkLow : c.inkHi,
    );
    return CustomPaint(
      foregroundPainter: _StrikePainter(
        progress: _line,
        text: widget.title,
        style: style,
        maxLines: widget.maxLines,
        textScaler: MediaQuery.textScalerOf(context),
        color: c.inkLow,
      ),
      child: AnimatedDefaultTextStyle(
        duration: Motion.orInstant(context, Motion.quick),
        style: style,
        child: Text(
          widget.title,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter({
    required this.progress,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.textScaler,
    required this.color,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final String text;
  final TextStyle style;
  final int maxLines;
  final TextScaler textScaler;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: textScaler,
    )..layout(maxWidth: size.width);
    final lines = tp.computeLineMetrics();
    final total = lines.fold<double>(0, (sum, line) => sum + line.width);
    var budget = total * t;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final line in lines) {
      if (budget <= 0) break;
      final w = budget.clamp(0.0, line.width);
      // Through the middle of the lower-case letters.
      final y = line.baseline - line.ascent * 0.32;
      canvas.drawLine(Offset(line.left, y), Offset(line.left + w, y), paint);
      budget -= line.width;
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_StrikePainter old) =>
      old.progress != progress ||
      old.text != text ||
      old.style != style ||
      old.maxLines != maxLines ||
      old.textScaler != textScaler ||
      old.color != color;
}

/// The line under a todo's title: when it is due · its list · notes.
class _TodoMeta extends StatelessWidget {
  final String? due;
  final bool overdue;
  final TodoListRef? list;
  final bool notes;

  const _TodoMeta({
    required this.due,
    required this.overdue,
    required this.list,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: c.inkMid);
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
              SizedBox.square(
                dimension: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: entityTone(list.color, c).fill,
                    shape: BoxShape.circle,
                  ),
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
        if (notes) Icon(Icons.notes_rounded, size: 14, color: c.inkMid),
      ],
    );
  }
}

/// An event row — on Today and in the Agenda (§4.6).
///
/// The leading slot holds the start time (`NokturnText.time`) over the end
/// (labelSmall inkLow), or "Tüm gün" (labelSmall w600 in the event's
/// colour, no pill). The bar is the event's colour; the meta its place, and
/// for a series a repeat icon with how often ("Her hafta").
///
/// [day] is the occurrence shown: a series is placed by its occurrences, at
/// the time of day of its first one (contract §10.2). Without it, the day
/// the event starts. With [showDay] the slot also says which day that is
/// ("Çar 7" over the time, the full date to a screen reader) — for rows not
/// under a heading of their own day. [finished] (an event already over on
/// Today) greys the title.
class EventRow extends StatelessWidget {
  final Event event;
  final DateTime? day;
  final VoidCallback? onTap;
  final bool showDay;
  final bool finished;

  const EventRow({
    super.key,
    required this.event,
    this.day,
    this.onTap,
    this.showDay = false,
    this.finished = false,
  });

  /// "09:00 – 10:00", "09:00", or "Tüm gün" — when [event] takes place on
  /// [day].
  static String timeLabel(AppL10n l, Event event, DateTime? day) {
    final on = day ?? event.startDay;
    if (event.allDay || on == null) return l.dayAllDay;
    final start = formatTime(event.occurrenceStart(on));
    final end = event.occurrenceEnd(on);
    return end == null ? start : '$start – ${formatTime(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(event.color, c);
    final on = day ?? event.startDay;
    final end = on == null || event.allDay ? null : event.occurrenceEnd(on);
    final location = event.location?.trim();
    final dated = showDay && on != null;
    final time = timeLabel(l, event, day);
    final allDay = event.allDay || event.startAt == null || on == null;

    final repeat = event.recurring
        ? Recurrence.parse(event.recurrenceRule).preset
        : RecurrencePreset.none;
    final repeatLabel = switch (repeat) {
      RecurrencePreset.none => null,
      RecurrencePreset.custom => null,
      _ => l.recurrence(repeat),
    };
    final metaStyle = text.bodySmall!.copyWith(color: c.inkMid);
    final meta = [
      ?repeatLabel,
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');

    final Widget clock = allDay
        ? Text(
            l.dayAllDay,
            style: text.labelSmall!.copyWith(
              color: tone.text,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            softWrap: false,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatTime(event.occurrenceStart(on)),
                style: context.nokText.time.copyWith(color: c.inkHi),
                maxLines: 1,
                softWrap: false,
              ),
              if (end != null)
                Text(
                  formatTime(end),
                  style: text.labelSmall!.copyWith(
                    color: c.inkLow,
                    fontFeatures: tabularFigures,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
            ],
          );

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onTap != null,
      label: l.eventSemantics(
        event.title,
        when: dated ? '${formatWeekday(on)}, ${formatDate(on)}, $time' : time,
        where: location == null || location.isEmpty ? null : location,
      ),
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: _AgendaRowFrame(
          bar: tone.fill,
          textSlot: true,
          leading: !dated
              ? clock
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatWeekdayShort(on)} ${on.day}',
                      style: text.labelSmall!.copyWith(
                        color: c.inkLow,
                        fontFeatures: tabularFigures,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                    const SizedBox(height: 2),
                    clock,
                  ],
                ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: text.titleMedium!.copyWith(
                  color: finished ? c.inkLow : c.inkHi,
                ),
                maxLines: _titleLines(context),
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty || event.recurring)
                Row(
                  children: [
                    if (event.recurring) ...[
                      Icon(Icons.repeat_rounded, size: 14, color: c.inkMid),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        meta,
                        style: metaStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
