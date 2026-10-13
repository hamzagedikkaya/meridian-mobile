import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/confirm_dialog.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/nok_chip.dart';
import '../../../ui/widgets/picker_sheet.dart';
import '../../../ui/widgets/primary_button.dart';
import '../../../ui/widgets/skeletons.dart';
import '../../../ui/widgets/slide_up_route.dart';
import '../../../ui/widgets/sync_hint.dart';
import 'widgets/energy_bars.dart';
import 'widgets/mood.dart';

/// Weather is free text on the server (the web app has a plain input), so the
/// picker stores the label in the user's own language, like a tag.
const _weatherOptions = <(String, IconData)>[
  ('sunny', Icons.wb_sunny_outlined),
  ('partly_cloudy', Icons.wb_cloudy_outlined),
  ('cloudy', Icons.cloud_outlined),
  ('rainy', Icons.water_drop_outlined),
  ('snowy', Icons.ac_unit_rounded),
];

/// The icon of a weather label picked in the editor; a cloud for any other
/// text (typed on the web).
IconData journalWeatherIcon(String? weather, AppL10n l) {
  for (final (key, icon) in _weatherOptions) {
    if (l.weatherLabel(key) == weather) return icon;
  }
  return Icons.wb_cloudy_outlined;
}

/// Opens the full-screen journal editor as a root-navigator modal: a new
/// entry, or [entry] to edit — the full entry (`GET /journal_entries/:id`);
/// given a list item, the editor loads the full one first. Completes with
/// true once something was saved (an entry deleted elsewhere meanwhile may
/// have been saved as a new one). [initialMood] starts a new entry with that
/// mood picked (Today's mood buttons), on today.
///
/// What the editor says once it has closed ("Kayıt eklendi") floats over
/// the FAB or capture bar of the screen the user is on then, wherever it
/// was opened from (a tab, the "Günlüğe yaz" shortcut): the app's
/// snackbars follow what is on view ([SnackClearance]).
Future<bool?> openJournalEditor(
  BuildContext context, {
  JournalEntry? entry,
  String? initialMood,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    slideUpModalRoute(
      (_) => JournalEditorScreen(
        editEntry: entry,
        initialMood: initialMood,
      ),
    ),
  );
}

/// Deletes entry [id] and drops the draft of an edit of it: the entry was
/// thrown away on purpose, and no screen could bring that draft back.
Future<void> deleteJournalEntryAndDraft(
  MeridianRepository repo,
  DraftStore drafts,
  int id,
) async {
  await repo.deleteJournalEntry(id);
  try {
    await drafts.clear(entryId: id);
  } catch (_) {
    // Storage hiccup: the entry is deleted either way.
  }
}

/// [now] as the account's wall clock — how the app reads the server's
/// datetimes (`parseDateTime`): in the zone of [offset], or the phone's
/// own while the account's is not known.
DateTime accountWallClock(DateTime now, Duration? offset) {
  if (offset == null) return now.toLocal();
  final t = now.toUtc().add(offset);
  return DateTime(
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
  );
}

/// How far the phone's clock and the server's may disagree when an entry's
/// `created_at` is held against the moment the app sent it.
const journalClockSkew = Duration(minutes: 2);

/// Whether [e] — a journal list item — is the entry [input] creates, sent
/// at [sentAt] (the account's wall clock, as `created_at` is read): created
/// no earlier (an older look-alike is not it), on the
/// same day, with the same title, mood, energy, weather, tags and
/// gratitude (or none), and its body, whole or as far as the list's
/// 200-character preview shows it.
bool journalEntryMatches(
  JournalEntry e,
  JournalInput input, {
  DateTime? sentAt,
}) {
  final created = e.createdAt;
  if (sentAt != null &&
      created != null &&
      created.isBefore(sentAt.subtract(journalClockSkew))) {
    return false;
  }
  if (isoDate(e.date) != isoDate(input.date)) return false;
  if ((e.title ?? '').trim() != (input.title ?? '').trim()) return false;
  if (e.mood != input.mood) return false;
  if (e.energyLevel != input.energyLevel) return false;
  if ((e.weather ?? '') != (input.weather ?? '')) return false;
  if (e.hasGratitude != (input.gratitude ?? '').trim().isNotEmpty) {
    return false;
  }
  Set<String> tagSet(Iterable<String> tags) => {
    for (final t in tags)
      if (t.trim().isNotEmpty) t.trim(),
  };
  final tags = tagSet(input.tags);
  final listed = tagSet(e.tags);
  if (tags.length != listed.length || !tags.containsAll(listed)) return false;
  final body = normalizedBody(input.bodyText ?? '');
  final shown = normalizedBody(e.bodyText ?? e.bodyPlain ?? '');
  if (shown == body) return true;
  return shown.endsWith('...') &&
      body.startsWith(shown.substring(0, shown.length - 3).trimRight());
}

/// How often what is typed is put aside as a draft.
const journalDraftInterval = Duration(seconds: 5);

/// The journal editor (design-research §5.6). Nothing typed is ever lost:
///
/// * an edit starts from the entry's whole body (`body_text`), paragraphs
///   and line breaks included, and sends it back only when its text
///   changed — so a web entry keeps its formatting through an edit of its
///   title, mood or tags, and a changed text over web formatting is saved
///   only once the user agrees to drop it;
/// * what is typed is kept as an encrypted draft — one for the new entry,
///   one per entry edited — every few seconds, when the app goes to the
///   background, and when the editor closes; it comes back the next time,
///   with a way to discard it, and is cleared once saved. A draft brings
///   back only what was changed in it, and says so when the entry was
///   changed elsewhere since;
/// * an entry deleted elsewhere while it is being edited keeps the editor
///   and its text, which can be saved as a new entry.
///
/// Its layout (design-analysis §7.12): the date chip as the title and a
/// quiet "Taslak 12:41" stamp; the title, an inline five-mood strip that
/// folds into a chip once picked, the body in the reading style; and the
/// accessory bar — Ruh hali · Enerji · Etiket · Minnet · Hava and "Kaydet"
/// — at the bottom of the body, so it rides the keyboard. X and the back
/// gesture keep the draft and close; they never ask and never throw away.
class JournalEditorScreen extends ConsumerStatefulWidget {
  final JournalEntry? editEntry;

