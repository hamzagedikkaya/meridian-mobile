import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/picker_sheet.dart';
import '../../../ui/widgets/slide_up_route.dart';
import 'journal_providers.dart';
import 'widgets/energy_dots.dart';
import 'widgets/mood.dart';

const _draftKey = 'journal_draft';

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

/// Opens the full-screen journal editor as a root-navigator modal.
Future<void> openJournalEditor(BuildContext context, {JournalEntry? entry}) {
  return Navigator.of(context, rootNavigator: true).push(
    slideUpModalRoute((_) => JournalEditorScreen(editEntry: entry)),
  );
}

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
  Timer? _draftTimer;

  bool get _isEditing => widget.editEntry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editEntry;
    if (e != null) {
      _date = e.date;
      _titleCtrl.text = e.title ?? '';
      _bodyCtrl.text = e.bodyPlain ?? '';
      _mood = e.mood;
      _weather = e.weather;
      _energy = e.energyLevel ?? 0;
      _gratitudeCtrl.text = e.gratitude ?? '';
      _gratitudeOn = (e.gratitude ?? '').isNotEmpty;
      _tagsCtrl.text = e.tags.join(', ');
      _tagsOn = e.tags.isNotEmpty;
    } else {
      _date = DateTime.now();
      _restoreDraft();
      _showMoodOverlay = _mood == null;
      _draftTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _saveDraft());
    }
    if (!_showMoodOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bodyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _gratitudeCtrl.dispose();
    _tagsCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_draftKey);
      if (raw == null) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      _date = DateTime.tryParse('${d['date']}') ?? DateTime.now();
      _titleCtrl.text = '${d['title'] ?? ''}';
      _bodyCtrl.text = '${d['body'] ?? ''}';
      _mood = d['mood'] as String?;
      _weather = d['weather'] as String?;
      _energy = (d['energy'] as num?)?.toInt() ?? 0;
      _gratitudeCtrl.text = '${d['gratitude'] ?? ''}';
      _gratitudeOn = _gratitudeCtrl.text.isNotEmpty;
      _tagsCtrl.text = '${d['tags'] ?? ''}';
      _tagsOn = _tagsCtrl.text.isNotEmpty;
    } catch (_) {
      // Corrupt draft — ignore.
    }
  }

  void _saveDraft() {
    if (_isEditing) return;
    try {
      ref.read(sharedPrefsProvider).setString(
            _draftKey,
            jsonEncode({
              'date': isoDate(_date),
              'title': _titleCtrl.text,
              'body': _bodyCtrl.text,
              'mood': _mood,
              'weather': _weather,
              'energy': _energy,
              'gratitude': _gratitudeCtrl.text,
              'tags': _tagsCtrl.text,
            }),
          );
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      await ref.read(sharedPrefsProvider).remove(_draftKey);
    } catch (_) {}
  }

  List<String> _parsedTags() => _tagsCtrl.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _pickDate() async {
    final first = DateTime(2015);
    final last = DateTime.now();
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

  Future<void> _save() async {
    if (_saving) return;
    final l = context.l10n;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty && body.isEmpty) {
      showAppSnack(context, l.journalEditorNeedsContent, isError: true);
      return;
    }
    setState(() => _saving = true);
    final gratitude = _gratitudeOn ? _gratitudeCtrl.text.trim() : '';
    final input = JournalInput(
      date: _date,
      title: title.isEmpty ? null : title,
      body: body.isEmpty ? null : body,
      mood: _mood,
      weather: _weather,
      energyLevel: _energy > 0 ? _energy : null,
      gratitude: gratitude.isEmpty ? null : gratitude,
      tags: _tagsOn ? _parsedTags() : const [],
    );
    try {
      final repo = ref.read(repositoryProvider);
      if (_isEditing) {
        await repo.updateJournalEntry(widget.editEntry!.id, input);
        ref.invalidate(journalEntryProvider(widget.editEntry!.id));
      } else {
        await repo.createJournalEntry(input);
        await _clearDraft();
      }
      ref.invalidate(journalProvider);
      if (!mounted) return;
      Haptics.success();
      showAppSnack(context, _isEditing ? l.journalUpdated : l.journalAdded);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, e.localized(l), isError: true);
    } catch (_) {
      // Any non-API failure must still clear the spinner, or the save button
      // stays a permanent loading state.
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, l.journalSaveFailed, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: text.titleLarge,
        leading: IconButton(
          icon: const Icon(Icons.close),
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
              : TextButton(onPressed: _save, child: Text(l.actionSave)),
        ],
      ),
      bottomNavigationBar: _AccessoryBar(
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
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _dateRow(context),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                style: text.titleLarge,
                textCapitalization: TextCapitalization.sentences,
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

  Widget _dateRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _weatherChip(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_weatherIcon(_weather, context.l10n),
                    size: 14, color: c.inkMid),
                const SizedBox(width: 6),
                Text(_weather!,
                    style: text.labelSmall!.copyWith(color: c.inkMid)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _weather = null),
                  child: Icon(Icons.close, size: 14, color: c.inkLow),
                ),
              ],
            ),
          ),
        ],
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
              _btn(context, Icons.favorite_border, gratitudeOn, onGratitude),
              _btn(context, Icons.sell_outlined, tagsOn, onTags),
              _btn(context, weatherIcon, weatherSet, onWeather),
              const Spacer(),
              Text(context.l10n.journalEnergy, style: text.labelSmall),
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
    bool active,
    VoidCallback onTap,
  ) {
    final c = context.nok;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: active ? c.gold : c.inkMid),
    );
  }
}
