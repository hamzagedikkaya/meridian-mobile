import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';

/// What a day of a habit — or of the perfect-day chain — looks like
/// (design-analysis §4.23). Told apart by shape, not by colour alone.
enum HabitDayState {
  /// Complete: filled.
  done,

  /// Some of the target: half filled, with an outline.
  partial,

  /// Nothing logged on a day that counted: a 1.5 dp inkDisabled outline,
  /// no fill (3:1 or more on surface1).
  missed,

  /// Today, nothing yet: a 1.5 dp gold outline.
  pending,

  /// No record — before the habit started, a day without habits: a 3 dp
  /// inkFaint dot.
  none,
}

/// The state a chain entry shows. A day before [startDate] (the server
/// calls it `missed`) has no record.
HabitDayState habitDayStateOf(
  ChainStatus status, {
  DateTime? date,
  DateTime? startDate,
}) {
  if (date != null &&
      startDate != null &&
      dateOnly(date).isBefore(dateOnly(startDate))) {
    return HabitDayState.none;
  }
  return switch (status) {
    ChainStatus.completed || ChainStatus.perfect => HabitDayState.done,
    ChainStatus.partial => HabitDayState.partial,
    ChainStatus.todayPending => HabitDayState.pending,
    ChainStatus.missed => HabitDayState.missed,
    ChainStatus.noHabits => HabitDayState.none,
  };
}

/// The shape of a day.
enum HabitDayShape {
  /// A rounded square: the chain, the heatmap, the calendar.
  square,

  /// A circle: the perfect-day dots.
  circle,
}

/// The colours a [HabitDayPainter] draws with.
@immutable
class HabitDayColors {
  /// The day done: the record's `tone.fill` (gold for perfect days).
  final Color fill;

  /// [fill] at 16 %: a done or partial calendar day, under its number.
  final Color tint;
  final Color missed;
  final Color pending;
  final Color none;

  const HabitDayColors({
    required this.fill,
    required this.tint,
    required this.missed,
    required this.pending,
    required this.none,
  });

  /// [fill] on palette [c]: inkDisabled outlines, a gold today, inkFaint
  /// dots.
  factory HabitDayColors.of(NokturnColors c, Color fill, {Color? tint}) =>
      HabitDayColors(
        fill: fill,
        tint: tint ?? fill.withValues(alpha: 0.16),
        missed: c.inkDisabled,
        pending: c.gold,
        none: c.inkFaint,
      );

  @override
  bool operator ==(Object other) =>
      other is HabitDayColors &&
      other.fill == fill &&
      other.tint == tint &&
      other.missed == missed &&
      other.pending == pending &&
      other.none == none;

  @override
  int get hashCode => Object.hash(fill, tint, missed, pending, none);
}

/// The one painter of every habit day (§4.23): the chain, the perfect-day
/// dots, the heatmap and the month calendar.
///
/// [solid] false is the calendar's look, where the day's number sits on
/// the cell: a done day is the tint with a 1.5 dp fill edge, a partial
/// one the tint in its lower half — never text on the solid fill (D19).
/// [grow] (0–1) scales the fill in from 60 %: the one cell the user just
/// changed.
class HabitDayPainter extends CustomPainter {
  HabitDayPainter({
    required this.state,
    required this.colors,
    this.shape = HabitDayShape.square,
    this.radius = 3,
    this.solid = true,
    this.grow,
  }) : super(repaint: grow);

  final HabitDayState state;
  final HabitDayColors colors;
  final HabitDayShape shape;
  final double radius;
  final bool solid;
  final Animation<double>? grow;

  /// The missed and pending outline.
  static const outline = 1.5;

  Path _shape(Rect rect) {
    if (shape == HabitDayShape.circle) return Path()..addOval(rect);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final t = (grow?.value ?? 1).clamp(0.0, 1.0);
    // The fill grows from 60 % to its size.
    final scale = 0.6 + 0.4 * t;
    final grown = Rect.fromCenter(
      center: full.center,
      width: size.width * scale,
      height: size.height * scale,
    );
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;

    switch (state) {
      case HabitDayState.done:
        if (solid) {
          canvas.drawPath(_shape(grown), Paint()..color = colors.fill);
        } else {
          canvas.drawPath(_shape(grown), Paint()..color = colors.tint);
          canvas.drawPath(
            _shape(full.deflate(outline / 2)),
            stroke(colors.fill, outline),
          );
        }
      case HabitDayState.partial:
        final path = _shape(full.deflate(0.5));
        canvas.save();
        canvas.clipPath(path);
        final half = shape == HabitDayShape.circle
            // The left half of a dot.
            ? Rect.fromLTRB(full.left, full.top, full.center.dx, full.bottom)
            // The lower half of a square.
            : Rect.fromLTRB(full.left, full.center.dy, full.right, full.bottom);
        canvas.drawRect(
          half,
          Paint()..color = solid ? colors.fill : colors.tint,
        );
        canvas.restore();
        canvas.drawPath(path, stroke(colors.fill, 1));
      case HabitDayState.missed:
        canvas.drawPath(
          _shape(full.deflate(outline / 2)),
          stroke(colors.missed, outline),
        );
      case HabitDayState.pending:
        canvas.drawPath(
          _shape(full.deflate(outline / 2)),
          stroke(colors.pending, outline),
        );
      case HabitDayState.none:
        canvas.drawCircle(full.center, 1.5, Paint()..color = colors.none);
    }
  }

