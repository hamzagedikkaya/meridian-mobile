import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/session.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/account.dart';
import '../../../models/goal.dart';
import '../../../models/habit.dart';
import '../../../theme/app_colors.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/segmented_pill.dart';
import '../../widgets/slide_up_route.dart';
import '../finance/account_form.dart';
import 'goal_ui.dart';

/// The longest goal name the server takes (meridian `Goal`).
const goalNameMaxLength = 100;

/// Opens the goal form: a new goal or, with [goal], an edit of it. Resolves
/// to the goal saved, or null when it was closed without saving.
Future<Goal?> openGoalForm(BuildContext context, {Goal? goal}) {
  return Navigator.of(context, rootNavigator: true).push<Goal>(
    slideUpModalRoute((_) => GoalFormScreen(goal: goal)),
  );
}

/// What [pickGoalLink] picked: the `related` value and the name it shows.
typedef GoalLink = ({String related, String? name});

/// The link picker a goal of [targetType] offers — an active account (or a
/// new one, made there; with none yet, the account form opens at once) for
/// a financial goal, an active habit for a habit goal — with "none" first.
/// [current] is the link now (`"Account-12"`, `"Habit-7"`, `"none"`). Null
/// when dismissed, or when the list cannot be had (the snackbar says why).
Future<GoalLink?> pickGoalLink(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String current,
}) async {
  final l = context.l10n;
  Future<T?> lookup<T>(Future<Fetched<T>> Function() load) async {
    try {
      return (await load()).data;
    } on ApiException catch (e) {
      if (context.mounted) {
        showAppSnack(context, e.localized(l), isError: true);
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, l.errNoConnection, isError: true);
      }
    }
    return null;
  }

  const none = -1;
  const created = -2;
  if (targetType == 'financial') {
    final List<Account>? all =
        await lookup(() => ref.read(accountsProvider.future));
    if (all == null || !context.mounted) return null;
    final accounts = [for (final a in all) if (!a.archived) a];
    final id = accounts.isEmpty
        ? created
        : await showPickerSheet<int>(
            context,
            title: l.goalsFormLinkedAccount,
            selected: current.startsWith('Account-')
                ? int.tryParse(current.substring(8))
                : none,
            options: [
              PickerOption(value: none, label: l.labelNone),
              for (final a in accounts)
                PickerOption(
                    value: a.id, label: a.name, color: goalColor(a.color)),
              PickerOption(value: created, label: l.accountNew, icon: Icons.add),
            ],
          );
    if (id == null || !context.mounted) return null;
    if (id == none) return (related: 'none', name: null);
    final account = id == created
        ? await openAccountForm(context)
        : accounts.firstWhere((a) => a.id == id);
    if (account == null) return null;
    // The account form's "saved" snackbar would sit over the goal form's
    // pinned button for seconds; the link row naming the new account says
    // it was made.
    if (id == created && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    return (related: 'Account-${account.id}', name: account.name);
  }
  final HabitsBundle? bundle =
      await lookup(() => ref.read(habitsProvider.future));
  if (bundle == null || !context.mounted) return null;
  final id = await showPickerSheet<int>(
    context,
    title: l.goalsFormLinkedHabit,
    selected: current.startsWith('Habit-')
        ? int.tryParse(current.substring(6))
        : none,
    options: [
      PickerOption(value: none, label: l.labelNone),
      for (final h in bundle.habits)
        PickerOption(value: h.id, label: h.name, color: goalColor(h.color)),
    ],
  );
  if (id == null) return null;
  if (id == none) return (related: 'none', name: null);
  final habit = bundle.habits.firstWhere((h) => h.id == id);
  return (related: 'Habit-${habit.id}', name: habit.name);
}

/// Full-screen goal form (design-research §5.5): type first, then only that
/// type's fields. With [goal] it edits that goal — every field prefilled,
/// its link kept unless changed here — and sends only what changed.
class GoalFormScreen extends ConsumerStatefulWidget {
  final Goal? goal;

  const GoalFormScreen({super.key, this.goal});

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  Goal? get _editing => widget.goal;

