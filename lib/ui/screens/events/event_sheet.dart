import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/sync_hint.dart';
import '../today/widgets/event_row.dart';
import '../today/widgets/today_common.dart';
import 'event_form.dart';

/// Opens [event]'s sheet: when and where, how it repeats, its description
/// (read in full from `GET /events/:id`), and "Düzenle" / "Sil". [day] is
/// the occurrence that was tapped.
Future<void> showEventSheet(
  BuildContext context,
  Event event, {
  DateTime? day,
}) {
  Haptics.tick();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _EventSheet(event: event, day: day),
  );
}

class _EventSheet extends ConsumerWidget {
  final Event event;
  final DateTime? day;

  const _EventSheet({required this.event, this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(eventDetailProvider(event.id));
    final full = async.value?.data;
    final shown = full ?? event;
    final color = hexColor(shown.color, fallback: c.gold);
    final offset = ref.watch(accountUtcOffsetProvider);
    final recurrence = full == null
        ? null
        : Recurrence.parse(
            full.recurrenceRule,
            anchor: full.startAt,
            utcOffset: offset,
          );
    final location = shown.location?.trim() ?? '';
    final description = full?.description?.trim() ?? '';

    if (async.isGone) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                l.errRecordGoneBody,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ],
          ),
        ),
      );
    }

    Widget line(IconData icon, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color ?? c.inkMid),
              const SizedBox(width: 12),
              Expanded(child: Text(value, style: text.bodyMedium)),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 28,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(child: Text(shown.title, style: text.titleLarge)),
              ],
            ),
            line(Icons.schedule, eventWhen(l, shown, day)),
            if (recurrence != null && recurrence.preset != RecurrencePreset.none)
              line(Icons.repeat, recurrenceText(l, recurrence)),
            if (location.isNotEmpty) line(Icons.place_outlined, location),
            if (shown.eventType != null)
              line(Icons.label_outline, l.eventType(shown.eventType!)),
            if (description.isNotEmpty) line(Icons.notes, description),
            if (shown.recurring)
              line(Icons.info_outline, l.eventSeriesNote, color: c.gold),
            if (async.isRefetching || async.isFirstLoad)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: SyncHint(active: true),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final full = await _full(context, ref);
                if (full == null || !context.mounted) return;
                Navigator.of(context).pop();
                await openEventForm(context, existing: full, occurrence: day);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.actionEdit),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                // The sheet closes now; a series' question outlives it.
                final host = Navigator.of(context, rootNavigator: true).context;
                Navigator.of(context).pop();
                deleteEvent(host, ref, full ?? event, day: day);
              },
              style: TextButton.styleFrom(
                foregroundColor: c.error,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.actionDelete),
            ),
          ],
        ),
      ),
    );
  }

  /// The event in full — the form edits its description and rule — waiting
  /// for it when it is still on its way; null (with the reason shown) when
  /// it cannot be had.
  Future<Event?> _full(BuildContext context, WidgetRef ref) async {
    final shown = ref.read(eventDetailProvider(event.id)).value?.data;
    if (shown != null) return shown;
    final l = context.l10n;
    try {
      return (await ref.read(eventDetailProvider(event.id).future)).data;
    } catch (e) {
      if (context.mounted) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.eventLoadFailed),
          isError: true,
        );
      }
      return null;
    }
  }
}

/// When [event] takes place on [day] (its start's day without one):
/// "Salı 6 Ekim · 18:00 – 19:00", "28 Ekim – 30 Ekim · Tüm gün".
String eventWhen(AppL10n l, Event event, DateTime? day) {
  final on = day ?? event.startDay;
  if (on == null) return l.dayAllDay;
  final withYear = on.year != appToday().year;
  final date = '${formatWeekday(on)} ${formatDate(on, withYear: withYear)}';
  if (event.allDay) {
    final start = event.startDay;
    final end = event.endDay;
    // A multi-day event: its span, moved to the occurrence shown.
    if (start != null && end != null && end.isAfter(start)) {
      final last = on.add(end.difference(start));
      return '${formatDate(on, withYear: withYear)} – '
          '${formatDate(DateTime(last.year, last.month, last.day), withYear: withYear)}'
          ' · ${l.dayAllDay}';
    }
    return '$date · ${l.dayAllDay}';
  }
  return '$date · ${EventRow.timeLabel(l, event, on)}';
}