  @override
  bool shouldRepaint(HabitDayPainter old) =>
      old.state != state ||
      old.colors != colors ||
      old.shape != shape ||
      old.radius != radius ||
      old.solid != solid ||
      old.grow != grow;
}

/// One habit day: [size] dp of [HabitDayPainter]. With [animate], a change
/// of [state] grows the fill in from 60 % over [Motion.standard] — only for
/// the cell the user just changed; never under reduced motion.
class HabitDayCell extends StatefulWidget {
  final HabitDayState state;
  final HabitDayColors colors;
  final double size;
  final HabitDayShape shape;
  final double radius;
  final bool animate;

  /// What a screen reader says ("4 Ekim, tamamlandı"); none leaves the
  /// cell out (its row says it).
  final String? semanticLabel;

  const HabitDayCell({
    super.key,
    required this.state,
    required this.colors,
    this.size = 12,
    this.shape = HabitDayShape.square,
    this.radius = 3,
    this.animate = false,
    this.semanticLabel,
  });

  @override
  State<HabitDayCell> createState() => _HabitDayCellState();
}

class _HabitDayCellState extends State<HabitDayCell>
    with SingleTickerProviderStateMixin {
  /// Made the first time this cell may grow ([HabitDayCell.animate]): a
  /// card's 13 other cells never do, and keep no controller or ticker
  /// (§8.8 — a tap must not set up 14 of them per card).
  AnimationController? _grow;
  CurvedAnimation? _curve;

  void _ensureGrow() {
    if (_grow != null) return;
    final grow = AnimationController(
      vsync: this,
      duration: Motion.standard,
      value: 1,
    );
    _grow = grow;
    _curve = CurvedAnimation(parent: grow, curve: Motion.enter);
  }

  @override
  void didUpdateWidget(HabitDayCell old) {
    super.didUpdateWidget(old);
    if (widget.animate &&
        old.state != widget.state &&
        !Motion.reduced(context)) {
      _ensureGrow();
      _grow!.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve?.dispose();
    _grow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = CustomPaint(
      size: Size.square(widget.size),
      painter: HabitDayPainter(
        state: widget.state,
        colors: widget.colors,
        shape: widget.shape,
        radius: widget.radius,
        // Null until the cell first grows: painted full size.
        grow: _curve,
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: cell);
    return Semantics(label: label, excludeSemantics: true, child: cell);
  }
}

/// The word a screen reader says for [state] ("tamamlandı").
String habitDayStateLabel(AppL10n l, HabitDayState state) => switch (state) {
  HabitDayState.done => l.habitsDayStateDone,
  HabitDayState.partial => l.habitsDayStatePartial,
  HabitDayState.missed => l.habitsDayStateMissed,
  HabitDayState.pending => l.habitsDayStatePending,
  HabitDayState.none => l.habitsDayStateNone,
};

/// "4 Ekim, tamamlandı".
String habitDaySemantics(AppL10n l, DateTime day, HabitDayState state) =>
    '${formatDate(day)}, ${habitDayStateLabel(l, state)}';

/// A habit's last [days] days (14 on its card, 30 in its detail): 12 dp
/// squares, 4 dp apart, radius 3 — 220 dp for 14. With [semantics] every
/// day is read out ("4 Ekim, tamamlandı"); a card leaves them out, as its
/// meta line already says how the habit goes.
class ChainRow extends StatelessWidget {
  final List<ChainDay> chain;
  final Color fill;
  final DateTime? startDate;
  final int days;
  final bool semantics;

  const ChainRow({
    super.key,
    required this.chain,
    required this.fill,
    this.startDate,
    this.days = 14,
    this.semantics = false,
  });

  static const cell = 12.0;
  static const gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final colors = HabitDayColors.of(c, fill);
    final shown = chain.length > days
        ? chain.sublist(chain.length - days)
        : chain;
    final row = Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final d in shown)
          Builder(
            builder: (context) {
              final state = habitDayStateOf(
                d.status,
                date: d.date,
                startDate: startDate,
              );
              return HabitDayCell(
                state: state,
                colors: colors,
                semanticLabel: semantics
                    ? habitDaySemantics(l, d.date, state)
                    : null,
              );
            },
          ),
      ],
    );
    return RepaintBoundary(child: row);
  }
}

