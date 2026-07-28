import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../data/providers.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/picker_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/segmented_pill.dart';
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _pickAccount() async {
    final accounts = await ref.read(repositoryProvider).fetchAccounts();
    if (!mounted) return;
    final id = await showPickerSheet<int>(
      context,
      title: 'Bağlı hesap',
      options: [
        for (final a in accounts)
          PickerOption(value: a.id, label: a.name, color: goalColor(a.color)),
      ],
    );
    if (id == null) return;
    final account = accounts.firstWhere((a) => a.id == id);
    setState(() {
      _related = 'Account-$id';
      _relatedLabel = account.name;
    });
  }

  Future<void> _pickHabit() async {
    final bundle = await ref.read(repositoryProvider).fetchHabits();
    if (!mounted) return;
    final id = await showPickerSheet<int>(
      context,
      title: 'Bağlı alışkanlık',
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
    final name = _name.text.trim();
    final target = double.tryParse(_target.text.trim().replaceAll(',', '.'));
    setState(() {
      _nameError = name.isEmpty ? 'Hedef adı gerekli' : null;
      _targetError = (target == null || target <= 0) ? 'Geçerli bir hedef değer gir' : null;
    });
    if (_nameError != null || _targetError != null) return;

    setState(() => _saving = true);
    try {
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
      ref.invalidate(goalsProvider);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop();
      showAppSnack(context, 'Hedef oluşturuldu ✓');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Hedef oluşturulamadı', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Yeni hedef', style: text.headlineMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Hedef adı',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
            ),
            const SizedBox(height: 24),
            Text('Tür', style: text.labelMedium),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedPill<String>(
                options: const [
                  ('custom', 'Özel'),
                  ('habit', 'Alışkanlık'),
                  ('financial', 'Finansal'),
                ],
                selected: _type,
                onChanged: _setType,
              ),
            ),
            const SizedBox(height: 24),
            Text('Renk', style: text.labelMedium),
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
                      labelText: 'Hedef değer',
                      errorText: _targetError,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Birim',
                      hintText: 'kg · gün · TRY',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RowTile(
              label: 'Bitiş tarihi',
              value: _deadline == null ? 'Seç' : formatDate(_deadline!, withYear: true),
              onTap: _pickDeadline,
            ),
            if (_type == 'financial')
              _RowTile(
                label: 'Bağlı hesap',
                value: _relatedLabel ?? 'Seç (isteğe bağlı)',
                onTap: _pickAccount,
              ),
            if (_type == 'habit')
              _RowTile(
                label: 'Bağlı alışkanlık',
                value: _relatedLabel ?? 'Seç (isteğe bağlı)',
                onTap: _pickHabit,
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Hedef oluştur',
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
            const Spacer(),
            Text(value, style: text.bodyMedium!.copyWith(color: c.inkMid)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: c.inkLow),
          ],
        ),
      ),
    );
  }
}
