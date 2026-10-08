import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/event.dart';
import '../../../models/quick_capture.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/choice_wrap.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/slide_up_route.dart';
import 'event_sheet.dart';

/// The longest event title the server takes.
const eventTitleMaxLength = 200;

/// Opens the event form — a new event, or [existing] (in full: its
/// description and rule) to edit — as a full-screen modal. Resolves to the
/// event as the server saved it, or null when it was closed without saving.
///
/// A new one starts on [day] (today without one), or from a quick-capture
/// [suggestion]: its title, day and time. [occurrence] is the occurrence of
/// a series that was tapped, which its delete offers to end the series at.
Future<Event?> openEventForm(
  BuildContext context, {
  Event? existing,
  DateTime? day,
  EventSuggestion? suggestion,
  DateTime? occurrence,
}) {
  return Navigator.of(context, rootNavigator: true).push<Event>(
    slideUpModalRoute(
      (_) => EventFormScreen(
        existing: existing,
        day: day,
        suggestion: suggestion,
        occurrence: occurrence,
      ),
    ),
  );
}

class EventFormScreen extends ConsumerStatefulWidget {
  final Event? existing;
  final DateTime? day;
  final EventSuggestion? suggestion;
  final DateTime? occurrence;

  const EventFormScreen({
    super.key,
    this.existing,
    this.day,
    this.suggestion,
    this.occurrence,
  });

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  late final _title = TextEditingController(
    text: widget.existing?.title ?? widget.suggestion?.title,
  );
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _description =
      TextEditingController(text: widget.existing?.description);
  final _titleFocus = FocusNode();

  late bool _allDay;
  late DateTime _start;
  DateTime? _end;
  late String _type = widget.existing?.eventType ?? 'personal';
  String? _color;

  /// The rule as stored; kept as it is unless the repetition is changed.
  String? _storedRule;
  late RecurrencePreset _preset;
  DateTime? _until;

  /// How many times a stored rule occurs (`COUNT`, from another client):
  /// kept when the rule is rebuilt, until another end is chosen.
  int? _count;

  /// Whether the repetition was changed here: only then is a rule built
  /// from [_preset] and [_until] (a stored one may say the same thing in
  /// other words — its `UNTIL` as a UTC instant, say).
  bool _ruleTouched = false;

  bool _saving = false;
  String? _titleError;
  String? _startError;
  String? _endError;
  String? _ruleError;
  String? _formError;

  /// Whether a save was tried: the end is checked live after that.
  bool _tried = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final suggestion = widget.suggestion;
    if (existing != null) {
      _allDay = existing.allDay;
      _start = existing.startAt ?? _defaultStart(existing.startDay);
      _end = existing.endAt;
      _storedRule = existing.recurrenceRule;
      final recurrence = Recurrence.parse(
        _storedRule,
        anchor: _start,
        utcOffset: ref.read(accountUtcOffsetProvider),
      );
      _preset = recurrence.preset;
      _until = recurrence.until;
      _count = recurrence.count;
    } else {
      _allDay = suggestion?.allDay ?? false;
      _start = suggestion?.startAt ??
          (suggestion != null
              ? _defaultStart(suggestion.date, morning: true)
              : _defaultStart(widget.day));
      _end = _allDay ? null : _start.add(const Duration(hours: 1));
      _preset = RecurrencePreset.none;
    }
    _title.addListener(() => setState(() => _titleError = null));
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  DateTime get _today => ref.read(homeProvider).value?.data.today ??
      ref.read<DateTime>(currentDayProvider);

  /// A new event starts at the next full hour today, or at 09:00 on another
  /// day ([morning]: always 09:00).
  DateTime _defaultStart(DateTime? day, {bool morning = false}) {
    final today = _today;
    final on = dateOnly(day ?? today);
    if (!morning && on == dateOnly(today)) {
      final now = ref.read(clockProvider)();
      final next = DateTime(on.year, on.month, on.day, now.hour + 1);
      // Past 23:00 the next full hour is tomorrow: stay on the day asked.
      if (next.day == on.day) return next;
      return DateTime(on.year, on.month, on.day, 23);
    }
    return DateTime(on.year, on.month, on.day, 9);
  }