/// "Her hafta · 31 Aralık tarihine kadar", "Her gün · 10 kez".
String recurrenceText(AppL10n l, Recurrence recurrence) {
  final until = recurrence.until;
  final count = recurrence.count;
  return [
    l.recurrence(recurrence.preset),
    if (until != null) l.recurrenceUntil(until),
    if (until == null && count != null) l.recurrenceCount(count),
  ].join(' · ');
}

/// Deletes [event]. A one-off goes at once, with "Geri al". A series asks
/// first — in a sheet — what to delete: the whole series (with "Geri al"),
/// or, from an occurrence [day] after its first, that one and the rest,
/// which ends the series the day before and keeps the earlier ones
/// (contract §10.2). There is no deleting one occurrence alone.
Future<void> deleteEvent(
  BuildContext context,
  WidgetRef ref,
  Event event, {
  DateTime? day,
}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final deletes = ref.read(deferredDeletesProvider.notifier);
  void deleteAll() => deleteWithUndo(
        context,
        deletes,
        record: (scope: DataScope.events, id: event.id),
        message: l.eventDeleted(event.title),
        send: () => repo.deleteEvent(event.id),
        failedMessage: l.eventDeleteFailed,
      );
  if (!event.recurring) {
    deleteAll();
    return;
  }
  // Its first occurrence, which may come after its start's day ("Hafta
  // içi her gün" begun on a Sunday): from there it can only go whole.
  final anchor = event.startDay;
  final first =
      anchor == null ? null : Recurrence.firstDay(event.recurrenceRule, anchor);
  final from = day == null ? null : dateOnly(day);
  final canEndSeries = from != null && first != null && from.isAfter(first);
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (sheet) {
      final c = sheet.nok;
      final text = Theme.of(sheet).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(l.eventDeleteSeriesTitle, style: text.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                event.title,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ),
            if (canEndSeries)
              ListTile(
                leading: const Icon(Icons.last_page),
                title: Text(l.eventDeleteFollowing(from)),
                subtitle: Text(l.eventDeleteFollowingHint(from)),
                onTap: () => Navigator.of(sheet).pop('following'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.error),
              title: Text(l.eventDeleteAll, style: TextStyle(color: c.error)),
              subtitle: Text(l.eventDeleteAllHint),
              onTap: () => Navigator.of(sheet).pop('all'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.actionCancel),
              onTap: () => Navigator.of(sheet).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'all') {
    deleteAll();
    return;
  }
  // "This and following": the series ends the day before [from].
  Haptics.tick();
  try {
    var full = event;
    if (full.recurrenceRule == null) {
      full = await repo.fetchEvent(event.id);
      final start = full.startDay;
      if (start != null &&
          !from!.isAfter(Recurrence.firstDay(full.recurrenceRule, start))) {
        // Its rule, read only now, says [from] is the first occurrence.
        if (context.mounted) deleteAll();
        return;
      }
    }
    final lastDay = DateTime(from!.year, from.month, from.day - 1);
    await repo.endSeries(full, lastDay);
    if (!context.mounted) return;
    showAppSnack(context, l.eventSeriesEnded(event.title));
  } catch (e) {
    if (!context.mounted) return;
    // Nothing would be left before [from] — it was the first occurrence
    // after all (a rule this app cannot read ahead): the whole series goes,
    // with "Geri al" (contract §10.2).
    if (e is ApiException &&
        (e.details['recurrence_rule'] ?? const [])
            .any((d) => d.error == 'no_occurrences')) {
      deleteAll();
      return;
    }
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.eventDeleteFailed),
      isError: true,
    );
  }
}
