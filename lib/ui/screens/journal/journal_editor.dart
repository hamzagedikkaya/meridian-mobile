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
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/confirm_dialog.dart';
import '../../../ui/widgets/picker_sheet.dart';
import '../../../ui/widgets/slide_up_route.dart';
import '../../../ui/widgets/sync_hint.dart';
import 'widgets/energy_dots.dart';
import 'widgets/mood.dart';

/// Weather is free text on the server (the web app has a plain input), so the
/// picker stores the label in the user's own language, like a tag.
const _weatherOptions = <(String, IconData)>[
  ('sunny', Icons.wb_sunny_outlined),
  ('partly_cloudy', Icons.wb_cloudy_outlined),
  ('cloudy', Icons.cloud_outlined),
  ('rainy', Icons.grain),
  ('snowy', Icons.ac_unit),
];

IconData _weatherIcon(String? weather, AppL10n l) {
  for (final (key, icon) in _weatherOptions) {
    if (l.weatherLabel(key) == weather) return icon;
  }
  return Icons.wb_cloudy_outlined;
}

/// Opens the full-screen journal editor as a root-navigator modal: a new
/// entry, or [entry] to edit — the full entry (`GET /journal_entries/:id`);
/// given a list item, the editor loads the full one first. Completes with
/// true once something was saved (an entry deleted elsewhere meanwhile may
/// have been saved as a new one).
Future<bool?> openJournalEditor(BuildContext context, {JournalEntry? entry}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    slideUpModalRoute((_) => JournalEditorScreen(editEntry: entry)),
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
class JournalEditorScreen extends ConsumerStatefulWidget {
  final JournalEntry? editEntry;
  const JournalEditorScreen({super.key, this.editEntry});

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

  late DateTime _date;
  String? _mood;
  String? _weather;
  int _energy = 0;
  bool _gratitudeOn = false;
  bool _tagsOn = false;
  bool _showMoodOverlay = false;
  bool _saving = false;

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
      // The mood step only for a fresh new entry without a mood — decided
      // once the draft is in, so it never pops over restored text.
      setState(() =>
          _showMoodOverlay = showMood && _mood == null && !_draftRestored);
      // A new entry is for writing: the keyboard comes up. An edit opens
      // at the top, reading, with no keyboard over it.
      if (!_isEditing && !_showMoodOverlay) _focusBody();
      _draftTimer ??=
          Timer.periodic(journalDraftInterval, (_) => _saveDraft());
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
      final stale = savedAt != null &&
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
      }
      _draftRestored = false;
      _draftStale = false;
    });
    unawaited(
        _drafts.clear(entryId: _draftKey).catchError((Object _) {}));
  }

  /// The entry was deleted elsewhere (a 404, or a refresh found it gone):
  /// the editor and the text stay, Save makes them a new entry, and the
  /// draft moves to the new entry's when that one is free — no screen could
  /// bring back a draft of an entry that is gone.
  void _markGone() {
    if (_gone || _saved || !mounted || widget.editEntry == null) return;
    Haptics.danger();
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

  /// The mood, changed or cleared at any time (the first step only asks
  /// once).
  Future<void> _pickMood() async {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    const clear = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.journalEditorMoodPrompt, style: text.titleLarge),
              const SizedBox(height: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: MoodPicker(
                  selected: _mood,
                  size: 44,
                  onSelected: (m) => Navigator.of(sheet).pop(m),
                ),
              ),
              if (_mood != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(sheet).pop(clear),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(l.journalEditorMoodClear),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _mood = picked == clear ? null : picked);
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
        await repo.updateJournalEntry(before, input,
            discardFormatting: discard);
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
          await repo.updateJournalEntry(before, input,
              discardFormatting: true);
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
      Haptics.success();
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
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final entry = _entry;
    final editId = widget.editEntry?.id;
    // Deleted on the web or another device while being edited.
    if (editId != null) {
      ref.listen(journalEntryProvider(editId), (_, next) {
        if (next.isGone && !_loadingFull) _markGone();
      });
    }
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: text.titleLarge,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEditing ? l.journalEditorEditTitle : l.journalEditorNewTitle),
        actions: [
          _saving
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.gold),
                  ),
                )
              : TextButton(
                  onPressed: _loadingFull ? null : _save,
                  child: Text(l.actionSave),
                ),
        ],
      ),
      bottomNavigationBar: _loadingFull
          ? null
          : _AccessoryBar(
              gratitudeOn: _gratitudeOn,
              tagsOn: _tagsCtrl.text.trim().isNotEmpty || _tagsOn,
              weatherSet: _weather != null,
              weatherIcon: _weatherIcon(_weather, l),
              energy: _energy,
              onGratitude: () => setState(() => _gratitudeOn = !_gratitudeOn),
              onTags: () => setState(() => _tagsOn = !_tagsOn),
              onWeather: _pickWeather,
              onEnergy: (v) => setState(() => _energy = v),
            ),
      body: _loadingFull
          ? Center(
              child: _loadError == null
                  ? CircularProgressIndicator(color: c.gold)
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        failureMessage(_loadError!, l,
                            fallback: l.journalLoadFailed),
                        textAlign: TextAlign.center,
                      ),
                    ),
            )
          : Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (_gone) _goneBanner(context),
              if (_draftRestored) _draftBanner(context),
              if (entry != null && entry.isRich) _richNotice(context, entry),
              _dateRow(context),
              _moodRow(context),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                style: text.titleLarge,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
                decoration: InputDecoration(
                  hintText: l.journalEditorTitleHint,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_weather != null) _weatherChip(context),
              TextField(
                controller: _bodyCtrl,
                focusNode: _bodyFocus,
                style: text.bodyLarge,
                minLines: 8,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l.journalEditorBodyHint,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_tagsOn) ...[
                const SizedBox(height: 16),
                _overline(context, l.journalEditorTags),
                const SizedBox(height: 8),
                TextField(
                  controller: _tagsCtrl,
                  style: text.bodyMedium,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l.journalEditorTagsHint,
                  ),
                ),
              ],
              if (_gratitudeOn) ...[
                const SizedBox(height: 16),
                _overline(context, l.journalGratitude),
                const SizedBox(height: 8),
                TextField(
                  controller: _gratitudeCtrl,
                  style: text.bodyMedium,
                  minLines: 2,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: l.journalEditorGratitudeHint,
                  ),
                ),
              ],
            ],
          ),
          if (_showMoodOverlay) _moodOverlay(context),
        ],
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: _draftStale ? c.goldContainer : c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          Icon(_draftStale ? Icons.history : Icons.restore,
              size: 18, color: ink),
          const SizedBox(width: 8),
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
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
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
                Icon(Icons.delete_outline, size: 18, color: c.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.journalEditorEntryGone,
                      style: text.bodySmall!.copyWith(color: c.inkMid)),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_bold, size: 18, color: c.onGoldContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n
                  .journalRichNotice(_formattingOf(entry.bodyFormatting)),
              style: text.bodySmall!.copyWith(color: c.onGoldContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: c.inkMid),
            const SizedBox(width: 8),
            Text(
              formatDate(_date, withYear: true),
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final mood = _mood;
    return Semantics(
      button: true,
      label: mood == null
          ? l.journalEditorMood
          : '${l.journalEditorMood}: ${l.moodLabel(mood)}',
      // Excluding the row's semantics drops the InkWell's tap: keep it.
      onTap: _pickMood,
      excludeSemantics: true,
      child: InkWell(
        onTap: _pickMood,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (mood == null)
                Icon(Icons.mood_outlined, size: 18, color: c.inkMid)
              else
                MoodEmoji(emoji: moodEmojiFor(mood), size: 18),
              const SizedBox(width: 8),
              Text(
                mood == null ? l.journalEditorMood : l.moodLabel(mood),
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherChip(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: Icon(_weatherIcon(_weather, context.l10n),
              size: 16, color: c.inkMid),
          label: Text(_weather!,
              style: text.labelSmall!.copyWith(color: c.inkMid)),
          onDeleted: () => setState(() => _weather = null),
          deleteButtonTooltipMessage:
              MaterialLocalizations.of(context).deleteButtonTooltip,
        ),
      ),
    );
  }

  Widget _overline(BuildContext context, String label) => Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      );

  Widget _moodOverlay(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Positioned.fill(
      child: Container(
        color: c.bg,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Text(context.l10n.journalEditorMoodPrompt,
                  style: text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MoodPicker(
                    selected: _mood,
                    onSelected: (m) {
                      setState(() {
                        _mood = m;
                        _showMoodOverlay = false;
                      });
                      _bodyFocus.requestFocus();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  setState(() => _showMoodOverlay = false);
                  _bodyFocus.requestFocus();
                },
                child: Text(context.l10n.labelSkip),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessoryBar extends StatelessWidget {
  final bool gratitudeOn;
  final bool tagsOn;
  final bool weatherSet;
  final IconData weatherIcon;
  final int energy;
  final VoidCallback onGratitude;
  final VoidCallback onTags;
  final VoidCallback onWeather;
  final ValueChanged<int> onEnergy;

  const _AccessoryBar({
    required this.gratitudeOn,
    required this.tagsOn,
    required this.weatherSet,
    required this.weatherIcon,
    required this.energy,
    required this.onGratitude,
    required this.onTags,
    required this.onWeather,
    required this.onEnergy,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _btn(context, Icons.favorite_border, l.journalGratitude,
                  gratitudeOn, onGratitude),
              _btn(context, Icons.sell_outlined, l.journalEditorTags, tagsOn,
                  onTags),
              _btn(context, weatherIcon, l.journalEditorWeather, weatherSet,
                  onWeather),
              const Spacer(),
              Flexible(
                child: Text(
                  l.journalEnergy,
                  style: text.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              EnergyDots(level: energy, size: 12, gap: 2, onChanged: onEnergy),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    IconData icon,
    String tooltip,
    bool active,
    VoidCallback onTap,
  ) {
    final c = context.nok;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: active ? c.gold : c.inkMid),
    );
  }
}
