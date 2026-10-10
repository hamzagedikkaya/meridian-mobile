import 'package:flutter/material.dart';
import '../../../../models/event.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/entity_color.dart';

/// Parse a "#B8860B" / "#b8860b" hex string into a Color (opaque).
/// New code draws record colours through `entityTone` (theme/entity_color).
Color hexColor(String hex, {Color fallback = const Color(0xFF6B8FA0)}) =>
    parseEntityHex(hex, fallback: fallback);

/// [child] growing and shrinking with its content in [duration]
/// (`easeOutCubic`, from the top) — or simply taking its size under reduced
/// motion, where an `AnimatedSize` could not take zero time.
Widget todayResize(
  BuildContext context, {
  required Widget child,
  Duration duration = Motion.collapse,
}) {
  if (Motion.reduced(context)) return child;
  return AnimatedSize(
    duration: duration,
    curve: Motion.enter,
    alignment: Alignment.topCenter,
    child: child,
  );
}

/// When [event]'s occurrence on [day] ends: from its duration, else from its
/// own start and end, else its start (an event with no end is over once it
/// has begun).
DateTime occurrenceEndOf(Event event, DateTime day) {
  final start = event.occurrenceStart(day);
  final end = event.occurrenceEnd(day);
  if (end != null) return end;
  final from = event.startAt;
  final to = event.endAt;
  if (from != null && to != null && to.isAfter(from)) {
    return start.add(to.difference(from));
  }
  return start;
}

/// Todo priority → 3dp left edge bar color (design §4.3).
Color priorityEdgeColor(NokturnColors c, String priority) => switch (priority) {
      'urgent' => c.error,
      'high' => c.warning,
      'medium' => c.goldDim,
      _ => Colors.transparent,
    };
