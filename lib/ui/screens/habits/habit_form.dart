import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/slide_up_route.dart';
import 'widgets/habit_visuals.dart';

/// Full-screen habit create modal (design §4.5): name, frequency, target
/// stepper, 8-swatch color row (gold default), optional goal link.
///
/// [initialName] fills the name in (quick capture's "create the habit 'X'").
/// Resolves to the habit created, or null when the form was closed without
/// saving.
Future<Habit?> openHabitForm(BuildContext context, {String? initialName}) {
  return Navigator.of(context, rootNavigator: true).push<Habit>(
    slideUpModalRoute((_) => HabitFormScreen(initialName: initialName)),
  );
}

/// The longest habit name the server takes (meridian `Habit`).
const habitNameMaxLength = 60;

const _swatches = [
  '#D4A853', // gold (default)
  '#6B8E5A', // sage
  '#6B8FA0', // dusty blue
  '#B85450', // clay
  '#D4A574', // tan
  '#7A5C9E', // mauve
  '#5A9E8B', // teal
  '#8B5A00', // amber
];

class HabitFormScreen extends ConsumerStatefulWidget {
  final String? initialName;

  const HabitFormScreen({super.key, this.initialName});

  @override
  ConsumerState<HabitFormScreen> createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends ConsumerState<HabitFormScreen> {
  late final _name = TextEditingController(text: widget.initialName?.trim());
  String _frequency = 'daily';
  int _target = 1;
  String _color = _swatches.first;
  int? _goalId;
  String? _goalName;
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickGoal() async {
    final l = context.l10n;
    // Watched in build, so the list is normally fetched (and current) by the
    // time the picker opens — even when the Goals tab was never visited. If
    // it is still on its way, wait for it; if it cannot be had, say so rather
    // than offering only "none".
    var bundle = ref.read(goalsProvider).value?.data;
    if (bundle == null) {
      try {
        bundle = (await ref.read(goalsProvider.future)).data;
      } on ApiException catch (e) {
        if (mounted) showAppSnack(context, e.localized(l), isError: true);
        return;
      } catch (_) {
        if (mounted) showAppSnack(context, l.errNoConnection, isError: true);
        return;
      }
      if (!mounted) return;
    }
    final goals = bundle.active;
    // -1 is the explicit "none" sentinel so a dismiss (null) can be told apart
    // from clearing an already-chosen goal.
    const noneSentinel = -1;
    final options = <PickerOption<int>>[
      PickerOption(value: noneSentinel, label: l.labelNone),
      for (final g in goals)
        PickerOption(value: g.id, label: g.name, color: hexColor(g.color)),
    ];
    final picked = await showPickerSheet<int>(
      context,
      title: l.habitsFormLinkGoal,
      options: options,
      selected: _goalId ?? noneSentinel,
    );
    if (!mounted) return;
    if (picked == null) return; // dismissed → keep the current selection
    setState(() {
      _goalId = picked == noneSentinel ? null : picked;
      _goalName = _goalId == null
          ? null
          : goals.firstWhere((g) => g.id == _goalId).name;
    });
  }

  Future<void> _save() async {
    final l = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = l.habitsFormNameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      // The repository reports the new habit; Habits, Today and goals
      // refresh from that, even if this form is closed before it answers.
      final habit = await ref.read(repositoryProvider).createHabit(HabitInput(
            name: name,
            frequency: _frequency,
            targetCount: _target,
            color: _color,
            goalId: _goalId,
          ));
      Haptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(habit);
      showAppSnack(context, l.habitsAdded);
    } catch (e) {
      if (!mounted) return;
      // A refusal about the name goes under the name; the rest to a snack.
      final nameError = e is ApiException ? e.fieldMessage(l, 'name') : null;
      setState(() {
        _saving = false;
        _nameError = nameError;
      });
      if (nameError == null) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.habitsSaveFailed),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the goal list loaded for the "link to goal" picker.
    ref.watch(goalsProvider);
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final targetLabel =
        _frequency == 'daily' ? l.habitsFormDailyTarget : l.habitsFormPeriodTarget;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l.habitsFormNewTitle, style: text.headlineMedium),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: habitNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.habitsFormName,
              hintText: l.habitsFormNameHint,
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 24),
          Text(l.habitsFormFrequency, style: text.titleSmall),
          const SizedBox(height: 12),
          SegmentedPill<String>(
            options: [
              ('daily', l.habitsFormDaily),
              ('weekly', l.habitsFormWeekly),
              ('monthly', l.habitsFormMonthly),
            ],
            selected: _frequency,
            onChanged: (v) => setState(() => _frequency = v),
          ),
          const SizedBox(height: 24),
          Text(targetLabel, style: text.titleSmall),
          const SizedBox(height: 12),
          _targetStepper(context),
          const SizedBox(height: 24),
          Text(l.habitsFormColor, style: text.titleSmall),
          const SizedBox(height: 12),
          _colorRow(),
          const SizedBox(height: 24),
          Text(l.habitsFormGoalLink, style: text.titleSmall),
          const SizedBox(height: 12),
          _goalRow(context),
          const SizedBox(height: 32),
          PrimaryButton(
            label: l.actionSave,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _targetStepper(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => Material(
          color: c.surface2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled
                ? () {
                    Haptics.tick();
                    onTap();
                  }
                : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon,
                  size: 20, color: enabled ? c.inkHi : c.inkFaint),
            ),
          ),
        );
    return Row(
      children: [
        btn(Icons.remove, _target > 1, () => setState(() => _target--)),
        SizedBox(
          width: 56,
          child: Text('$_target',
              textAlign: TextAlign.center, style: text.titleLarge),
        ),
        btn(Icons.add, _target < 99, () => setState(() => _target++)),
      ],
    );
  }

  Widget _colorRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final hex in _swatches)
          GestureDetector(
            onTap: () {
              Haptics.tick();
              setState(() => _color = hex);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hexColor(hex),
                shape: BoxShape.circle,
                border: _color == hex
                    ? Border.all(color: context.nok.inkHi, width: 2)
                    : null,
              ),
              child: _color == hex
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _goalRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _pickGoal,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _goalName ?? context.l10n.labelNone,
                style: text.bodyLarge!.copyWith(
                  color: _goalName == null ? c.inkLow : c.inkHi,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.inkLow, size: 20),
          ],
        ),
      ),
    );
  }
}