  String? get _rule {
    if (!_ruleTouched) return _storedRule;
    if (_preset == RecurrencePreset.custom) return _storedRule;
    return Recurrence.ruleFor(_preset, until: _until, count: _count);
  }

  EventInput _input(String color) => EventInput(
        title: _title.text,
        start: _start,
        end: _end,
        allDay: _allDay,
        location: _location.text,
        description: _description.text,
        color: color,
        eventType: _type,
        recurrenceRule: _rule,
      );

  bool _dirty(String color) {
    final existing = widget.existing;
    if (existing != null) return _input(color).changesFrom(existing).isNotEmpty;
    return (_title.text.trim().isNotEmpty &&
            _title.text.trim() != (widget.suggestion?.title ?? '')) ||
        _location.text.trim().isNotEmpty ||
        _description.text.trim().isNotEmpty;
  }

  /// The end's problem, if any: it must come after the start — on a later
  /// time, or for an all-day event on the same day or later.
  String? _endProblem(AppL10n l) {
    final end = _end;
    if (end == null) return null;
    if (_allDay) {
      return dateOnly(end).isBefore(dateOnly(_start))
          ? l.eventEndBeforeStart
          : null;
    }
    return end.isAfter(_start) ? null : l.eventEndBeforeStart;
  }

  void _afterTimesChanged() {
    if (_tried) _endError = _endProblem(context.l10n);
    _startError = null;
  }

