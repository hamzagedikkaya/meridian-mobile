import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/goal.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/slide_up_route.dart';
import 'widgets/habit_visuals.dart';

/// Full-screen habit form (design §4.5): name, description, frequency,
/// target stepper, colour, optional goal link — to create a habit or, with
/// [habit], to edit one (every field prefilled, only the changed ones sent).
///
/// [initialName] fills the name in (quick capture's "create the habit 'X'").
/// Resolves to the habit saved, or null when the form was closed without
/// saving.
Future<Habit?> openHabitForm(
  BuildContext context, {
  String? initialName,
  Habit? habit,
}) {
  return Navigator.of(context, rootNavigator: true).push<Habit>(
    slideUpModalRoute(
      (_) => HabitFormScreen(initialName: initialName, habit: habit),
    ),
  );
}

/// The longest habit name the server takes (meridian `Habit`).
const habitNameMaxLength = 60;

class HabitFormScreen extends ConsumerStatefulWidget {
  final String? initialName;

  /// The habit to edit; null to create one.
  final Habit? habit;

  const HabitFormScreen({super.key, this.initialName, this.habit});

  @override
  ConsumerState<HabitFormScreen> createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends ConsumerState<HabitFormScreen> {
  Habit? get _editing => widget.habit;

  late final _name = TextEditingController(
    text: _editing?.name ?? widget.initialName?.trim(),
  );
  late final _description =
      TextEditingController(text: _editing?.description ?? '');
  late String _frequency = _editing?.frequency ?? 'daily';
  late int _target = _editing?.targetCount ?? 1;
  late String _color = _editing?.color ?? recordSwatches.first;
  late int? _goalId = _editing?.goalId;
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  HabitInput get _input => HabitInput(
        name: _name.text.trim(),
        frequency: _frequency,
        targetCount: _target,
        color: _color,
        description: _description.text,
        goalId: _goalId,
      );

  /// Whether leaving would lose something: for an edit, a change from the
  /// habit; for a new habit, anything typed.
  bool get _dirty {
    final before = _editing;
    if (before != null) return _input.changesFrom(before).isNotEmpty;
    return _name.text.trim().isNotEmpty &&
            _name.text.trim() != (widget.initialName?.trim() ?? '') ||
        _description.text.trim().isNotEmpty;
  }

  /// Every goal by id (any status: a habit can serve an achieved one too).
  Map<int, Goal> _goalsById(GoalsBundle? bundle) => {
        if (bundle != null)
          for (final g in [...bundle.active, ...bundle.achieved, ...bundle.abandoned])
            g.id: g,
      };

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
    // The active goals, and the one linked now whatever its status.
    final current = _goalsById(bundle)[_goalId];
    final goals = [
      ...bundle.active,
      if (current != null && !current.isActive) current,
    ];
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
    setState(() => _goalId = picked == noneSentinel ? null : picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = context.l10n;
    final input = _input;
    if (input.name.isEmpty) {
      Haptics.danger();
      setState(() => _nameError = l.habitsFormNameRequired);
      return;
    }
    final before = _editing;
    if (before != null && input.changesFrom(before).isEmpty) {
      Navigator.of(context).pop(before);
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      // The repository reports the write; Habits, Today and goals refresh
      // from that, even if this form is closed before it answers.
      final repo = ref.read(repositoryProvider);
      final habit = before == null
          ? await repo.createHabit(input)
          : await repo.updateHabit(before, input);
      Haptics.success();
      if (!mounted) return;
      Navigator.of(context).pop(habit);
      showAppSnack(context, before == null ? l.habitsAdded : l.habitsUpdated);
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
      } else {
        Haptics.danger();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the goal list loaded for the "link to goal" picker and the name
    // of the goal linked now.
    final goals = ref.watch(goalsProvider).value?.data;
    final text = Theme.of(context).textTheme;
    final c = context.nok;
    final l = context.l10n;
    final before = _editing;
    final targetLabel = _frequency == 'daily'
        ? l.habitsFormDailyTarget
        : l.habitsFormPeriodTarget;
    final rhythmChanged = before != null &&
        (before.frequency != _frequency || before.targetCount != _target);
    final goal = _goalsById(goals)[_goalId];

    return FormScaffold(
      title: before == null ? l.habitsFormNewTitle : l.habitsFormEditTitle,
      actionLabel: l.actionSave,
      onAction: _save,
      busy: _saving,
      dirty: _dirty && !_saving,
      children: [
        TextField(
          controller: _name,
          // A new habit starts typing at once; an edit does not pop the
          // keyboard over what it shows.
          autofocus: before == null,
          maxLength: habitNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.habitsFormName,
            hintText: l.habitsFormNameHint,
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameError = null),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l.habitsFormDescription,
            hintText: l.habitsFormDescriptionHint,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FormLabel(l.habitsFormFrequency),
        // Scrolls rather than overflows with large text.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedPill<String>(
            options: [
              ('daily', l.habitsFormDaily),
              ('weekly', l.habitsFormWeekly),
              ('monthly', l.habitsFormMonthly),
            ],
            selected: _frequency,
            onChanged: (v) => setState(() => _frequency = v),
          ),
        ),
        const SizedBox(height: 24),
        FormLabel(targetLabel),
        _targetStepper(context),
        if (rhythmChanged) ...[
          const SizedBox(height: 8),
          Text(
            l.habitsFormHistoryNote,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
        const SizedBox(height: 24),
        FormLabel(l.habitsFormColor),
        ColorSwatchRow(
          selected: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
        const SizedBox(height: 24),
        FormLabel(l.habitsFormGoalLink),
        FormPickerRow(
          icon: Icons.flag_outlined,
          label: l.habitsFormLinkGoal,
          // A goal linked on the web that is not loaded yet still shows as
          // linked, never as "none".
          value: _goalId == null ? l.labelNone : goal?.name ?? '…',
          color: goal == null ? null : hexColor(goal.color),
          onTap: _pickGoal,
        ),
      ],
    );
  }

  Widget _targetStepper(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    Widget btn(IconData icon, String tooltip, bool enabled, VoidCallback onTap) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled
              ? () {
                  Haptics.tick();
                  onTap();
                }
              : null,
          icon: Icon(icon, size: 20, color: enabled ? c.inkHi : c.inkFaint),
        );
    return Row(
      children: [
        btn(Icons.remove, l.habitLogDecrease, _target > 1,
            () => setState(() => _target--)),
        Semantics(
          liveRegion: true,
          child: SizedBox(
            width: 56,
            child: Text('$_target',
                textAlign: TextAlign.center, style: text.titleLarge),
          ),
        ),
        btn(Icons.add, l.habitLogIncrease, _target < 99,
            () => setState(() => _target++)),
      ],
    );
  }
}
