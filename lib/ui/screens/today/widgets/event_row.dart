import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/event.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';
import 'today_common.dart';

/// An event row — on Today and in the agenda: a 3 dp colour bar, the time
/// (or an all-day pill), the title, and under it the end time and the
/// place; a repeat icon for a series.
///
/// [day] is the occurrence shown: a series is placed by its occurrences, at
/// the time of day of its first one (contract §10.2). Without it, the day
/// the event starts. With [showDay] the row also says which day that is
/// ("Çar 7" over the time, the full date to a screen reader) — for rows
/// not under a heading of their own day, like Today's "BU HAFTA".
class EventRow extends StatelessWidget {
  final Event event;
  final DateTime? day;
  final VoidCallback? onTap;
  final bool showDay;

  const EventRow({
    super.key,
    required this.event,
    this.day,
    this.onTap,
    this.showDay = false,
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
    final color = hexColor(event.color, fallback: c.gold);
    final on = day ?? event.startDay;
    final end = on == null ? null : event.occurrenceEnd(on);
    final location = event.location?.trim();
    final meta = [
      if (end != null) '– ${formatTime(end)}',
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');
    final dated = showDay && on != null;
    final time = timeLabel(l, event, day);
    final timeStyle = text.labelMedium!.copyWith(
      color: c.inkMid,
      fontFeatures: tabularFigures,
    );
    final Widget clock = event.allDay || event.startAt == null
        ? _AllDayPill(color: color)
        : Text(formatTime(event.occurrenceStart(on!)), style: timeStyle);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onTap != null,
      label: l.eventSemantics(
        event.title,
        when: dated
            ? '${formatWeekday(on)}, ${formatDate(on)}, $time'
            : time,
        where: location == null || location.isEmpty ? null : location,
      ),
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        splashColor: c.gold.withValues(alpha: 0.08),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 17),
                SizedBox(
                  width: 76,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: !dated
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            style: text.bodySmall!.copyWith(color: c.inkMid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                if (event.recurring)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.repeat, size: 16, color: c.inkLow),
                  ),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDayPill extends StatelessWidget {
  final Color color;

  const _AllDayPill({required this.color});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l10n.dayAllDay,
        style: text.labelSmall!.copyWith(color: color),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
