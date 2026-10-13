import 'dart:math' as math;

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
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/entity_color.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/color_swatches.dart';
import '../../widgets/form_scaffold.dart';
import '../../widgets/nok_chip.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/slide_up_route.dart';
import '../finance/account_form.dart';
import 'goal_kind_tile.dart';
import 'goal_ui.dart';
import 'goal_value_sheet.dart';

/// The longest goal name the server takes (meridian `Goal`).
const goalNameMaxLength = 100;

/// Opens the goal form: a new goal — of [type] (`financial`, `habit`,
/// `custom`) when given; a habit goal already linked to habit [habitId]
/// when that is given (the habit's "Bu alışkanlık için hedef koy") — or,
/// with [goal], an edit of it. Resolves to the goal saved, or null when it
/// was closed without saving.
Future<Goal?> openGoalForm(
  BuildContext context, {
  Goal? goal,
  String? type,
  int? habitId,
}) {
  return Navigator.of(context, rootNavigator: true).push<Goal>(
    slideUpModalRoute(
      (_) => GoalFormScreen(
        goal: goal,
        initialType: type,
        initialHabitId: habitId,
      ),
    ),
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
    final List<Account>? all = await lookup(
      () => ref.read(accountsProvider.future),
    );
    if (all == null || !context.mounted) return null;
    final accounts = [
      for (final a in all)
        if (!a.archived) a,
    ];
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
                  value: a.id,
                  label: a.name,
                  color: goalColor(a.color),
                ),
              PickerOption(
                value: created,
                label: l.accountNew,
                icon: Icons.add,
              ),
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
  final HabitsBundle? bundle = await lookup(
    () => ref.read(habitsProvider.future),
  );
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

/// The deadline choices of the form: none, 1, 3 or 6 months from today,
/// or a picked date.
enum _Deadline { none, oneMonth, threeMonths, sixMonths, date }

/// [from] moved [months] ahead, on the same day of the month — or the
/// month's last day when it is shorter (31 Jan + 1 month = 28/29 Feb).
DateTime _monthsAhead(DateTime from, int months) {
  final last = DateTime(from.year, from.month + months + 1, 0).day;
  return DateTime(from.year, from.month + months, math.min(from.day, last));
}

/// Full-screen goal form (design-analysis §7.11, IA-21): the kind first —
/// savings, habit or custom, as three cards — then the name, the target on
/// the keypad (money for savings), the unit (not for savings), the link
/// (an account or a habit), the deadline as chips (none · 1 · 3 · 6 months
/// · a date) and, folded under "Daha fazla", the description and colour.
///
/// With [goal] it edits that goal — every field prefilled, its link kept
/// unless changed here — and sends only what changed.
class GoalFormScreen extends ConsumerStatefulWidget {
  final Goal? goal;

  /// The kind a new goal starts as; custom by default — habit when
  /// [initialHabitId] is given.
  final String? initialType;

  /// A new goal starts linked to this habit (`related: Habit-<id>`), as a
  /// habit goal.
  final int? initialHabitId;

  const GoalFormScreen({
    super.key,
    this.goal,
    this.initialType,
    this.initialHabitId,
  });

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  Goal? get _editing => widget.goal;

  /// The habit a new goal starts linked to; never for an edit.
  int? get _habitId => widget.goal == null ? widget.initialHabitId : null;

  late final _name = TextEditingController(text: _editing?.name ?? '');
  late final _description = TextEditingController(
    text: _editing?.description ?? '',
  );
  late final _unit = TextEditingController(text: _editing?.unit ?? '');

  /// The target, in major units; null until one is entered.
  late double? _target = _editing?.targetValue;

  /// The progress so far of a goal logged by hand; null when not entered.
  late double? _current = _editing == null || !_editing!.isManual
      ? null
      : _editing!.currentValue;

  late String _type =
      _editing?.targetType ??
      (_habitId != null ? 'habit' : widget.initialType ?? 'custom');
  late String _color = _editing?.color ?? recordSwatches.first;
  late DateTime? _deadline = _editing?.deadline;
  late String _related =
      _editing?.relatedRef ?? (_habitId != null ? 'Habit-$_habitId' : 'none');
  late String? _relatedLabel = _editing?.related?.name;

  /// The description and colour are shown: when editing a goal that has a
  /// description, or once "Daha fazla" is tapped.
  late bool _more = _editing?.description.trim().isNotEmpty ?? false;

  final _nameKey = GlobalKey();
  final _targetKey = GlobalKey();

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
    super.dispose();
  }

  /// Progress logged by hand: a custom goal, or a habit goal without a
  /// habit. Only those take a starting value.
  bool get _manual =>
      _type == 'custom' || (_type == 'habit' && _related == 'none');

  bool get _financial => _type == 'financial';

  /// The name of the habit [_related] points at, from the habits loaded —
  /// for a link given up front (`initialHabitId`), which comes without it.
  String? get _linkedHabitName {
    if (!_related.startsWith('Habit-')) return null;
    final id = int.tryParse(_related.substring(6));
    final habits = ref.read(habitsProvider).value?.data.habits;
    return habits?.where((h) => h.id == id).firstOrNull?.name;
  }

  void _setType(String type) {
    if (type == _type) return;
    final before = _editing;
    setState(() {
      _type = type;
      // Back to the goal's own type: its link comes back with it.
      if (before != null && type == before.targetType) {
        _related = before.relatedRef;
        _relatedLabel = before.related?.name;
      } else if (before == null && _habitId != null && type == 'habit') {
        // Back to the habit it was opened for.
        _related = 'Habit-$_habitId';
        _relatedLabel = null;
      } else {
        _related = 'none';
        _relatedLabel = null;
      }
      _relatedError = null;
    });
  }

  /// What a financial goal is counted in: the goal's own currency when it
  /// already is one, else the linked account's, else the user's.
  ({String currency, int subunit}) get _money {
    final before = _editing;
    if (before != null && before.targetType == 'financial') {
      return goalMoneyMeta(before);
    }
    if (_related.startsWith('Account-')) {
      final id = int.tryParse(_related.substring(8));
      final accounts = ref.read(accountsProvider).value?.data;
      final account = accounts?.where((a) => a.id == id).firstOrNull;
      if (account != null) {
        return (currency: account.currency, subunit: account.subunitToUnit);
      }
    }
    final currency = ref.read(currentUserProvider)?.currency ?? 'TRY';
    return (currency: currency, subunit: currency == 'GAU' ? 1 : 100);
  }

  _Deadline get _deadlineChoice {
    final d = _deadline;
    if (d == null) return _Deadline.none;
    final today = ref.read(currentDayProvider);
    bool sameDay(DateTime a) =>
        a.year == d.year && a.month == d.month && a.day == d.day;
    if (sameDay(_monthsAhead(today, 1))) return _Deadline.oneMonth;
    if (sameDay(_monthsAhead(today, 3))) return _Deadline.threeMonths;
    if (sameDay(_monthsAhead(today, 6))) return _Deadline.sixMonths;
    return _Deadline.date;
  }

  void _setMonths(int months) {
    final today = ref.read(currentDayProvider);
    setState(() => _deadline = _monthsAhead(today, months));
  }

  Future<void> _pickDeadline() async {
    final now = ref.read(currentDayProvider);
    final initial = _deadline ?? _monthsAhead(now, 1);
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
    unit: _financial ? _financialUnit : _unit.text,
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
    final input = _inputWith(target: _target, current: _current);
    final before = _editing;
    if (before != null) return input.changesFrom(before).isNotEmpty;
    return input.name.isNotEmpty ||
        _target != null ||
        _description.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l = context.l10n;
    final name = _name.text.trim();
    final target = _target;
    final current = _current;
    setState(() {
      _nameError = name.isEmpty ? l.goalsFormNameRequired : null;
      _targetError = (target == null || target <= 0)
          ? l.goalsFormTargetRequired
          : null;
      _currentError = null;
    });
    final invalid = _nameError != null
        ? _nameKey
        : _targetError != null
        ? _targetKey
        : null;
    if (invalid != null) {
      await FormScaffold.revealInvalid(invalid);
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
      Haptics.confirm();
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
      if ([
        nameError,
        targetError,
        currentError,
        relatedError,
      ].every((m) => m == null)) {
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
        await FormScaffold.revealInvalid(
          nameError != null ? _nameKey : _targetKey,
        );
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
        // 1. The kind decides every other field.
        FormLabel(l.goalsFormType),
        for (final type in goalKinds) ...[
          GoalKindTile(
            type: type,
            selected: type == _type,
            onTap: () {
              if (type != _type) Haptics.tick();
              _setType(type);
            },
          ),
          if (type != goalKinds.last) const SizedBox(height: Gap.sm),
        ],
        if (typeChanged && before.related != null) ...[
          const SizedBox(height: Gap.sm),
          Text(
            l.goalsFormTypeChangeNote,
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
        const SizedBox(height: Gap.xl),
        // 2. The name.
        TextField(
          key: _nameKey,
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
        const SizedBox(height: Gap.sm),
        // 3. The target, on the keypad.
        KeyedSubtree(key: _targetKey, child: _targetField(l)),
        // 4. The unit: not for money.
        if (!_financial) ...[
          const SizedBox(height: Gap.lg),
          TextField(
            controller: _unit,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l.goalsFormUnit,
              hintText: l.goalsFormUnitHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (_manual) ...[
          const SizedBox(height: Gap.lg),
          GoalValueField(
            label: l.goalsFormCurrentValue,
            value: _current,
            kind: GoalValueKind.count(_unit.text.trim()),
            errorText: _currentError,
            onChanged: (v) => setState(() {
              _current = v;
              _currentError = null;
            }),
          ),
        ],
        // 5. The link: an account or a habit.
        if (_type != 'custom') ...[
          const SizedBox(height: Gap.lg),
          FormPickerRow(
            icon: _financial
                ? Icons.account_balance_wallet_outlined
                : Icons.repeat_rounded,
            label: _financial
                ? l.goalsFormLinkedAccount
                : l.goalsFormLinkedHabit,
            value: _related == 'none'
                ? l.labelNone
                : _relatedLabel ?? _linkedHabitName ?? '…',
            errorText: _relatedError,
            onTap: _pickLink,
          ),
          if (_related == 'none') ...[
            const SizedBox(height: 6),
            Text(
              _financial ? l.goalsNoAccountLinked : l.goalsNoHabitLinked,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ],
        ],
        // 6. The deadline, as chips.
        const SizedBox(height: Gap.xl),
        FormLabel(l.goalsFormEndDate),
        _deadlineChips(l),
        // 7. More: the description and the colour.
        const SizedBox(height: Gap.md),
        _moreToggle(l),
        if (_more) ...[
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(labelText: l.goalsFormDescription),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Gap.xxl),
          FormLabel(l.goalsFormColor),
          ColorSwatchRow(
            selected: _color,
            onChanged: (hex) => setState(() => _color = hex),
          ),
        ],
      ],
    );
  }

  Widget _targetField(AppL10n l) {
    void changed(double v) => setState(() {
      _target = v;
      _targetError = null;
    });
    if (_financial) {
      final money = _money;
      final target = _target;
      return AmountField(
        label: l.goalsFormTargetValue,
        minorUnits: target == null ? null : (target * money.subunit).round(),
        currency: money.currency,
        subunitToUnit: money.subunit,
        errorText: _targetError,
        onChanged: (cents) => changed(cents / money.subunit),
      );
    }
    return GoalValueField(
      label: l.goalsFormTargetValue,
      value: _target,
      kind: GoalValueKind.count(_unit.text.trim()),
      errorText: _targetError,
      onChanged: changed,
    );
  }

  Widget _deadlineChips(AppL10n l) {
    final choice = _deadlineChoice;
    final deadline = _deadline;
    NokChip chip(
      String label,
      _Deadline value,
      VoidCallback onTap, {
      IconData? icon,
    }) => NokChip(
      label: label,
      icon: icon,
      exclusive: true,
      selected: choice == value,
      // The date chip opens the picker again; the others do nothing
      // once chosen.
      onTap: choice == value && value != _Deadline.date ? null : onTap,
    );
    return Wrap(
      spacing: Gap.sm,
      children: [
        chip(
          l.goalsFormNoDeadline,
          _Deadline.none,
          () => setState(() => _deadline = null),
        ),
        chip(l.goalsDeadlineMonths(1), _Deadline.oneMonth, () => _setMonths(1)),
        chip(
          l.goalsDeadlineMonths(3),
          _Deadline.threeMonths,
          () => _setMonths(3),
        ),
        chip(
          l.goalsDeadlineMonths(6),
          _Deadline.sixMonths,
          () => _setMonths(6),
        ),
        chip(
          choice == _Deadline.date && deadline != null
              ? formatDate(deadline, withYear: true)
              : l.goalsDeadlinePick,
          _Deadline.date,
          _pickDeadline,
          icon: Icons.event_outlined,
        ),
      ],
    );
  }

  Widget _moreToggle(AppL10n l) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      expanded: _more,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => setState(() => _more = !_more),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.goalsFormMore,
                  style: text.titleSmall!.copyWith(color: c.inkMid),
                ),
              ),
              AnimatedRotation(
                turns: _more ? 0.5 : 0,
                duration: Motion.orInstant(context, Motion.quick),
                child: Icon(Icons.expand_more_rounded, color: c.inkMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
