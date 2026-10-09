import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// A day's heading in a dated list — the Agenda, Today, Transactions
/// (design-analysis §4.6): "Bugün · 4 Ekim", "Yarın · 5 Ekim",
/// "Salı · 6 Ekim" in titleSmall inkMid ("Bugün" in gold w600), at least
/// 36 dp tall on the page background, 20 dp in from the sides.
///
/// [trailing] is an optional count or day total in `numMeta` ("−₺1.240").
/// The overdue group ([DayHeader.overdue]) is `error`, label and count, with
/// "Hepsini bugüne al" on the right when [onMoveAllToToday] is given.
///
/// Pin it over its day's rows with [DayHeader.group]. Screen readers hear it
/// as a heading.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.label,
    this.isToday = false,
    this.trailing,
    this.overdue = false,
    this.onMoveAllToToday,
  });

  /// The heading of [day]: today and tomorrow by name, other days by
  /// weekday, each with the date. [today] is the app's today.
  factory DayHeader.forDay(
    BuildContext context,
    DateTime day, {
    Key? key,
    required DateTime today,
    String? trailing,
  }) {
    final l = context.l10n;
    final delta = dayDelta(day, now: today);
    final name = switch (delta) {
      0 => l.dayToday,
      1 => l.dayTomorrow,
      -1 => l.dayYesterday,
      _ => formatWeekday(day),
    };
    return DayHeader(
      key: key,
      label: '$name · ${formatDate(day)}',
      isToday: delta == 0,
      trailing: trailing,
    );
  }

  /// The overdue group's heading: [label] ("Gecikmiş") and [count] in
  /// `error`, and "Hepsini bugüne al" when [onMoveAllToToday] is given.
  const DayHeader.overdue({
    super.key,
    required this.label,
    String? count,
    this.onMoveAllToToday,
  }) : trailing = count,
       isToday = false,
       overdue = true;

  final String label;
  final bool isToday;
  final String? trailing;
  final bool overdue;
  final VoidCallback? onMoveAllToToday;

  /// [header] pinned over [slivers] — its day's rows — while they scroll
  /// (`SliverMainAxisGroup` + `PinnedHeaderSliver`), pushed off by the next
  /// day's heading.
  static Widget group({
    Key? key,
    required DayHeader header,
    required List<Widget> slivers,
  }) => SliverMainAxisGroup(
    key: key,
    slivers: [
      PinnedHeaderSliver(child: header),
      ...slivers,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = overdue
        ? c.error
        : isToday
        ? c.gold
        : c.inkMid;
    final labelStyle = text.titleSmall!.copyWith(
      color: color,
      fontWeight: isToday || overdue ? FontWeight.w600 : null,
    );
    final trailing = this.trailing;
    final move = onMoveAllToToday;
    // Past 1.3× text the button gets a line of its own.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    final button = move == null
        ? null
        : TextButton(
            onPressed: move,
            child: Text(context.l10n.dayHeaderMoveAllToToday),
          );
    final line = Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        if (trailing != null)
          Text(
            trailing,
            style: context.nokText.numMeta.copyWith(
              color: overdue ? c.error : c.inkMid,
            ),
          ),
        if (button != null && !stacked) ...[
          const SizedBox(width: 8),
          button,
        ],
      ],
    );
    return Semantics(
      header: true,
      child: ColoredBox(
        color: c.bg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: button != null && stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      line,
                      Align(alignment: Alignment.centerRight, child: button),
                    ],
                  )
                : line,
          ),
        ),
      ),
    );
  }
}