/// The perfect-day chain: 10 dp dots, 6 dp apart, in rows of at most 15 —
/// gold done (perfect), half-gold partial, outlined missed, a gold ring for
/// today. [count] keeps the last ones only (14 on the hero card).
///
/// [todayDone] draws today as perfect before the server has said so (every
/// habit of the day ticked here); the dot fills in 300 ms.
class PerfectDayDots extends StatelessWidget {
  final List<ChainDay> chain;
  final int? count;
  final bool todayDone;
  final bool semantics;

  const PerfectDayDots({
    super.key,
    required this.chain,
    this.count,
    this.todayDone = false,
    this.semantics = false,
  });

  static const dot = 10.0;
  static const gap = 6.0;
  static const perRow = 15;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final colors = HabitDayColors.of(c, c.gold);
    final n = count;
    final shown = n != null && chain.length > n
        ? chain.sublist(chain.length - n)
        : chain;
    return RepaintBoundary(
      child: SizedBox(
        width: perRow * dot + (perRow - 1) * gap,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < shown.length; i++)
              Builder(
                builder: (context) {
                  final last = i == shown.length - 1;
                  var state = habitDayStateOf(shown[i].status);
                  if (last && todayDone) state = HabitDayState.done;
                  return HabitDayCell(
                    key: last ? const ValueKey('perfect-today') : null,
                    state: state,
                    colors: colors,
                    size: dot,
                    shape: HabitDayShape.circle,
                    animate: last,
                    semanticLabel: semantics
                        ? habitDaySemantics(l, shown[i].date, state)
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// The last 84 days as 12 week columns of 7 (Monday on top): 18 dp cells
/// 4 dp apart, the weekday names (Pzt, Çar, Cum) in a column of at least
/// 28 dp — 288 dp in all at normal text. Days after [today] are left blank.
class MiniHeatmap extends StatelessWidget {
  final List<ChainDay> chain;
  final Color fill;
  final DateTime today;
  final DateTime? startDate;

  const MiniHeatmap({
    super.key,
    required this.chain,
    required this.fill,
    required this.today,
    this.startDate,
  });

  static const weeks = 12;
  static const cell = 18.0;
  static const gap = 4.0;
  static const labelColumn = 28.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final colors = HabitDayColors.of(c, fill);
    final last = dateOnly(today);
    final byDay = {for (final d in chain) dateOnly(d.date): d};
    // The Monday of the first of the 12 weeks.
    final thisMonday = last.subtract(Duration(days: last.weekday - 1));
    final first = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day - 7 * (weeks - 1),
    );

    Widget weekday(int row) {
      // Monday, Wednesday and Friday are named; 1 Jan 2024 was a Monday.
      final named = row == 0 || row == 2 || row == 4;
      // Large text never cuts a name (§8.3): it is laid out whole and
      // scaled down to its row, and the column widens to the widest.
      return SizedBox(
        height: cell,
        child: named
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatWeekdayShort(DateTime(2024, 1, 1 + row)),
                  maxLines: 1,
                  style: text.labelSmall!.copyWith(
                    color: c.inkLow,
                    height: 1.2,
                  ),
                ),
              )
            : null,
      );
    }

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: labelColumn),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var row = 0; row < 7; row++) ...[
                    if (row > 0) const SizedBox(height: gap),
                    weekday(row),
                  ],
                ],
              ),
            ),
            for (var w = 0; w < weeks; w++) ...[
              if (w > 0) const SizedBox(width: gap),
              Column(
                children: [
                  for (var row = 0; row < 7; row++) ...[
                    if (row > 0) const SizedBox(height: gap),
                    Builder(
                      builder: (context) {
                        final day = DateTime(
                          first.year,
                          first.month,
                          first.day + w * 7 + row,
                        );
                        if (day.isAfter(last)) {
                          return const SizedBox.square(dimension: cell);
                        }
                        final entry = byDay[day];
                        final state = entry == null
                            ? HabitDayState.none
                            : habitDayStateOf(
                                entry.status,
                                date: day,
                                startDate: startDate,
                              );
                        return HabitDayCell(
                          state: state,
                          colors: colors,
                          size: cell,
                          radius: Radii.xs,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The key to the cells, drawn with the same shapes: done, partial,
/// missed — and today, where it shows.
class HabitDayLegend extends StatelessWidget {
  final Color fill;
  final HabitDayShape shape;
  final bool showPending;

  const HabitDayLegend({
    super.key,
    required this.fill,
    this.shape = HabitDayShape.square,
    this.showPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final colors = HabitDayColors.of(c, fill);
    Widget item(HabitDayState state, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HabitDayCell(
          state: state,
          colors: colors,
          size: 10,
          shape: shape,
          radius: 2.5,
        ),
        const SizedBox(width: 6),
        Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
      ],
    );
    return Wrap(
      spacing: Gap.lg,
      runSpacing: Gap.sm,
      children: [
        item(HabitDayState.done, l.habitsLegendDone),
        item(HabitDayState.partial, l.habitsLegendPartial),
        item(HabitDayState.missed, l.habitsLegendMissed),
        if (showPending) item(HabitDayState.pending, l.habitsLegendToday),
      ],
    );
  }
}