  Future<DateTime?> _pickDay(DateTime initial, {DateTime? first}) {
    final today = _today;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(today.year - 5),
      lastDate: DateTime(today.year + 10),
    );
  }

  Future<TimeOfDay?> _pickTime(DateTime initial) => showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );

  /// A new start day keeps the time, and moves the end with it so the
  /// event keeps its length. A weekly, monthly or yearly series follows its
  /// first day, so its rule is rebuilt for the new one.
  Future<void> _pickStartDay() async {
    final picked = await _pickDay(_start);
    if (picked == null || !mounted) return;
    final moved = DateTime(
        picked.year, picked.month, picked.day, _start.hour, _start.minute);
    setState(() {
      final shift = moved.difference(_start);
      _start = moved;
      if (_end != null) _end = _end!.add(shift);
      if (_preset == RecurrencePreset.weekly ||
          _preset == RecurrencePreset.monthly ||
          _preset == RecurrencePreset.yearly) {
        _ruleTouched = true;
      }
      _afterTimesChanged();
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await _pickTime(_start);
    if (picked == null || !mounted) return;
    final moved = DateTime(
        _start.year, _start.month, _start.day, picked.hour, picked.minute);
    setState(() {
      final shift = moved.difference(_start);
      _start = moved;
      if (_end != null) _end = _end!.add(shift);
      _afterTimesChanged();
    });
  }

  Future<void> _pickEndDay() async {
    final end = _end ?? _start;
    final picked = await _pickDay(end, first: dateOnly(_start));
    if (picked == null || !mounted) return;
    setState(() {
      _end = DateTime(picked.year, picked.month, picked.day, end.hour, end.minute);
      _afterTimesChanged();
    });
  }

  Future<void> _pickEndTime() async {
    final end = _end ?? _start.add(const Duration(hours: 1));
    final picked = await _pickTime(end);
    if (picked == null || !mounted) return;
    setState(() {
      _end = DateTime(end.year, end.month, end.day, picked.hour, picked.minute);
      _afterTimesChanged();
    });
  }

  void _addEnd() => setState(() {
        _end = _allDay ? _start : _start.add(const Duration(hours: 1));
        _afterTimesChanged();
      });

  Future<void> _pickUntil() async {
    final picked = await _pickDay(
      _until ?? dateOnly(_start).add(const Duration(days: 30)),
      first: dateOnly(_start),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _until = dateOnly(picked);
      _count = null;
      _ruleTouched = true;
      _ruleError = null;
    });
  }

  Future<void> _save(String color) async {
    final l = context.l10n;
    if (_saving) return;
    _tried = true;
    final titleMissing = _title.text.trim().isEmpty;
    final endProblem = _endProblem(l);
    if (titleMissing || endProblem != null) {
      Haptics.danger();
      setState(() {
        _titleError = titleMissing ? l.eventTitleRequired : null;
        _endError = endProblem;
      });
      if (titleMissing) _titleFocus.requestFocus();
      return;
    }
    final input = _input(color);
    final existing = widget.existing;
    if (existing != null && input.changesFrom(existing).isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
      _ruleError = null;
    });
    try {
      // The repository reports the write: Today and the agendas refresh
      // from it, even if this form is closed before the answer.
      final repo = ref.read(repositoryProvider);
      final saved = existing == null
          ? await repo.createEvent(input)
          : await repo.updateEvent(existing, input);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(saved);
      showAppSnack(
        context,
        existing == null ? l.eventCreated(saved.title) : l.eventUpdated,
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      String? field(String name) =>
          refusal?.param == name ? refusal!.localized(l) : refusal?.fieldMessage(l, name);
      final titleError = field('title');
      final startError = field('start_at');
      final endError = field('end_at');
      final ruleError = field('recurrence_rule');
      final placed = titleError != null ||
          startError != null ||
          endError != null ||
          ruleError != null;
      setState(() {
        _saving = false;
        _titleError = titleError;
        _startError = startError;
        _endError = endError;
        _ruleError = ruleError;
        _formError =
            placed ? null : failureMessage(e, l, fallback: l.eventSaveFailed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final existing = widget.existing;
    final color = _color ?? existing?.color ?? recordSwatches.first;
    final today = _today;

    String dayLabel(DateTime day) =>
        '${formatWeekdayShort(day)} ${formatDate(day, withYear: day.year != today.year)}';

    // The label over its day and time, so both stay whole at large text.
    Widget pickers({
      required String label,
      required DateTime value,
      required VoidCallback onDay,
      required VoidCallback onTime,
      Widget? trailing,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.bodyMedium!.copyWith(color: c.inkMid)),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _PickerButton(
                        icon: Icons.calendar_today_outlined,
                        label: dayLabel(value),
                        onTap: onDay,
                      ),
                      if (!_allDay)
                        _PickerButton(
                          icon: Icons.schedule,
                          label: formatTime(value),
                          onTap: onTime,
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ],
        );

    final presets = [
      RecurrencePreset.none,
      RecurrencePreset.daily,
      RecurrencePreset.weekdays,
      RecurrencePreset.weekly,
      RecurrencePreset.monthly,
      RecurrencePreset.yearly,
      if (_preset == RecurrencePreset.custom) RecurrencePreset.custom,
    ];

    return FormScaffold(
      title: _isEdit ? l.eventEditTitle : l.eventNewTitle,
      actionLabel: l.actionSave,
      busy: _saving,
      dirty: _dirty(color),
      onAction: () => _save(color),
      footer: existing == null
          ? null
          : TextButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      final host =
                          Navigator.of(context, rootNavigator: true).context;
                      Navigator.of(context).pop();
                      deleteEvent(host, ref, existing, day: widget.occurrence);
                    },
              style: TextButton.styleFrom(
                foregroundColor: c.error,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.actionDelete),
            ),
      children: [
        if (existing?.recurring ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.goldContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.repeat, size: 18, color: c.onGoldContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.eventSeriesFormNote,
                      style: text.bodySmall!
                          .copyWith(color: c.onGoldContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          autofocus: !_isEdit && (widget.suggestion?.title.isEmpty ?? true),
          maxLength: eventTitleMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.eventFieldTitle,
            errorText: _titleError,
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l.dayAllDay),
          value: _allDay,
          onChanged: (value) => setState(() {
            _allDay = value;
            if (_end != null && !value && !_end!.isAfter(_start)) {
              _end = _start.add(const Duration(hours: 1));
            }
            _afterTimesChanged();
          }),
        ),
        pickers(
          label: l.eventStarts,
          value: _start,
          onDay: _pickStartDay,
          onTime: _pickStartTime,
        ),
        if (_startError != null) _error(context, _startError!),
        const SizedBox(height: 12),
        if (_end == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.eventEnds,
                  style: text.bodyMedium!.copyWith(color: c.inkMid)),
              TextButton.icon(
                onPressed: _addEnd,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.eventAddEnd),
              ),
            ],
          )
        else
          pickers(
            label: l.eventEnds,
            value: _end!,
            onDay: _pickEndDay,
            onTime: _pickEndTime,
            trailing: IconButton(
              tooltip: l.eventRemoveEnd,
              onPressed: () => setState(() {
                _end = null;
                _endError = null;
              }),
              icon: Icon(Icons.close, size: 18, color: c.inkMid),
            ),
          ),
        if (_endError != null) _error(context, _endError!),
        const SizedBox(height: 20),
        FormLabel(l.eventRepeat),
        ChoiceWrap<RecurrencePreset>(
          choices: [
            for (final preset in presets) Choice(preset, l.recurrence(preset)),
          ],
          selected: _preset,
          onChanged: (preset) => setState(() {
            _preset = preset;
            _ruleTouched = true;
            _ruleError = null;
            if (preset == RecurrencePreset.none) {
              _until = null;
              _count = null;
            }
          }),
        ),
        if (_preset != RecurrencePreset.none &&
            _preset != RecurrencePreset.custom) ...[
          const SizedBox(height: 8),
          FormLabel(l.eventRepeatEnds),
          ChoiceWrap<_RepeatEnd>(
            choices: [
              Choice(_RepeatEnd.never, l.eventRepeatForever),
              if (_count != null)
                Choice(_RepeatEnd.count, l.recurrenceCount(_count!)),
              Choice(
                _RepeatEnd.until,
                _until == null ? l.todoDuePick : l.recurrenceUntil(_until!),
                icon: Icons.event_outlined,
              ),
            ],
            selected: _until != null
                ? _RepeatEnd.until
                : _count != null
                ? _RepeatEnd.count
                : _RepeatEnd.never,
            onChanged: (end) {
              switch (end) {
                case _RepeatEnd.until:
                  _pickUntil();
                case _RepeatEnd.never:
                  setState(() {
                    _until = null;
                    _count = null;
                    _ruleTouched = true;
                  });
                case _RepeatEnd.count:
                  break;
              }
            },
          ),
          if (_until != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickUntil,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text(l.todoDuePick),
              ),
            ),
        ],
        if (_preset == RecurrencePreset.custom && _storedRule != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              recurrenceText(
                l,
                Recurrence.parse(
                  _storedRule,
                  anchor: _start,
                  utcOffset: ref.read(accountUtcOffsetProvider),
                ),
              ),
              style: text.bodySmall!.copyWith(color: c.inkLow),
            ),
          ),
        if (_ruleError != null) _error(context, _ruleError!),
        const SizedBox(height: 20),
        TextField(
          controller: _location,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l.eventLocation,
            prefixIcon: const Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l.eventDescription,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        FormLabel(l.eventFieldType),
        ChoiceWrap<String>(
          choices: [
            for (final type in eventTypes) Choice(type, l.eventType(type)),
          ],
          selected: _type,
          onChanged: (type) => setState(() => _type = type),
        ),
        const SizedBox(height: 20),
        FormLabel(l.eventColor),
        ColorSwatchRow(
          selected: color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
        if (_formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _formError!,
                style: text.bodyMedium!.copyWith(color: c.error),
              ),
            ),
          ),
      ],
    );
  }

  Widget _error(BuildContext context, String message) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: c.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(message,
                  style: text.bodySmall!.copyWith(color: c.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date or time a tap changes: a 48 dp target.
class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: c.inkMid),
                    const SizedBox(width: 6),
                    Flexible(child: Text(label, style: text.titleSmall)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a series ends, in the form: never, after a stored `COUNT`, or on a
/// day.
enum _RepeatEnd { never, count, until }