  /// A new entry's mood, already picked (Today's mood buttons).
  final String? initialMood;

  const JournalEditorScreen({
    super.key,
    this.editEntry,
    this.initialMood,
  });

  @override
  ConsumerState<JournalEditorScreen> createState() =>
      _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _gratitudeCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _bodyFocus = FocusNode();
  final _tagsFocus = FocusNode();
  final _gratitudeFocus = FocusNode();

  /// The optional sections, scrolled into view when the accessory bar
  /// reveals them.
  final _moodKey = GlobalKey();
  final _energyKey = GlobalKey();
  final _tagsKey = GlobalKey();
  final _gratitudeKey = GlobalKey();

  late DateTime _date;
  String? _mood;
  String? _weather;
  int _energy = 0;
  bool _gratitudeOn = false;
  bool _tagsOn = false;
  bool _energyOn = false;

  /// The five-mood strip is open (it folds into a chip once a mood is
  /// picked, or skipped).
  bool _moodOpen = false;
  Timer? _foldTimer;
  bool _saving = false;

  /// When what is typed was last put aside as a draft — the app bar stamp.
  DateTime? _draftSavedAt;
  String? _lastDraft;

  /// Saved: nothing is put aside as a draft any more.
  bool _saved = false;

  /// The full entry being edited; null for a new one, or while it loads.
  JournalEntry? _entry;

  /// The full entry is still being fetched (an edit opened from a list
  /// item), or could not be.
  bool _loadingFull = false;
  Object? _loadError;

  /// The entry to edit was deleted elsewhere before it could load, and no
  /// draft of it was kept here: there is nothing to show.
  bool _loadGone = false;

  /// A new entry's save went out but its answer was lost (a timeout): the
  /// server may have it. What was sent, and when — kept in the draft too,
  /// so the journal is checked before it is sent again, in this editor or
  /// one that brings the draft back.
  ({Map<String, Object?> fields, DateTime at})? _sent;

  /// The fields last put aside: what a draft written once the editor has
  /// closed holds.
  Map<String, Object?>? _lastFields;

  /// The accessory bar's content (inside its safe area): the editor's own
  /// snackbars float above it.
  final _barKey = GlobalKey();

  /// A draft from an earlier session was put in the fields.
  bool _draftRestored = false;

  /// The restored draft was written before the entry last changed
  /// elsewhere (its `updated_at` moved).
  bool _draftStale = false;

  /// The entry was deleted elsewhere while being edited: the text stays,
  /// and Save makes it a new entry.
  bool _gone = false;

  /// What the fields held when the editor opened (the entry, or blank):
  /// the draft is what differs from it.
  String? _baseline;

  Timer? _draftTimer;
  late final DraftStore _drafts;
  late final AppLifecycleListener _lifecycle;

  bool get _isEditing => widget.editEntry != null && !_gone;