  late final _name = TextEditingController(text: _editing?.name ?? '');
  late final _description =
      TextEditingController(text: _editing?.description ?? '');
  late final _unit = TextEditingController(text: _editing?.unit ?? '');
  late final _target = TextEditingController(
    text: _editing == null ? '' : goalNumberInput(_editing!.targetValue),
  );
  late final _current = TextEditingController(
    text: _editing == null || !_editing!.isManual
        ? ''
        : goalNumberInput(_editing!.currentValue),
  );

  late String _type = _editing?.targetType ?? 'custom';
  late String _color = _editing?.color ?? recordSwatches.first;
  late DateTime? _deadline = _editing?.deadline;
  late String _related = _editing?.relatedRef ?? 'none';
  late String? _relatedLabel = _editing?.related?.name;

  bool _saving = false;
  bool _picking = false;
  String? _nameError;
  String? _targetError;
  String? _currentError;
  String? _relatedError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _unit.dispose();
    _target.dispose();
    _current.dispose();
    super.dispose();
  }

  /// Progress logged by hand: a custom goal, or a habit goal without a
  /// habit. Only those take a starting value.
  bool get _manual =>
      _type == 'custom' || (_type == 'habit' && _related == 'none');

  void _setType(String type) {
    final before = _editing;
    setState(() {
      _type = type;
      // Back to the goal's own type: its link comes back with it.
      if (before != null && type == before.targetType) {
        _related = before.relatedRef;
        _relatedLabel = before.related?.name;
      } else {
        _related = 'none';
        _relatedLabel = null;
      }
      _relatedError = null;
    });
  }

  Future<void> _pickDeadline() async {
    final now = ref.read(currentDayProvider);
    final initial = _deadline ?? now.add(const Duration(days: 30));
    final first = initial.isBefore(now) ? initial : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(first.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _pickLink() async {
    if (_picking) return;
    _picking = true;
    try {
      final picked = await pickGoalLink(
        context,
        ref,
        targetType: _type,
        current: _related,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _related = picked.related;
        _relatedLabel = picked.name;
        _relatedError = null;
      });
    } finally {
      _picking = false;
    }
  }

  GoalInput _inputWith({num? target, num? current}) => GoalInput(
        name: _name.text.trim(),
        description: _description.text,
        targetType: _type,
        color: _color,
        unit: _type == 'financial' ? _financialUnit : _unit.text,
        deadline: _deadline,
        targetValue: target,
        related: _related,
        currentValue: _manual ? current : null,
      );

  /// A financial goal's unit is a currency, never typed here: the goal's
  /// own when it already was a financial one, the server's default (the
  /// user's currency) for a new goal, and the user's currency for a goal
  /// that becomes a financial one.
  String? get _financialUnit {
    final before = _editing;
    if (before == null) return null;
    if (before.targetType == 'financial') return before.unit;
    return ref.read(currentUserProvider)?.currency ?? before.unit;
  }

  bool get _dirty {
    final input = _inputWith(
      target: parseGoalNumber(_target.text),
      current: parseGoalNumber(_current.text),
    );
    final before = _editing;
    if (before != null) return input.changesFrom(before).isNotEmpty;
    return input.name.isNotEmpty ||
        _target.text.trim().isNotEmpty ||
        _description.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l = context.l10n;
    final name = _name.text.trim();
    final target = parseGoalNumber(_target.text);
    final currentText = _current.text.trim();
    final current = currentText.isEmpty ? null : parseGoalNumber(currentText);
    setState(() {
      _nameError = name.isEmpty ? l.goalsFormNameRequired : null;
      _targetError = (target == null || target <= 0)
          ? goalNumberError(l, _target.text,
              invalid: l.goalsFormTargetRequired)
          : null;
      _currentError = _manual && currentText.isNotEmpty &&
              (current == null || current < 0)
          ? goalNumberError(l, currentText, invalid: l.errInvalidData)
          : null;
    });
    if (_nameError != null || _targetError != null || _currentError != null) {
      Haptics.danger();
      return;
    }

    final input = _inputWith(target: target, current: current);
    final before = _editing;
    if (before != null && input.changesFrom(before).isEmpty) {
      Navigator.of(context).pop(before);
      return;
    }
    setState(() => _saving = true);
    try {
      // The repository reports the write; the Goals grid, the goal and
      // Today refresh from that, even if this form is closed first.
      final repo = ref.read(repositoryProvider);
      final saved = before == null
          ? await repo.createGoal(input)
          : await repo.updateGoal(before, input);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop(saved);
      showAppSnack(context, before == null ? l.goalsCreated : l.goalsUpdated);
    } catch (e) {
      if (!mounted) return;
      // A refusal about a field goes under it; anything else to a snack.
      final refusal = e is ApiException ? e : null;
      final nameError = refusal?.fieldMessage(l, 'name');
      final targetError = refusal?.fieldMessage(l, 'target_value');
      final currentError = refusal?.fieldMessage(l, 'current_value');
      final relatedError = refusal?.fieldMessage(l, 'related');
      setState(() {
        _saving = false;
        _nameError = nameError;
        _targetError = targetError;
        _currentError = currentError;
        _relatedError = relatedError;
      });
      if ([nameError, targetError, currentError, relatedError]
          .every((m) => m == null)) {
        showAppSnack(
          context,
          failureMessage(
            e,
            l,
            fallback: before == null ? l.goalsCreateFailed : l.goalsSaveFailed,
          ),
          isError: true,
        );
      } else {
        Haptics.danger();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loaded up front for the linked account / habit pickers.
    ref.watch(accountsProvider);
    ref.watch(habitsProvider);
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final before = _editing;
    final typeChanged = before != null && before.targetType != _type;

    return FormScaffold(
      title: before == null ? l.goalsFormNewTitle : l.goalsFormEditTitle,
      actionLabel: before == null ? l.goalsFormSubmit : l.actionSave,
      onAction: _submit,
      busy: _saving,
      dirty: _dirty && !_saving,
      children: [
        FormLabel(l.goalsFormType),
        // Scrolls rather than overflows with large text.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedPill<String>(
            options: [
              ('custom', l.goalsFormTypeCustom),
              ('habit', l.goalsFormTypeHabit),
              ('financial', l.goalsFormTypeFinancial),
            ],
            selected: _type,
            onChanged: _setType,
          ),
        ),
        if (typeChanged && before.related != null) ...[
          const SizedBox(height: 8),
          Text(
            l.goalsFormTypeChangeNote,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          autofocus: before == null,
          maxLength: goalNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.goalsFormName,
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameError = null),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _target,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l.goalsFormTargetValue,
                  errorText: _targetError,
                ),
                onChanged: (_) => setState(() => _targetError = null),
              ),
            ),
            if (_type != 'financial') ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unit,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l.goalsFormUnit,
                    hintText: l.goalsFormUnitHint,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
        if (_manual) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _current,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.goalsFormCurrentValue,
              hintText: '0',
              errorText: _currentError,
            ),
            onChanged: (_) => setState(() => _currentError = null),
          ),
        ],
        if (_type != 'custom') ...[
          const SizedBox(height: 16),
          FormPickerRow(
            icon: _type == 'financial'
                ? Icons.account_balance_wallet_outlined
                : Icons.repeat,
            label: _type == 'financial'
                ? l.goalsFormLinkedAccount
                : l.goalsFormLinkedHabit,
            value: _related == 'none' ? l.labelNone : _relatedLabel ?? '…',
            errorText: _relatedError,
            onTap: _pickLink,
          ),
          if (_related == 'none') ...[
            const SizedBox(height: 6),
            Text(
              _type == 'financial'
                  ? l.goalsNoAccountLinked
                  : l.goalsNoHabitLinked,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ],
        ],
        const SizedBox(height: 16),
        FormPickerRow(
          icon: Icons.event_outlined,
          label: l.goalsFormEndDate,
          value: _deadline == null
              ? l.goalsFormNoDeadline
              : formatDate(_deadline!, withYear: true),
          onTap: _pickDeadline,
        ),
        if (_deadline != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _deadline = null),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(l.goalsFormClearDeadline),
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.goalsFormDescription),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FormLabel(l.goalsFormColor),
        ColorSwatchRow(
          selected: _color,
          onChanged: (hex) => setState(() => _color = hex),
        ),
      ],
    );
  }
}
