import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
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
import '../../widgets/picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/segmented_pill.dart';
import '../finance/account_form.dart';
import 'goal_ui.dart';

const _swatches = [
  '#D4A853',
  '#6B8E5A',
  '#6B8FA0',
  '#B85450',
  '#8B5A00',
  '#7A5C9E',
  '#5A9E8B',
  '#D4A574',
];

/// Full-screen create form → repository.createGoal (design §4.6).
class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key});

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _unit = TextEditingController();
  final _target = TextEditingController();

  String _type = 'custom';
  String _color = _swatches.first;
  DateTime? _deadline;
  String _related = 'none';
  String? _relatedLabel;

  bool _saving = false;
  String? _nameError;
  String? _targetError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _unit.dispose();
    _target.dispose();
    super.dispose();
  }

  void _setType(String type) {
    setState(() {
      _type = type;
      _related = 'none';
      _relatedLabel = null;
    });
  }

  Future<void> _pickDeadline() async {
    final now = ref.read(currentDayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  /// The pickers read the same cached lists every screen shares (watched in
  /// build, so already loaded and kept current), and say so when the server
  /// cannot be reached instead of throwing.
  Future<T?> _lookup<T>(Future<Fetched<T>> Function() load) async {
    try {
      return (await load()).data;
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.localized(context.l10n), isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnack(context, context.l10n.errNoConnection, isError: true);
      }
    }
    return null;
  }

  /// Links an account — an active one, or one made here: with no account
  /// yet, the account form opens straight away (a savings goal needs
  /// somewhere to save).
  Future<void> _pickAccount() async {
    final l = context.l10n;
    final List<Account>? all =
        await _lookup(() => ref.read(accountsProvider.future));
    if (all == null || !mounted) return;
    final accounts = [for (final a in all) if (!a.archived) a];
    const newAccount = -1;
    final id = accounts.isEmpty
        ? newAccount
        : await showPickerSheet<int>(
            context,
            title: l.goalsFormLinkedAccount,
            selected: int.tryParse(_related.replaceFirst('Account-', '')),
            options: [
              for (final a in accounts)
                PickerOption(
                    value: a.id, label: a.name, color: goalColor(a.color)),
              PickerOption(
                value: newAccount,
                label: l.accountNew,
                icon: Icons.add,
              ),
            ],
          );
    if (id == null || !mounted) return;
    final account = id == newAccount
        ? await openAccountForm(context)
        : accounts.firstWhere((a) => a.id == id);
    if (account == null || !mounted) return;
    setState(() {
      _related = 'Account-${account.id}';
      _relatedLabel = account.name;
    });
  }

  Future<void> _pickHabit() async {
    final HabitsBundle? bundle =
        await _lookup(() => ref.read(habitsProvider.future));
    if (bundle == null || !mounted) return;
    final id = await showPickerSheet<int>(
      context,
      title: context.l10n.goalsFormLinkedHabit,
      options: [
        for (final h in bundle.habits)
          PickerOption(value: h.id, label: h.name, color: goalColor(h.color)),
      ],
    );
    if (id == null) return;
    final habit = bundle.habits.firstWhere((h) => h.id == id);
    setState(() {
      _related = 'Habit-$id';
      _relatedLabel = habit.name;
    });
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final name = _name.text.trim();
    final target = double.tryParse(_target.text.trim().replaceAll(',', '.'));
    setState(() {
      _nameError = name.isEmpty ? l.goalsFormNameRequired : null;
      _targetError = (target == null || target <= 0)
          ? l.goalsFormTargetRequired
          : null;
    });
    if (_nameError != null || _targetError != null) return;

    setState(() => _saving = true);
    try {
      // The repository reports the new goal; the Goals grid and Today
      // refresh from that, even if this form is closed before it answers.
      await ref.read(repositoryProvider).createGoal(
            GoalInput(
              name: name,
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              targetType: _type,
              color: _color,
              unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
              deadline: _deadline,
              targetValue: target,
              related: _related,
            ),
          );
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop();
      showAppSnack(context, l.goalsCreated);
    } catch (e) {
      if (!mounted) return;
      // A refusal about a field goes under it; anything else to a snack.
      final refusal = e is ApiException ? e : null;
      final nameError = refusal?.fieldMessage(l, 'name');
      final targetError = refusal?.fieldMessage(l, 'target_value');
      setState(() {
        _saving = false;
        _nameError = nameError;
        _targetError = targetError;
      });
      if (nameError == null && targetError == null) {
        showAppSnack(
          context,
          failureMessage(e, l, fallback: l.goalsCreateFailed),
          isError: true,
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l.goalsFormNewTitle, style: text.headlineMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.goalsFormName,
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration:
                  InputDecoration(labelText: l.goalsFormDescription),
            ),
            const SizedBox(height: 24),
            Text(l.goalsFormType, style: text.labelMedium),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
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
            const SizedBox(height: 24),
            Text(l.goalsFormColor, style: text.labelMedium),
            const SizedBox(height: 8),
            Wrap(
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
                        color: goalColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == hex ? c.inkHi : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l.goalsFormTargetValue,
                      errorText: _targetError,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: InputDecoration(
                      labelText: l.goalsFormUnit,
                      hintText: l.goalsFormUnitHint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RowTile(
              label: l.goalsFormEndDate,
              value: _deadline == null
                  ? l.actionSelect
                  : formatDate(_deadline!, withYear: true),
              onTap: _pickDeadline,
            ),
            if (_type == 'financial')
              _RowTile(
                label: l.goalsFormLinkedAccount,
                value: _relatedLabel ?? l.actionSelectOptional,
                onTap: _pickAccount,
              ),
            if (_type == 'habit')
              _RowTile(
                label: l.goalsFormLinkedHabit,
                value: _relatedLabel ?? l.actionSelectOptional,
                onTap: _pickHabit,
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: l.goalsFormSubmit,
                loading: _saving,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _RowTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(label, style: text.titleSmall),
            const SizedBox(width: 12),
            // A long account or habit name wraps instead of overflowing.
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: c.inkLow),
          ],
        ),
      ),
    );
  }
}
