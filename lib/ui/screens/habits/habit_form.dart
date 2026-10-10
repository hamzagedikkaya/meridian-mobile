import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/data_scope.dart';
import '../../../data/providers.dart';
import '../../../data/recent_changes.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/entity_color.dart';
import '../../widgets/amount_keypad.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/slide_up_route.dart';

/// The habit form (design-analysis §7.10, IA-21), full screen: to create a
/// habit or, with [habit], to edit one (every field prefilled, only the
/// changed ones sent).
///
/// In order: the name (focused when creating), how often (Günlük ·
/// Haftalık · Aylık), the target — a 48 dp − and + around "günde 8 kez",
/// whose tap opens a keypad to type it — the colour, then "Daha fazla":
/// the description and, for a habit that exists, the day it started. A
/// habit is no longer linked to a goal here: a goal counts a habit from
/// the goal's side (contract §5.1), shown in the habit's detail.
///
/// [initialName] fills the name in (quick capture's "create the habit 'X'").
/// Resolves to the habit saved, or null when the form was closed without
/// saving. A new habit's card grows in on the list, washed.
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

/// The highest target the stepper and its keypad take.
const habitTargetMax = 99;

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
  late final _description = TextEditingController(
    text: _editing?.description ?? '',
  );
  late String _frequency = _editing?.frequency ?? 'daily';
  late int _target = _editing?.targetCount ?? 1;
  late String _color = _editing?.color ?? recordSwatches.first;

  /// "Daha fazla" open: from the start when there is a description to show.
  late bool _more = _editing?.description.trim().isNotEmpty ?? false;

  /// The target's keypad is open, with what has been typed on it.
  bool _typingTarget = false;
  String _typed = '';
  int _rejected = 0;

  bool _saving = false;
  String? _nameError;
  final _nameKey = GlobalKey();

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
    // Not edited here any more: whatever the habit has is kept.
    goalId: _editing?.goalId,
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

  Future<void> _save() async {
    if (_saving) return;
    final l = context.l10n;
    final input = _input;
    if (input.name.isEmpty) {
      setState(() => _nameError = l.habitsFormNameRequired);
      await FormScaffold.revealInvalid(_nameKey);
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
      final sync = ref.read(dataSyncProvider);
      final habit = before == null
          ? await repo.createHabit(input)
          : await repo.updateHabit(before, input);
      sync.noteChange(
        DataScope.habits,
        habit.id,
        before == null ? ChangeKind.inserted : ChangeKind.updated,
      );
      Haptics.confirm();
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
        await FormScaffold.revealInvalid(_nameKey);
      }
    }
  }

  // --- Target -----------------------------------------------------------------

  void _setTarget(int value) {
    final next = value.clamp(1, habitTargetMax);
    if (next == _target) return;
    setState(() => _target = next);
  }

  void _toggleKeypad() => setState(() {
    _typingTarget = !_typingTarget;
    _typed = '';
  });

  void _digit(String d) {
    final typed = _typed == '0' ? d : '$_typed$d';
    final value = int.parse(typed);
    if (value > habitTargetMax) {
      Haptics.reject();
      setState(() => _rejected++);
      return;
    }
    setState(() {
      _typed = typed;
      if (value >= 1) _target = value;
    });
  }

  void _backspace() {
    if (_typed.isEmpty) return;
    final typed = _typed.substring(0, _typed.length - 1);
    setState(() {
      _typed = typed;
      final value = int.tryParse(typed) ?? 0;
      if (value >= 1) _target = value;
    });
  }

  /// "günde 8 kez", "haftada 3 gün", "ayda 3 gün".
  String _targetLabel(AppL10n l) => switch (_frequency) {
    'weekly' => l.habitsTargetWeekly(_target),
    'monthly' => l.habitsTargetMonthly(_target),
    _ => l.habitsTargetDaily(_target),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.nok;
    final l = context.l10n;
    final before = _editing;
    final rhythmChanged =
        before != null &&
        (before.frequency != _frequency || before.targetCount != _target);

    return FormScaffold(
      title: before == null ? l.habitsFormNewTitle : l.habitsFormEditTitle,
      actionLabel: l.actionSave,
      onAction: _save,
      busy: _saving,
      dirty: _dirty && !_saving,
      children: [
        TextField(
          key: _nameKey,
          controller: _name,
          // A new habit starts typing at once; an edit does not pop the
          // keyboard over what it shows.
          autofocus: before == null,
          maxLength: habitNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l.habitsFormName,
            hintText: l.habitsFormNameHint,
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameError = null),
        ),
        const SizedBox(height: Gap.lg),
        FormLabel(l.habitsFormFrequency),
        SegmentedPill<String>(
          expand: true,
          options: [
            ('daily', l.habitsFormDaily),
            ('weekly', l.habitsFormWeekly),
            ('monthly', l.habitsFormMonthly),
          ],
          selected: _frequency,
          onChanged: (v) => setState(() => _frequency = v),
        ),
        const SizedBox(height: Gap.xxl),
        FormLabel(
          _frequency == 'daily'
              ? l.habitsFormDailyTarget
              : l.habitsFormPeriodTarget,
        ),
        _targetStepper(context),
        if (_typingTarget) ...[
          const SizedBox(height: Gap.sm),
          AmountKeypad(
            showDecimal: false,
            onDigit: _digit,
            onDot: () {},
            onBackspace: _backspace,
          ),
        ],
        if (rhythmChanged) ...[
          const SizedBox(height: Gap.sm),
          Text(
            l.habitsFormHistoryNote,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
        const SizedBox(height: Gap.xxl),
        FormLabel(l.habitsFormColor),
        ColorSwatchRow(
          selected: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
        const SizedBox(height: Gap.lg),
        if (!_more)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _more = true),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(l.habitsFormMore),
            ),
          )
        else ...[
          const SizedBox(height: Gap.sm),
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
          if (before?.startDate case final start?) ...[
            const SizedBox(height: Gap.md),
            // The server sets it: the day the habit was made.
            Text(
              l.habitsFormStarted(formatDate(start, withYear: true)),
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ],
        ],
      ],
    );
  }

  /// 48 dp − and +, and between them "günde 8 kez" — a tap there opens the
  /// keypad.
  Widget _targetStepper(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final tone = entityTone(_color, c);
    Widget btn(IconData icon, String tooltip, bool enabled, int to) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(
            width: Hit.min,
            height: Hit.min,
          ),
          onPressed: enabled
              ? () {
                  Haptics.tick();
                  _typed = '';
                  _setTarget(to);
                }
              : null,
          icon: Icon(icon, size: 20, color: enabled ? c.inkHi : c.inkDisabled),
        );
    return Row(
      children: [
        btn(Icons.remove_rounded, l.habitLogDecrease, _target > 1, _target - 1),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: RejectShake(
            trigger: _rejected,
            child: Semantics(
              button: true,
              liveRegion: true,
              hint: l.habitsTargetTypeHint,
              child: Material(
                color: _typingTarget ? tone.tint : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: Radii.mdAll,
                  side: BorderSide(
                    color: _typingTarget ? tone.fill : c.inkDisabled,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _toggleKeypad,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Hit.min),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: Gap.sm,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _targetLabel(l),
                              textAlign: TextAlign.center,
                              style: text.titleMedium,
                            ),
                          ),
                          const SizedBox(width: Gap.xs),
                          Icon(
                            Icons.dialpad_rounded,
                            size: 18,
                            color: c.inkLow,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.sm),
        btn(
          Icons.add_rounded,
          l.habitLogIncrease,
          _target < habitTargetMax,
          _target + 1,
        ),
      ],
    );
  }
}
