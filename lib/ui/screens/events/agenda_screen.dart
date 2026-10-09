import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/sync_hint.dart';
import '../today/widgets/event_row.dart';
import '../todos/todos_screen.dart' show dayHeading;
import 'event_form.dart';
import 'event_sheet.dart';

/// One occurrence of an event: the day it takes place on.
typedef Occurrence = ({DateTime day, Event event});

/// Every occurrence of [events] within [window], by day, then all-day
/// events first and the rest by their time of day (a series by its own
/// time of day, never by its first occurrence's date: contract §3). An
/// event without `occurrences` (`/home`'s) occurs on [fallbackDay].
List<Occurrence> occurrencesIn(
  Iterable<Event> events,
  EventWindow window, {
  DateTime? fallbackDay,
}) {
  final out = <Occurrence>[];
  for (final event in events) {
    final days = event.occurrences.isNotEmpty
        ? event.occurrences
        : [?(fallbackDay ?? event.startDay)];
    for (final day in days) {
      final on = dateOnly(day);
      if (window.contains(on)) out.add((day: on, event: event));
    }
  }
  out.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    if (byDay != 0) return byDay;
    final byTime = a.event.minuteOfDay.compareTo(b.event.minuteOfDay);
    if (byTime != 0) return byTime;
    return a.event.title.compareTo(b.event.title);
  });
  return out;
}

/// The days ahead, with every event (each occurrence of a series) under
/// its day: 30 days at first, 30 more with each "Daha fazla göster", up to
/// a year (the server's limit). A tap opens the event's sheet; "Etkinlik"
/// adds one.
class AgendaScreen extends ConsumerStatefulWidget {
  /// Shown inside the Agenda tab, which has the app bar itself.
  final bool embedded;

  const AgendaScreen({super.key, this.embedded = false});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  static const _step = 30;
  static const _maxDays = 367;

  int _days = _step;

  /// What the last window showed — kept on screen while a longer window
  /// loads, so "show more" never blanks the list.
  ({EventWindow window, List<Event> events})? _shown;

  Future<void> _refresh(EventWindow window) async {
    ref.read(dataSyncProvider).refresh([eventsProvider]);
    await settleRefresh([
      ref.read(eventsProvider(window).future),
    ], minimum: const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    final today = dateOnly(ref.watch(currentDayProvider));
    final window = EventWindow.days(today, _days);
    final async = ref.watch(eventsProvider(window));
    final hidden = ref.watch(deferredDeletesProvider);
    final fetched = async.value;
    if (fetched != null) _shown = (window: window, events: fetched.data);
    final shown = _shown;

    Widget body;
    if (shown != null) {
      final events = withoutDeleted(
        shown.events,
        hidden,
        DataScope.events,
        (e) => e.id,
      );
      final occurrences = occurrencesIn(events, shown.window);
      body = Column(
        children: [
          if (async.refreshFailed && fetched != null)
            OfflineBanner(
              lastUpdated: fetched.at,
              onRetry: () =>
                  ref.read(dataSyncProvider).refresh([eventsProvider]),
            ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: c.gold,
              onRefresh: () => _refresh(window),
              child: _list(
                context,
                occurrences,
                today,
                loadingMore: fetched == null,
                moreError: fetched == null && async.hasFailed
                    ? async.error
                    : null,
              ),
            ),
          ),
        ],
      );
    } else if (async.hasFailed) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: l.agendaLoadFailed,
        subtitle: l.errCheckWifi,
        actionLabel: l.actionRetry,
        onAction: () => ref.read(dataSyncProvider).refresh([eventsProvider]),
      );
    } else {
      body = const Center(child: CircularProgressIndicator.adaptive());
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: widget.embedded ? null : AppBar(title: Text(l.titleAgenda)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => openEventForm(context, day: today),
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        icon: const Icon(Icons.add),
        label: Text(l.eventAdd),
      ),
      body: SyncHint.over(active: async.isRefetching, child: body),
    );
  }

  Widget _list(
    BuildContext context,
    List<Occurrence> occurrences,
    DateTime today, {
    required bool loadingMore,
    Object? moreError,
  }) {
    final l = context.l10n;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final byDay = <DateTime, List<Occurrence>>{};
    for (final o in occurrences) {
      byDay.putIfAbsent(o.day, () => []).add(o);
    }
    final children = <Widget>[];
    if (byDay.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 48),
          child: EmptyState(
            icon: Icons.event_available,
            title: l.agendaEmpty,
            actionLabel: l.eventNewTitle,
            onAction: () => openEventForm(context, day: today),
          ),
        ),
      );
    }
    for (final MapEntry(key: day, value: rows) in byDay.entries) {
      children
        ..add(
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                dayHeading(l, day, today),
                style: text.labelMedium!.copyWith(
                  color: day == today ? c.gold : c.inkMid,
                ),
              ),
            ),
          ),
        )
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NokturnCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 20,
                        endIndent: 20,
                        color: c.divider,
                      ),
                    EventRow(
                      key: ValueKey('event-${rows[i].event.id}-${rows[i].day}'),
                      event: rows[i].event,
                      day: rows[i].day,
                      onTap: () => showEventSheet(
                        context,
                        rows[i].event,
                        day: rows[i].day,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
    }
    if (_days < _maxDays) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Center(
            child: moreError != null
                ? _moreFailed(context, moreError)
                : loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator.adaptive(),
                  )
                : TextButton(
                    onPressed: () => setState(
                      () => _days = math.min(_days + _step, _maxDays),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(l.agendaShowMore),
                  ),
          ),
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: children,
    );
  }

  /// The longer window failed to load: the days already shown stay, with
  /// why the rest is missing and a retry in place of "Daha fazla göster".
  Widget _moreFailed(BuildContext context, Object error) {
    final l = context.l10n;
    final c = context.nok;
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Text(
            failureMessage(error, l, fallback: l.agendaLoadFailed),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: c.inkMid),
          ),
          TextButton.icon(
            onPressed: () =>
                ref.read(dataSyncProvider).refresh([eventsProvider]),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.refresh),
            label: Text(l.actionRetry),
          ),
        ],
      ),
    );
  }
}
