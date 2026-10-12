import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/confirm_dialog.dart';
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
/// mood picked (Today's mood buttons).
Future<bool?> openJournalEditor(
  BuildContext context, {
  JournalEntry? entry,
  String? initialMood,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    slideUpModalRoute(
      (_) => JournalEditorScreen(editEntry: entry, initialMood: initialMood),
    ),
  );
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
  const JournalEditorScreen({super.key, this.editEntry, this.initialMood});

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

  Future<void> _loadFull(int id) async {
    try {
      final full = (await ref.read(journalEntryProvider(id).future)).data;
      if (!mounted) return;
      setState(() {
        _fill(full);
        _loadingFull = false;
      });
      _start();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// The fields hold the entry (or nothing): note that as the baseline,
  /// bring back a draft, then start putting changes aside.
  void _start({bool showMood = false}) {
    _baseline = jsonEncode(_snapshot());
    _restoreDraft().then((_) {
      if (!mounted) return;
      setState(() {
        // A mood picked on the way in wins over a draft's.
        final picked = widget.initialMood;
        if (picked != null && !_isEditing) _mood = picked;
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
    final now = jsonEncode(_snapshot());
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
        : _drafts.write(
            jsonEncode({
              'fields': _snapshot(),
              'base': jsonDecode(baseline),
              'updated_at': _entry?.updatedAt?.toIso8601String(),
            }),
            entryId: key,
          );
    unawaited(write.catchError((Object _) {}));
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
    unawaited(_drafts.clear(entryId: _draftKey).catchError((Object _) {}));
  }

  /// The entry was deleted elsewhere (a 404, or a refresh found it gone):
  /// the editor and the text stay, Save makes them a new entry, and the
  /// draft moves to the new entry's when that one is free — no screen could
  /// bring back a draft of an entry that is gone.
  void _markGone() {
    if (_gone || _saved || !mounted || widget.editEntry == null) return;
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
    _saveDraft();
  }

  List<String> _parsedTags() => _tagsCtrl.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

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

  Future<void> _save() async {
    if (_saving) return;
    final l = context.l10n;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    // A mood or energy alone is a check-in worth keeping.
    if (title.isEmpty && body.isEmpty && _mood == null && _energy == 0) {
      showAppSnack(context, l.journalEditorNeedsContent, isError: true);
      return;
    }
    final gratitude = _gratitudeCtrl.text.trim();
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
    setState(() => _saving = true);
    // The journal list and this entry refresh from the repository's report
    // of the write, closed editor or not.
    final repo = ref.read(repositoryProvider);
    try {
      if (before == null) {
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
      _failed(e);
    } catch (e) {
      _failed(e);
    }
  }

  /// Saved (or nothing to save): the draft goes, and so does the editor.
  Future<void> _finish({required bool changed}) async {
    _saved = true;
    _draftTimer?.cancel();
    try {
      await _drafts.clear(entryId: _draftKey);
    } catch (_) {
      // Secure storage hiccup: the entry is saved either way.
    }
    if (!mounted) return;
    final l = context.l10n;
    if (changed) {
      Haptics.confirm();
      showAppSnack(context, _isEditing ? l.journalUpdated : l.journalAdded);
    }
    Navigator.of(context).pop(changed);
  }

  void _failed(Object e) {
    // Any failure must clear the spinner, or the save button stays a
    // permanent loading state; the text stays, and so does the draft.
    if (!mounted) return;
    final l = context.l10n;
    setState(() => _saving = false);
    showAppSnack(
      context,
      failureMessage(e, l, fallback: l.journalSaveFailed),
      isError: true,
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
    final error = _loadError;
    if (error != null) {
      final l = context.l10n;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.x3),
          child: Text(
            failureMessage(error, l, fallback: l.journalLoadFailed),
            textAlign: TextAlign.center,
          ),
        ),
      );
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
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _bodyFocus.requestFocus(),
            decoration: bare.copyWith(
              hintText: l.journalEditorTitleHint,
              hintStyle: text.headlineMedium!.copyWith(color: c.inkLow),
            ),
          ),
          AnimatedSize(
            key: _moodKey,
            duration: Motion.orInstant(context, Motion.quick),
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
    return Semantics(
      button: true,
      label: l.journalEditorDateLabel(
        '${formatDate(_date, withYear: true)}, ${formatWeekday(_date)}',
      ),
      // Excluding the button's semantics drops its tap: keep it here.
      onTap: _pickDate,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: _pickDate,
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
                color: c.onGoldContainer.withValues(alpha: 0.72),
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
