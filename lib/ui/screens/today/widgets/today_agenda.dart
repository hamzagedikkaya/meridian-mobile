import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/data_scope.dart';
import '../../../../data/deferred_deletes.dart';
import '../../../../data/providers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../models/home.dart';
import '../../../../theme/app_colors.dart';
import '../../../widgets/nokturn_card.dart';
import '../../../widgets/section_header.dart';
import '../../events/agenda_screen.dart';
import '../../events/event_form.dart';
import '../../events/event_sheet.dart';
import 'event_row.dart';

/// Today's agenda: the events of today, tomorrow and the rest of this week
/// (`GET /events` for that span), each occurrence of a series on its own
/// day, under "BUGÜN", "YARIN" and "BU HAFTA". At most [maxRows] rows; the
/// rest — and every later day — are on the agenda screen ("Tümü →").
///
/// Until the week's events are in (or when they cannot be had), today's
/// come from `/home`, which Today already has.
class TodayAgenda extends ConsumerWidget {
  final HomeSummary home;
  final DateTime today;
  final int maxRows;

  const TodayAgenda({
    super.key,
    required this.home,
    required this.today,
    this.maxRows = 6,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final day = dateOnly(today);
    final window = EventWindow.thisWeek(day);
    final week = ref.watch(eventsProvider(window)).value?.data;
    final hidden = ref.watch(deferredDeletesProvider);
    final events = withoutDeleted(
      week ?? home.todayEvents,
      hidden,
      DataScope.events,
      (e) => e.id,
    );
    final occurrences = week == null
        ? occurrencesIn(events, EventWindow(day, day), fallbackDay: day)
        : occurrencesIn(events, window);
    // `/home` lists at most four of today's events; it says how many there
    // are.
    final unlisted = week == null
        ? (home.todayEventsCount - occurrences.length).clamp(0, 999)
        : 0;
    final tomorrow = DateTime(day.year, day.month, day.day + 1);

    final shown = occurrences.take(maxRows).toList();
    final more = occurrences.length - shown.length + unlisted;
    final groups = <(String, List<Occurrence>)>[
      (l.dayToday, [for (final o in shown) if (o.day == day) o]),
      (l.dayTomorrow, [for (final o in shown) if (o.day == tomorrow) o]),
      (l.agendaThisWeek, [for (final o in shown) if (o.day.isAfter(tomorrow)) o]),
    ];

    Widget overline(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Semantics(
            header: true,
            child: Text(
              label.toUpperCase(),
              style: text.labelMedium!.copyWith(color: c.inkMid),
            ),
          ),
        );

    final rows = <Widget>[];
    for (final (label, items) in groups) {
      // Today's heading always shows — "nothing planned" sits under it.
      if (items.isEmpty && label != l.dayToday) continue;
      rows.add(overline(label));
      if (items.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            l.todayEmptyDay,
            style: text.bodyMedium!.copyWith(color: c.inkLow),
          ),
        ));
      }
      for (final o in items) {
        rows.add(EventRow(
          key: ValueKey('event-${o.event.id}-${isoDate(o.day)}'),
          event: o.event,
          day: o.day,
          onTap: () => showEventSheet(context, o.event, day: o.day),
          // Past tomorrow the heading ("BU HAFTA") spans several days.
          showDay: o.day.isAfter(tomorrow),
        ));
      }
    }
    if (more > 0) {
      rows.add(InkWell(
        onTap: () => context.push('/agenda'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.agendaMore(more),
                style: text.labelLarge!.copyWith(color: c.gold),
              ),
            ),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l.titleAgenda,
          trailing: IconButton(
            icon: Icon(Icons.add, color: c.gold),
            tooltip: l.eventNewTitle,
            onPressed: () => openEventForm(context, day: day),
          ),
          onSeeAll: () => context.push('/agenda'),
        ),
        NokturnCard(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }
}