  /// Where the draft is kept: the entry's own, or the new entry's (also
  /// once the entry is gone, when that one is free).
  late int? _draftKey = widget.editEntry?.id;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(draftStoreProvider);
    // Put aside on the way to the background: the app may not come back.
    _lifecycle = AppLifecycleListener(
      onInactive: _saveDraft,
      onHide: _saveDraft,
      onPause: _saveDraft,
    );
    final e = widget.editEntry;
    if (e == null) {
      // The account's today (see data/current_day.dart).
      _date = ref.read(currentDayProvider);
      _start(showMood: true);
      // Picked on Today: a change from the blank baseline, so it is kept.
      if (widget.initialMood != null) _mood = widget.initialMood;
    } else if (e.isFull) {
      _fill(e);
      _start();
    } else {
      _date = e.date;
      _loadingFull = true;
      unawaited(_loadFull(e.id));
    }
  }

  /// Fills the fields from [e], the full entry.
  void _fill(JournalEntry e) {
    _entry = e;
    _date = e.date;
    _titleCtrl.text = e.title ?? '';
    _bodyCtrl.text = e.editableBody;
    _mood = e.mood;
    _weather = e.weather;
    _energy = e.energyLevel ?? 0;
    _gratitudeCtrl.text = e.gratitude ?? '';
    _gratitudeOn = (e.gratitude ?? '').isNotEmpty;
    _tagsCtrl.text = e.tags.join(', ');
    _tagsOn = e.tags.isNotEmpty;
    _energyOn = _energy > 0;
  }

  Future<void> _loadFull(int id, {bool again = false}) async {
    try {
      final provider = journalEntryProvider(id);
      final full =
          (await (again
                  ? ref.refresh(provider.future)
                  : ref.read(provider.future)))
              .data;
      if (!mounted) return;
      setState(() {
        _fill(full);
        _loadingFull = false;
      });
      _start();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiErrorKind.notFound) return _loadedGone(id);
      setState(() => _loadError = e);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _retryLoad() {
    final id = widget.editEntry?.id;
    if (id == null) return;
    setState(() => _loadError = null);
    unawaited(_loadFull(id, again: true));
  }

  /// The entry was deleted elsewhere before it loaded. A draft of an edit of
  /// it comes back as a new entry, to be saved as one; with none, there is
  /// nothing to edit.
  Future<void> _loadedGone(int id) async {
    String? draft;
    try {
      draft = await _drafts.read(entryId: id);
    } catch (_) {
      // Storage hiccup: as if there were none.
    }
    if (!mounted) return;
    if (draft == null) {
      setState(() => _loadGone = true);
      return;
    }
    Haptics.reject();
    setState(() {
      _loadingFull = false;
      _gone = true;
      _entry = null;
    });
    // The draft is all its own now: every field in it is brought back.
    await _start();
    if (mounted) unawaited(_moveDraft(id));
  }

  /// The fields hold the entry (or nothing): note that as the baseline,
  /// bring back a draft, then start putting changes aside.
  Future<void> _start({bool showMood = false}) {
    _baseline = jsonEncode(_snapshot());
    return _restoreDraft().then((_) {
      if (!mounted) return;
      setState(() {
        // A mood picked on the way in wins over a draft's — and is about
        // today ("Bugün nasıldı?"), not the day an older draft was for.
        final picked = widget.initialMood;
        if (picked != null && !_isEditing) {
          _mood = picked;
          _date = ref.read(currentDayProvider);
        }
        // The mood strip opens only for a fresh new entry without a mood —
        // decided once the draft is in.
        _moodOpen = showMood && _mood == null && !_draftRestored;
      });
      // A new entry is for writing: the keyboard comes up. An edit opens
      // at the top, reading, with no keyboard over it.
      if (!_isEditing) _focusBody();
      _draftTimer ??= Timer.periodic(journalDraftInterval, (_) => _saveDraft());
    });
  }

  void _focusBody() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _foldTimer?.cancel();
    // Closing the editor keeps what was typed (it never asks): the draft
    // brings it back next time. Also while a save is on its way: should it
    // fail, nothing is lost; should it succeed, it clears the draft after.
    _saveDraft(closing: true);
    _lifecycle.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _gratitudeCtrl.dispose();
    _tagsCtrl.dispose();
    _bodyFocus.dispose();
    _tagsFocus.dispose();
    _gratitudeFocus.dispose();
    super.dispose();
  }

  Map<String, Object?> _snapshot() => {
    'date': isoDate(_date),
    'title': _titleCtrl.text,
    'body': _bodyCtrl.text,
    'mood': _mood,
    'weather': _weather,
    'energy': _energy,
    'gratitude': _gratitudeCtrl.text,
    'tags': _tagsCtrl.text,
  };

  /// Brings back a draft: only the fields changed in it (from what the
  /// draft started from), so a field edited elsewhere since — and not
  /// here — keeps its new value. A draft of an entry changed elsewhere
  /// since says so.
  Future<void> _restoreDraft() async {
    try {
      final raw = await _drafts.read(entryId: _draftKey);
      if (raw == null || !mounted) return;
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      final fields = stored['fields'] is Map
          ? (stored['fields'] as Map).cast<String, dynamic>()
          : stored;
      final draft = _snapshotOf(fields);
      // A new entry whose save may have reached the server: looked for
      // before it is sent again.
      final sent = stored['sent'];
      if (sent is Map && sent['fields'] is Map && !_isEditing) {
        _sent = (
          fields: _snapshotOf((sent['fields'] as Map).cast<String, dynamic>()),
          at: DateTime.tryParse('${sent['at']}') ?? DateTime(1970),
        );
      }
      final base = stored['base'] is Map
          ? _snapshotOf((stored['base'] as Map).cast<String, dynamic>())
          : null;
      final merged = {
        ..._snapshot(),
        for (final key in draft.keys)
          // A new entry's draft is all its own.
          if (base == null ||
              _entry == null ||
              '${draft[key]}' != '${base[key]}')
            key: draft[key],
      };
      if (jsonEncode(merged) == _baseline) return;
      final savedAt = DateTime.tryParse('${stored['updated_at']}');
      final updatedAt = _entry?.updatedAt;
      final stale =
          savedAt != null &&
          updatedAt != null &&
          !updatedAt.isAtSameMomentAs(savedAt);
      setState(() {
        _date = DateTime.tryParse('${merged['date']}') ?? _date;
        _titleCtrl.text = '${merged['title']}';
        _bodyCtrl.text = '${merged['body']}';
        _mood = merged['mood'] as String?;
        _weather = merged['weather'] as String?;
        _energy = merged['energy'] as int;
        _gratitudeCtrl.text = '${merged['gratitude']}';
        _gratitudeOn = _gratitudeCtrl.text.isNotEmpty;
        _tagsCtrl.text = '${merged['tags']}';
        _tagsOn = _tagsCtrl.text.isNotEmpty;
        _energyOn = _energy > 0;
        _draftRestored = true;
        _draftStale = stale;
      });
    } catch (_) {
      // Corrupt draft or a storage hiccup — the fields keep the entry.
    }
  }

  /// A stored draft in the shape of [_snapshot], to compare with it.
  static Map<String, Object?> _snapshotOf(Map<String, dynamic> d) => {
    'date': '${d['date']}',
    'title': '${d['title'] ?? ''}',
    'body': '${d['body'] ?? ''}',
    'mood': d['mood'],
    'weather': d['weather'],
    'energy': (d['energy'] as num?)?.toInt() ?? 0,
    'gratitude': '${d['gratitude'] ?? ''}',
    'tags': '${d['tags'] ?? ''}',
  };

  /// Puts what is typed aside — or, when it is what the editor opened with,
  /// drops any draft. Never once saved, nor on a tick while saving: that
  /// would write the text just saved back as a draft. A failed save clears
  /// [_saving] and the drafts carry on. [closing]: the editor is going away
  /// with a save still on its way — kept, in case that save fails. Never
  /// throws.
  void _saveDraft({bool closing = false}) {
    final baseline = _baseline;
    if (_saved || baseline == null || (_saving && !closing)) return;
    final fields = _snapshot();
    _lastFields = fields;
    final now = jsonEncode(fields);
    // Nothing changed since the last tick: it is put aside (or dropped)
    // already — no encrypted write every few seconds while the editor idles.
    if (now == _lastDraft && !closing) return;
    final key = _draftKey;
    // With what it started from and the entry's version, so a later
    // restore brings back only what was changed, and knows when the entry
    // moved on meanwhile.
    // The quiet stamp moves only when the text did.
    if (now != baseline && now != _lastDraft && !closing && mounted) {
      setState(() => _draftSavedAt = DateTime.now());
    }
    _lastDraft = now;
    final write = now == baseline
        ? _drafts.clear(entryId: key)
        : _drafts.write(_draftJson(fields, baseline), entryId: key);
    unawaited(
      write.catchError((Object _) {
        // Not stored: the next tick tries again.
        if (_lastDraft == now) _lastDraft = null;
      }),
    );
  }

  /// A draft of [fields]: with what it started from and the entry's
  /// version, and what a lost save sent ([_sent]).
  String _draftJson(Map<String, Object?> fields, String baseline) {
    final sent = _sent;
    return jsonEncode({
      'fields': fields,
      'base': jsonDecode(baseline),
      'updated_at': _entry?.updatedAt?.toIso8601String(),
      if (sent != null)
        'sent': {'fields': sent.fields, 'at': sent.at.toIso8601String()},
    });
  }

  /// A new entry's answer was lost: what was sent goes into the draft now —
  /// also once the editor has closed — so whoever brings the draft back
  /// looks in the journal before sending it again.
  void _rememberSent(Map<String, Object?> fields, DateTime at) {
    _sent = (fields: fields, at: at);
    final baseline = _baseline;
    final current = mounted ? _snapshot() : _lastFields ?? fields;
    if (baseline == null || _saved) return;
    _lastFields = current;
    _lastDraft = jsonEncode(current);
    unawaited(
      _drafts
          .write(_draftJson(current, baseline), entryId: _draftKey)
          .catchError((Object _) {
            // Not stored: the next tick tries again.
            _lastDraft = null;
          }),
    );
  }

  /// Puts the fields back as the editor opened them and drops the draft.
  void _discardDraft() {
    Haptics.tick();
    final e = _entry;
    setState(() {
      if (e != null) {
        _fill(e);
      } else {
        _date = ref.read(currentDayProvider);
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _mood = null;
        _weather = null;
        _energy = 0;
        _gratitudeCtrl.clear();
        _gratitudeOn = false;
        _tagsCtrl.clear();
        _tagsOn = false;
        _energyOn = false;
      }
      _draftRestored = false;
      _draftStale = false;
    });
    _lastDraft = null;
    _sent = null;
    unawaited(_drafts.clear(entryId: _draftKey).catchError((Object _) {}));
  }

  /// The entry was deleted elsewhere (a 404, or a refresh found it gone):
  /// the editor and the text stay, Save makes them a new entry, and the
  /// draft moves to the new entry's when that one is free — no screen could
  /// bring back a draft of an entry that is gone.
  void _markGone() {
    if (_gone || _saved || widget.editEntry == null) return;
    if (!mounted) {
      unawaited(_goneAfterClose(widget.editEntry!.id));
      return;
    }
    Haptics.reject();
    setState(() {
      _gone = true;
      _saving = false;
      _entry = null;
    });
    // As a new entry, everything in the fields is worth keeping.
    _baseline = jsonEncode({
      ..._snapshot(),
      'title': '',
      'body': '',
      'mood': null,
      'weather': null,
      'energy': 0,
      'gratitude': '',
      'tags': '',
    });
    unawaited(_moveDraft(widget.editEntry!.id));
  }

  Future<void> _moveDraft(int entryId) async {
    try {
      if (await _drafts.read() == null) {
        _draftKey = null;
        await _drafts.clear(entryId: entryId);
      }
    } catch (_) {
      // Storage hiccup: the draft stays under the entry's key.
    }
    _lastDraft = null;
    _saveDraft();
  }

  /// The save of an edit was answered 404 after the editor closed: the
  /// draft it left moves to the new entry's, when that one is free, and the
  /// snackbar offers to open it.
  Future<void> _goneAfterClose(int entryId) async {
    _gone = true;
    var moved = false;
    try {
      final raw = await _drafts.read(entryId: entryId);
      if (raw != null && await _drafts.read() == null) {
        await _drafts.write(raw);
        await _drafts.clear(entryId: entryId);
        moved = true;
      }
    } catch (_) {
      // Storage hiccup: the draft stays under the entry's key.
    }
    final out = _out;
    if (out == null || !out.host.mounted) return;
    showAppSnack(
      out.host,
      moved ? out.l.journalGoneDraftKept : out.l.journalGone,
      isError: true,
      actionLabel: moved ? out.l.journalOpenDraft : null,
      onAction: moved
          ? () => openJournalEditor(out.host)
          : null,
    );
  }

  List<String> _parsedTags() => _tagsOf(_tagsCtrl.text);

  static List<String> _tagsOf(String text) =>
      text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  /// What a snapshot of the fields ([_snapshot]) would save.
  static JournalInput _inputOf(Map<String, Object?> f) {
    final title = '${f['title'] ?? ''}'.trim();
    final gratitude = '${f['gratitude'] ?? ''}'.trim();
    final energy = (f['energy'] as num?)?.toInt() ?? 0;
    return JournalInput(
      date: DateTime.tryParse('${f['date']}') ?? DateTime(1970),
      title: title.isEmpty ? null : title,
      bodyText: '${f['body'] ?? ''}',
      mood: f['mood'] as String?,
      weather: f['weather'] as String?,
      energyLevel: energy > 0 ? energy : null,
      gratitude: gratitude.isEmpty ? null : gratitude,
      tags: _tagsOf('${f['tags'] ?? ''}'),
    );
  }

  Future<void> _pickDate() async {
    final first = DateTime(2015);
    final last = ref.read(currentDayProvider);
    // A draft/edit date can fall outside [first, last]; clamp so showDatePicker
    // never asserts on an out-of-range initialDate.
    final initial = _date.isBefore(first)
        ? first
        : (_date.isAfter(last) ? last : _date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickWeather() async {
    final l = context.l10n;
    final picked = await showPickerSheet<String>(
      context,
      title: l.journalEditorWeather,
      selected: _weather,
      options: [
        for (final (key, icon) in _weatherOptions)
          PickerOption(
            value: l.weatherLabel(key),
            label: l.weatherLabel(key),
            icon: icon,
          ),
      ],
    );
    if (picked != null) setState(() => _weather = picked);
  }

  /// A mood from the strip: it grows, then the strip folds into a chip.
  void _selectMood(String mood) {
    _foldTimer?.cancel();
    setState(() => _mood = mood);
    _foldTimer = Timer(Motion.orInstant(context, Motion.quick), () {
      if (mounted) setState(() => _moodOpen = false);
    });
  }

  void _clearMood() {
    Haptics.tick();
    _foldTimer?.cancel();
    setState(() => _mood = null);
  }

  void _toggleMoodStrip() {
    _foldTimer?.cancel();
    setState(() => _moodOpen = !_moodOpen);
    if (_moodOpen) _reveal(_moodKey);
  }

  /// The accessory bar's Enerji: shows the picker, or — once a level is
  /// set, when the picker stays — brings it into view.
  void _onEnergy() {
    if (_energy > 0) {
      _reveal(_energyKey);
      return;
    }
    setState(() => _energyOn = !_energyOn);
    if (_energyOn) _reveal(_energyKey);
  }

  void _onTags() {
    setState(() => _tagsOn = !_tagsOn);
    if (_tagsOn) _reveal(_tagsKey, focus: _tagsFocus);
  }

  void _onGratitude() {
    setState(() => _gratitudeOn = !_gratitudeOn);
    if (_gratitudeOn) _reveal(_gratitudeKey, focus: _gratitudeFocus);
  }

  /// Once the section under [key] is built, scrolls it into view — down to
  /// it, or up to it, only as far as needed; a jump under reduced motion —
  /// and puts the cursor in its field ([focus]).
  void _reveal(GlobalKey key, {FocusNode? focus}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = key.currentContext;
      if (!mounted || target == null) return;
      focus?.requestFocus();
      final duration = Motion.orInstant(context, Motion.standard);
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        curve: Motion.enter,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      if (!mounted || !target.mounted) return;
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        curve: Motion.enter,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  /// The kinds of web formatting ([kinds], `body_formatting` values) in
  /// words: "kalın yazı, liste".
  String _formattingOf(List<String> kinds) {
    final l = context.l10n;
    return (kinds.isEmpty ? const ['other'] : kinds)
        .map(l.journalFormatting)
        .join(', ');
  }

  Future<bool> _confirmDropFormatting(List<String> kinds) => showConfirmDialog(
    context,
    title: context.l10n.journalRichConfirmTitle,
    message: context.l10n.journalRichConfirmBody(_formattingOf(kinds)),
    confirmLabel: context.l10n.journalRichConfirmAction,
    destructive: true,
  );

  /// Where the outcome of a save is said once the editor has closed — X
  /// and the back gesture stay live while it is on its way: the app's
  /// navigator, the screen the editor was opened from, the words.
  ({BuildContext host, AppL10n l, bool editing})? _out;

  /// Floats the editor's own snackbars above the accessory bar, so they
  /// never cover "Kaydet" (§7.12: the bar rides the keyboard).
  EdgeInsets _overBar() {
    final bar = _barKey.currentContext?.size?.height ?? 0;
    return EdgeInsets.fromLTRB(16, 0, 16, bar + Gap.sm);
  }

  /// [force]: send a new entry without first looking for an earlier send
  /// whose answer was lost — the user's call ("Yine de kaydet").
  Future<void> _save({bool force = false}) async {
    if (_saving) return;
    final l = context.l10n;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    // A mood or energy alone is a check-in worth keeping.
    if (title.isEmpty && body.isEmpty && _mood == null && _energy == 0) {
      showAppSnack(
        context,
        l.journalEditorNeedsContent,
        isError: true,
        margin: _overBar(),
      );
      return;
    }
    final gratitude = _gratitudeCtrl.text.trim();
    final fields = _snapshot();
    final today = ref.read(currentDayProvider);
    final clock = ref.read(clockProvider);
    final offset = ref.read(accountUtcOffsetProvider);
    final input = JournalInput(
      date: _date,
      title: title.isEmpty ? null : title,
      // As typed — line breaks and blank lines are the paragraphs.
      bodyText: _bodyCtrl.text,
      mood: _mood,
      weather: _weather,
      energyLevel: _energy > 0 ? _energy : null,
      // Hiding a field never deletes what it holds.
      gratitude: gratitude.isEmpty ? null : gratitude,
      tags: _parsedTags(),
    );
    final before = _entry;
    var discard = false;
    if (before != null) {
      if (input.changesFrom(before).isEmpty) {
        await _finish(changed: false);
        return;
      }
      // A changed text over web formatting: only once the user agrees.
      if (before.isRich && input.bodyChangedFrom(before)) {
        if (!await _confirmDropFormatting(before.bodyFormatting) || !mounted) {
          return;
        }
        discard = true;
      }
    }
    _out = (
      host: Navigator.of(context, rootNavigator: true).context,
      l: l,
      editing: _isEditing,
    );
    setState(() => _saving = true);
    // The journal list and this entry refresh from the repository's report
    // of the write, closed editor or not.
    final repo = ref.read(repositoryProvider);
    ({Map<String, Object?> fields, DateTime at})? sending;
    try {
      if (before == null) {
        // An earlier send may have arrived: look before sending it again.
        final sent = _sent;
        if (sent != null && !force) {
          if (await _settleSent(repo, sent, input, fields, today)) return;
        }
        _sent = null;
        sending = (fields: fields, at: accountWallClock(clock(), offset));
        await repo.createJournalEntry(input);
      } else {
        await repo.updateJournalEntry(
          before,
          input,
          discardFormatting: discard,
        );
      }
      await _finish(changed: true);
    } on ApiException catch (e) {
      // The entry got web formatting since it was opened: ask, then send
      // the same changes again with the go-ahead.
      if (e.code == 'body_has_formatting' && before != null && mounted) {
        setState(() => _saving = false);
        final kinds = [
          for (final kind in (e.extra['body_formatting'] as List?) ?? const [])
            '$kind',
        ];
        if (!await _confirmDropFormatting(kinds) || !mounted) return;
        setState(() => _saving = true);
        try {
          await repo.updateJournalEntry(before, input, discardFormatting: true);
          await _finish(changed: true);
        } on ApiException catch (e) {
          if (e.kind == ApiErrorKind.notFound) return _markGone();
          _failed(e);
        } catch (e) {
          _failed(e);
        }
        return;
      }
      // Deleted elsewhere: keep the text, offer it as a new entry.
      if (e.kind == ApiErrorKind.notFound && before != null) {
        return _markGone();
      }
      // No answer in time to a new entry: the server may have it. Look for
      // it before saying anything, and never send it again blindly — the
      // draft remembers it was sent.
      if (sending != null && e.isNetwork && e.mayHaveArrived) {
        _rememberSent(sending.fields, sending.at);
        try {
          if (await _settleSent(repo, _sent!, input, fields, today)) return;
        } catch (e) {
          return _failed(e);
        }
      }
      _failed(e);
    } catch (e) {
      _failed(e);
    }
  }

  /// Looks in the journal for the new entry [sent] would have created —
  /// its answer was lost. True when that settles the save: it is there
  /// (saved; and should the fields have changed since, [input] goes to it
  /// as an edit), or the journal cannot tell ("may be saved"). False when
  /// it is not there.
  Future<bool> _settleSent(
    MeridianRepository repo,
    ({Map<String, Object?> fields, DateTime at}) sent,
    JournalInput input,
    Map<String, Object?> fields,
    DateTime today,
  ) async {
    final look = await _lookFor(repo, _inputOf(sent.fields), sent.at, today);
    if (look == null) {
      _maybeSaved();
      return true;
    }
    final found = look.found;
    if (found == null) return false;
    if (jsonEncode(fields) != jsonEncode(sent.fields)) {
      // Changed since it was sent: the changes go to the entry it made.
      final full = await repo.fetchJournalEntry(found.id);
      if (input.changesFrom(full).isNotEmpty) {
        await repo.updateJournalEntry(full, input);
      }
    }
    _sent = null;
    await _finish(changed: true);
    return true;
  }

  /// The entry [sent], sent at [at], in the journal: `found` null when it
  /// is not there; null when the journal cannot tell — it cannot be read,
  /// or its newest 180 stop before that day. Asks for the shortest range
  /// that reaches the day, so the 180 rarely stop short.
  static Future<({JournalEntry? found})?> _lookFor(
    MeridianRepository repo,
    JournalInput sent,
    DateTime at,
    DateTime today,
  ) async {
    final JournalBundle journal;
    try {
      journal = await repo.fetchJournal(
        range: _rangeReaching(sent.date, today),
      );
    } catch (_) {
      return null;
    }
    final entries = journal.entries;
    for (final e in entries) {
      if (journalEntryMatches(e, sent, sentAt: at)) return (found: e);
    }
    final day = isoDate(sent.date);
    final stopsShort =
        entries.length < journal.entriesCount &&
        (entries.isEmpty || isoDate(entries.last.date).compareTo(day) > 0);
    return stopsShort ? null : (found: null);
  }

  /// The shortest `GET /journal_entries` range (each ends today) holding
  /// [date].
  static String _rangeReaching(DateTime date, DateTime today) {
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
    if (days < 0) return 'all';
    if (days == 0) return '1d';
    if (days < 6) return '7d';
    if (days < 29) return '30d';
    if (days < 180) return '6mo';
    if (days < 360) return '1y';
    return 'all';
  }

  /// A new entry's save may have reached the server, and the journal could
  /// not tell: the text stays, and the next "Kaydet" — here, or in an
  /// editor that brings the draft back — looks again before sending it.
  /// "Yine de kaydet" sends it without looking.
  void _maybeSaved() {
    final out = _out!;
    if (mounted) {
      setState(() => _saving = false);
      showAppSnack(
        context,
        out.l.journalMaybeSaved,
        isError: true,
        margin: _overBar(),
        actionLabel: out.l.journalSaveAnyway,
        onAction: () {
          if (mounted) unawaited(_save(force: true));
        },
      );
    } else if (out.host.mounted) {
      showAppSnack(
        out.host,
        out.l.journalMaybeSavedLater,
        isError: true,
      );
    }
  }

  /// Saved (or nothing to save): the draft goes, and so does the editor.
  /// Said also when the editor was closed while the save was on its way.
  Future<void> _finish({required bool changed}) async {
    _saved = true;
    _draftTimer?.cancel();
    try {
      await _drafts.clear(entryId: _draftKey);
    } catch (_) {
      // Secure storage hiccup: the entry is saved either way.
    }
    final out = _out;
    if (!mounted) {
      if (changed && out != null && out.host.mounted) {
        Haptics.confirm();
        showAppSnack(
          out.host,
          out.editing ? out.l.journalUpdated : out.l.journalAdded,
        );
      }
      return;
    }
    final l = context.l10n;
    final host = Navigator.of(context, rootNavigator: true).context;
    final editing = _isEditing;
    Navigator.of(context).pop(changed);
    if (changed && host.mounted) {
      Haptics.confirm();
      // Said on the screen the editor goes back to, once it is the one
      // shown: over its FAB or capture bar.
      showAppSnack(
        host,
        editing ? l.journalUpdated : l.journalAdded,
      );
    }
  }

  void _failed(Object e) {
    // Any failure must clear the spinner, or the save button stays a
    // permanent loading state; the text stays, and so does the draft.
    if (!mounted) return _failedAfterClose(e);
    final l = context.l10n;
    setState(() => _saving = false);
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.journalSaveFailed),
      isError: true,
      margin: _overBar(),
    );
  }

  /// The save failed after the editor was closed: what was typed is a
  /// draft (closing put it aside), and the snackbar says so and opens it.
  void _failedAfterClose(Object e) {
    final out = _out;
    if (out == null || !out.host.mounted) {
      Haptics.reject();
      return;
    }
    final entry = widget.editEntry;
    final gone = _gone;
    showAppSnack(
      out.host,
      out.l.journalSaveFailedKept,
      isError: true,
      actionLabel: out.l.journalOpenDraft,
      onAction: () => openJournalEditor(
        out.host,
        entry: gone ? null : entry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final editId = widget.editEntry?.id;
    // Deleted on the web or another device while being edited.
    if (editId != null) {
      ref.listen(journalEntryProvider(editId), (_, next) {
        if (next.isGone && !_loadingFull) _markGone();
      });
    }
    return PopScope(
      // Never blocks the back gesture: what is typed is put aside first.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveDraft(closing: true);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: _dateChip(context),
          actions: [_draftStamp(context)],
        ),
        // The accessory bar is the body's last child, not the scaffold's
        // bottom bar: the body shrinks above the keyboard, so Save rides it.
        body: _loadingFull
            ? _loadingView(context)
            : Column(
                children: [
                  Expanded(child: _fields(context)),
                  _AccessoryBar(
                    contentKey: _barKey,
                    mood: _mood != null || _moodOpen,
                    energy: _energy > 0 || _energyOn,
                    tags: _tagsCtrl.text.trim().isNotEmpty || _tagsOn,
                    gratitude: _gratitudeOn,
                    weatherSet: _weather != null,
                    weatherIcon: journalWeatherIcon(_weather, l),
                    saving: _saving,
                    onMood: _toggleMoodStrip,
                    onEnergy: _onEnergy,
                    onTags: _onTags,
                    onGratitude: _onGratitude,
                    onWeather: _pickWeather,
                    onSave: _save,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _loadingView(BuildContext context) {
    final l = context.l10n;
    if (_loadGone) {
      // A retry could only answer 404 again: say what happened instead.
      return EmptyState(
        icon: Icons.delete_outline_rounded,
        title: l.journalGone,
        subtitle: l.errRecordGoneBody,
        actionLabel: l.actionBack,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (_loadError != null) {
      // The server cannot be reached (§7.15): the Tailscale advice and a
      // retry.
      return EmptyState.error(onRetry: _retryLoad);
    }
    // The whole body is on its way (GET /journal_entries/:id).
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.formH,
        Gap.lg,
        Insets.formH,
        Gap.lg,
      ),
      children: [
        const Bone.text(width: 200, lineHeight: 28),
        const SizedBox(height: Gap.xxl),
        for (var i = 0; i < 6; i++)
          const Bone.text(width: double.infinity, lineHeight: 28),
        const Bone.text(width: 180, lineHeight: 28),
      ],
    );
  }

  Widget _fields(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final entry = _entry;
    const bare = InputDecoration(
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    );
    // Not lazy: the sections after a long body are built, so the
    // accessory bar can scroll them into view.
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: const EdgeInsets.fromLTRB(
        Insets.formH,
        Gap.sm,
        Insets.formH,
        Gap.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_gone) _goneBanner(context),
          if (_draftRestored) _draftBanner(context),
          if (entry != null && entry.isRich) _richNotice(context, entry),
          TextField(
            controller: _titleCtrl,
            style: text.headlineMedium,
            // A long title wraps, whole at any text size; Next still moves
            // on to the body.
            keyboardType: TextInputType.text,
            minLines: 1,
            maxLines: null,
            // Wrapping, yet one line: a pasted line break is dropped, as
            // a single-line field would (Flutter adds this only there).
            inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _bodyFocus.requestFocus(),
            decoration: bare.copyWith(
              hintText: l.journalEditorTitleHint,
              hintStyle: text.headlineMedium!.copyWith(color: c.inkLow),
            ),
          ),
          // AnimatedSize cannot take zero time (it would re-lay itself out
          // mid-layout): under reduced motion the section just takes its
          // size.
          if (Motion.reduced(context))
            KeyedSubtree(key: _moodKey, child: _moodSection(context))
          else
            AnimatedSize(
              key: _moodKey,
              duration: Motion.quick,
              curve: Motion.enter,
              alignment: Alignment.topCenter,
              child: _moodSection(context),
            ),
          if (_weather != null) _weatherChip(context),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _bodyCtrl,
            focusNode: _bodyFocus,
            style: context.nokText.reading,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: bare.copyWith(
              hintText: l.journalEditorBodyHint,
              hintStyle: context.nokText.reading.copyWith(color: c.inkLow),
            ),
          ),
          if (_energyOn || _energy > 0)
            _section(_energyKey, [
              const SizedBox(height: Gap.lg),
              _overline(context, l.journalEnergy),
              EnergyBars(
                level: _energy,
                scale: 1.6,
                onChanged: (v) => setState(() => _energy = v),
              ),
            ]),
          if (_tagsOn)
            _section(_tagsKey, [
              const SizedBox(height: Gap.lg),
              _overline(context, l.journalEditorTags),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _tagsCtrl,
                focusNode: _tagsFocus,
                style: text.bodyLarge,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: l.journalEditorTagsHint),
              ),
            ]),
          if (_gratitudeOn)
            _section(_gratitudeKey, [
              const SizedBox(height: Gap.lg),
              _gratitudeBox(context),
            ]),
        ],
      ),
    );
  }

  /// An optional section under [key], for [_reveal].
  Widget _section(GlobalKey key, List<Widget> children) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );

  /// The inline mood strip, or — once a mood is picked — the chip it folds
  /// into (a tap opens the strip again).
  Widget _moodSection(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final mood = _mood;
    if (_moodOpen) {
      return Padding(
        key: const ValueKey('mood-strip'),
        padding: const EdgeInsets.only(top: Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.journalEditorMoodPrompt,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: Gap.sm),
            MoodStrip(selected: mood, onSelected: _selectMood),
            Align(
              alignment: Alignment.centerRight,
              child: mood == null
                  ? TextButton(
                      onPressed: () => setState(() => _moodOpen = false),
                      child: Text(l.labelSkip),
                    )
                  : TextButton(
                      onPressed: _clearMood,
                      child: Text(l.journalEditorMoodClear),
                    ),
            ),
          ],
        ),
      );
    }
    if (mood == null) {
      return const SizedBox(key: ValueKey('mood-none'), width: double.infinity);
    }
    return Padding(
      key: const ValueKey('mood-chip'),
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: '${l.journalEditorMood}: ${l.moodLabel(mood)}',
          onTap: _toggleMoodStrip,
          excludeSemantics: true,
          child: InkWell(
            onTap: _toggleMoodStrip,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoodEmoji(emoji: moodEmojiFor(mood), size: 20),
                    const SizedBox(width: Gap.sm),
                    Text(
                      l.moodLabel(mood),
                      style: text.bodyMedium!.copyWith(color: c.inkMid),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "4 Eki Paz ▾" — the entry's day; a tap picks another.
  Widget _dateChip(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final label = '${formatDate(_date)} ${formatWeekdayShort(_date)}';
    // Not while the entry loads: its own date would replace the one picked.
    final onTap = _loadingFull ? null : _pickDate;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: l.journalEditorDateLabel(
        '${formatDate(_date, withYear: true)}, ${formatWeekday(_date)}',
      ),
      // Excluding the button's semantics drops its tap: keep it here.
      onTap: onTap,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: onTap,
        iconAlignment: IconAlignment.end,
        style: TextButton.styleFrom(foregroundColor: c.inkHi),
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: c.inkMid,
        ),
        label: Text(label, style: text.titleMedium),
      ),
    );
  }

  /// "Taslak 12:41": when what is typed was last put aside. A fixed slot,
  /// the time cross-fading in 200 ms on each autosave.
  Widget _draftStamp(BuildContext context) {
    final c = context.nok;
    final at = _draftSavedAt;
    return Padding(
      padding: const EdgeInsets.only(right: Insets.formH),
      child: SizedBox(
        width: 88,
        child: AnimatedSwitcher(
          duration: Motion.orInstant(context, Motion.quick),
          child: at == null
              ? const SizedBox.shrink()
              : Align(
                  key: ValueKey(at),
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.l10n.journalDraftSavedAt(formatTime(at)),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: c.inkLow),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _draftBanner(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    // A draft of an entry changed elsewhere since stands out: check first.
    final ink = _draftStale ? c.onGoldContainer : c.inkMid;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.xs, Gap.xs),
      decoration: BoxDecoration(
        color: _draftStale ? c.goldContainer : c.surface2,
        borderRadius: Radii.mdAll,
        border: Border.all(color: _draftStale ? c.goldDim : c.hairline),
      ),
      child: Row(
        children: [
          Icon(
            _draftStale ? Icons.history_rounded : Icons.restore_rounded,
            size: 18,
            color: ink,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              _draftStale
                  ? l.journalDraftRestoredStale
                  : l.journalDraftRestored,
              style: text.bodySmall!.copyWith(color: ink),
            ),
          ),
          TextButton(
            onPressed: _discardDraft,
            child: Text(l.journalDraftDiscard),
          ),
        ],
      ),
    );
  }

  Widget _goneBanner(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.xs),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: c.error),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    l.journalEditorEntryGone,
                    style: text.bodySmall!.copyWith(color: c.inkMid),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l.journalEditorSaveAsNew),
            ),
          ),
        ],
      ),
    );
  }

  Widget _richNotice(BuildContext context, JournalEntry entry) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.goldDim),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_bold_rounded, size: 18, color: c.onGoldContainer),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              context.l10n.journalRichNotice(
                _formattingOf(entry.bodyFormatting),
              ),
              style: text.bodySmall!.copyWith(color: c.onGoldContainer),
            ),
          ),
        ],
      ),
    );
  }

  /// The weather as a pill, and a 48 dp button that removes it.
  Widget _weatherChip(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 6,
              ),
              decoration: ShapeDecoration(
                color: c.surface2,
                shape: StadiumBorder(side: BorderSide(color: c.hairline)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    journalWeatherIcon(_weather, l),
                    size: 16,
                    color: c.inkMid,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _weather!,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge!.copyWith(color: c.inkMid),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: l.journalEditorWeatherClear,
            onPressed: () => setState(() => _weather = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  /// "MİNNET": goldContainer, a 1 dp goldDim edge.
  Widget _gratitudeBox(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.goldDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 14, color: c.onGoldContainer),
              const SizedBox(width: 6),
              Text(
                l.journalGratitude,
                style: text.labelMedium!.copyWith(color: c.onGoldContainer),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _gratitudeCtrl,
            focusNode: _gratitudeFocus,
            style: text.bodyLarge!.copyWith(color: c.onGoldContainer),
            minLines: 2,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l.journalEditorGratitudeHint,
              hintStyle: text.bodyLarge!.copyWith(
                // 0.8: ≥ 4.5:1 over goldContainer in both themes (§8.1).
                color: c.onGoldContainer.withValues(alpha: 0.8),
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _overline(BuildContext context, String label) =>
      Text(label, style: Theme.of(context).textTheme.labelMedium);
}

/// The editor's accessory bar: Ruh hali · Enerji · Etiket · Minnet · Hava
/// (scrolling sideways) and "Kaydet", above the keyboard.
class _AccessoryBar extends StatelessWidget {
  /// On the bar's content, inside its safe area: its height is what the
  /// editor's snackbars float above.
  final Key contentKey;
  final bool mood;
  final bool energy;
  final bool tags;
  final bool gratitude;
  final bool weatherSet;
  final IconData weatherIcon;
  final bool saving;
  final VoidCallback onMood;
  final VoidCallback onEnergy;
  final VoidCallback onTags;
  final VoidCallback onGratitude;
  final VoidCallback onWeather;
  final VoidCallback onSave;

  const _AccessoryBar({
    required this.contentKey,
    required this.mood,
    required this.energy,
    required this.tags,
    required this.gratitude,
    required this.weatherSet,
    required this.weatherIcon,
    required this.saving,
    required this.onMood,
    required this.onEnergy,
    required this.onTags,
    required this.onGratitude,
    required this.onWeather,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;
    Widget chip(String label, IconData icon, bool on, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(right: Gap.sm),
          child: NokChip(label: label, icon: icon, selected: on, onTap: onTap),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          key: contentKey,
          padding: const EdgeInsets.fromLTRB(0, Gap.xs, Gap.md, Gap.xs),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: Gap.md),
                  child: Row(
                    children: [
                      chip(
                        l.journalEditorMood,
                        Icons.mood_rounded,
                        mood,
                        onMood,
                      ),
                      chip(
                        l.journalEnergy,
                        Icons.bolt_rounded,
                        energy,
                        onEnergy,
                      ),
                      chip(
                        l.journalChipTags,
                        Icons.sell_outlined,
                        tags,
                        onTags,
                      ),
                      chip(
                        l.journalChipGratitude,
                        Icons.favorite_border_rounded,
                        gratitude,
                        onGratitude,
                      ),
                      chip(
                        l.journalChipWeather,
                        weatherIcon,
                        weatherSet,
                        onWeather,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              PrimaryButton(
                label: l.actionSave,
                expand: false,
                loading: saving,
                onPressed: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
