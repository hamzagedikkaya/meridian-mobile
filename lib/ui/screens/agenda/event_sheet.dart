import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/agenda_rows.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sync_hint.dart';
import 'event_form.dart';

/// Opens [event]'s sheet (design-analysis §7.4), top to bottom: its title,
/// when ("Salı, 6 Ekim · 18:00 – 19:00", "Tüm gün"), how it repeats, where,
/// its description (read in full from `GET /events/:id`), a full-width
/// "Düzenle" and — 24 dp below — "Sil". [day] is the occurrence that was
/// tapped.
///
/// [context] is the screen's: a delete says "Geri al" there once the sheet
/// is closed, and a series' question opens from it.
Future<void> showEventSheet(
  BuildContext context,
  Event event, {
  DateTime? day,
}) {
  return showNokSheet<void>(
    context,
    builder: (_) => _EventSheet(event: event, day: day, host: context),
  );
}

class _EventSheet extends ConsumerWidget {
  final Event event;
  final DateTime? day;
  final BuildContext host;

  const _EventSheet({required this.event, this.day, required this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(eventDetailProvider(event.id));
    final full = async.value?.data;
    final shown = full ?? event;
    final tone = entityTone(shown.color, c);
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
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: event.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.sheetH,
                0,
                Insets.sheetH,
                Gap.xxl,
              ),
              child: Text(
                l.errRecordGoneBody,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ),
          ],
        ),
      );
    }

    Widget line(
      IconData icon,
      String value, {
      Color? color,
      TextStyle? style,
    }) => Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? c.inkMid),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(value, style: style ?? text.bodyMedium)),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 28,
                      margin: const EdgeInsets.only(right: Gap.md),
                      decoration: BoxDecoration(
                        color: tone.fill,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(shown.title, style: text.titleLarge),
                      ),
                    ),
                  ],
                ),
                line(
                  Icons.schedule_rounded,
                  eventWhen(l, shown, day),
                  style: text.titleSmall,
                ),
                if (recurrence != null &&
                    recurrence.preset != RecurrencePreset.none)
                  line(
                    Icons.repeat_rounded,
                    recurrenceText(l, recurrence, anchor: full?.startDay),
                  ),
                if (location.isNotEmpty) line(Icons.place_outlined, location),
                if (description.isNotEmpty)
                  line(Icons.notes_rounded, description),
                if (shown.eventType != null)
                  line(
                    Icons.label_outline_rounded,
                    l.eventType(shown.eventType!),
                  ),
                if (shown.recurring)
                  line(
                    Icons.info_outline_rounded,
                    l.eventSeriesNote,
                    style: text.bodySmall!.copyWith(color: c.inkMid),
                  ),
                if (async.isRefetching || async.isFirstLoad)
                  const Padding(
                    padding: EdgeInsets.only(top: Gap.md),
                    child: SyncHint(active: true),
                  ),
                const SizedBox(height: Gap.xxl),
              ],
            ),
          ),
        ),
        SheetActions(
          primary: PrimaryButton(
            label: l.actionEdit,
            icon: Icons.edit_outlined,
            onPressed: () async {
              final full = await _full(context, ref);
              if (full == null || !context.mounted) return;
              Navigator.of(context).pop();
              if (!host.mounted) return;
              await openEventForm(host, existing: full, occurrence: day);
            },
          ),
          destructive: TextButton(
            onPressed: () {
              // The sheet closes now; a series' question outlives it.
              Navigator.of(context).pop();
              if (!host.mounted) return;
              deleteEvent(host, ref, full ?? event, day: day);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(Hit.min),
            ),
            child: Text(l.actionDelete),
          ),
        ),
      ],
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
/// "Salı, 6 Ekim · 18:00 – 19:00", "28 Ekim – 30 Ekim · Tüm gün".
String eventWhen(AppL10n l, Event event, DateTime? day) {
  final on = day ?? event.startDay;
  if (on == null) return l.dayAllDay;
  final withYear = on.year != appToday().year;
  final date = '${formatWeekday(on)}, ${formatDate(on, withYear: withYear)}';
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

/// "Her hafta Paz · 31 Aralık tarihine kadar", "Her gün · 10 kez": how a
/// series repeats, a weekly one with the day it falls on ([anchor], its
/// first occurrence's day) — or, set on the web, the days it names ("Her
/// hafta Sal, Per") — and until when.
String recurrenceText(AppL10n l, Recurrence recurrence, {DateTime? anchor}) {
  final until = recurrence.until;
  final count = recurrence.count;
  final weekly = recurrence.preset == RecurrencePreset.custom
      ? _weeklyDays(recurrence.rule)
      : null;
  final how = recurrence.preset == RecurrencePreset.weekly && anchor != null
      ? l.recurrenceWeeklyOn(formatWeekdayShort(anchor))
      : weekly != null
      ? l.recurrenceWeeklyOn(
          // 1 January 2024 was a Monday: its week names each day.
          weekly
              .map((d) => formatWeekdayShort(DateTime(2024, 1, d)))
              .join(', '),
        )
      : l.recurrence(recurrence.preset);
  return [
    how,
    if (until != null) l.recurrenceUntil(until),
    if (until == null && count != null) l.recurrenceCount(count),
  ].join(' · ');
}

/// The weekdays (1 Monday – 7 Sunday, in order) of a plain weekly [rule]
/// on given days — `FREQ=WEEKLY;BYDAY=TU,TH`, with `UNTIL` or `COUNT` at
/// most; null for any other rule.
List<int>? _weeklyDays(String? rule) {
  const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final parts = <String, String>{};
  for (final part
      in (rule ?? '').toUpperCase().replaceFirst('RRULE:', '').split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) {
      parts[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
  }
  parts
    ..remove('UNTIL')
    ..remove('COUNT');
  if (parts['INTERVAL'] == '1') parts.remove('INTERVAL');
  if (parts['WKST'] == 'MO') parts.remove('WKST');
  final byDay = parts['BYDAY'];
  if (parts['FREQ'] != 'WEEKLY' || byDay == null || parts.length != 2) {
    return null;
  }
  final named = byDay.split(',').map((d) => days.indexOf(d.trim()) + 1);
  if (named.isEmpty || named.contains(0)) return null;
  return named.toSet().toList()..sort();
}

/// Deletes [event]. A one-off goes at once, with "Geri al". A series asks
/// first — in the "Tekrarlayan etkinlik" sheet — what to delete: from an
/// occurrence [day] after its first, that one and the rest ("Bu ve
/// sonrakileri sil", which ends the series the day before and keeps the
/// earlier ones), or the whole series (with "Geri al"). There is no
/// deleting one occurrence alone (contract §10.2, D14).
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
  final first = anchor == null
      ? null
      : Recurrence.firstDay(event.recurrenceRule, anchor);
  final from = day == null ? null : dateOnly(day);
  final canEndSeries = from != null && first != null && from.isAfter(first);
  final choice = await showNokSheet<String>(
    context,
    title: l.eventDeleteSeriesTitle,
    subtitle: event.title,
    showClose: true,
    builder: (sheet) {
      final c = sheet.nok;
      final text = Theme.of(sheet).textTheme;
      Widget hint(String value) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          Gap.xs,
          Insets.sheetH,
          0,
        ),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: text.bodySmall!.copyWith(color: c.inkMid),
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canEndSeries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
              child: PrimaryButton(
                label: l.eventDeleteFollowing(from),
                onPressed: () => Navigator.of(sheet).pop('following'),
              ),
            ),
            hint(l.eventDeleteFollowingHint(from)),
          ],
          SheetActions(
            primary: canEndSeries
                ? const SizedBox.shrink()
                : PrimaryButton(
                    label: l.eventDeleteAll,
                    destructive: true,
                    onPressed: () => Navigator.of(sheet).pop('all'),
                  ),
            destructive: canEndSeries
                ? TextButton(
                    onPressed: () => Navigator.of(sheet).pop('all'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(Hit.min),
                    ),
                    child: Text(l.eventDeleteAll),
                  )
                : null,
          ),
        ],
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'all') {
    deleteAll();
    return;
  }
  // "This and following": the series ends the day before [from].
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
        (e.details['recurrence_rule'] ?? const []).any(
          (d) => d.error == 'no_occurrences',
        )) {
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
