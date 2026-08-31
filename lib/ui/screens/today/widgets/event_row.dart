import 'package:flutter/material.dart';

import '../../../../core/formats.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/event.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_typography.dart';
import 'today_common.dart';

/// Today event row: 3dp colour bar + HH:mm (or an all-day pill) + title.
class EventRow extends StatelessWidget {
  final Event event;

  const EventRow({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(event.color, fallback: c.gold);

    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 10,
            bottom: 10,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: event.allDay || event.startAt == null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: _AllDayPill(color: color),
                        )
                      : Text(
                          formatTime(event.startAt!),
                          style: text.labelMedium!.copyWith(
                            color: c.inkMid,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    event.title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
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
