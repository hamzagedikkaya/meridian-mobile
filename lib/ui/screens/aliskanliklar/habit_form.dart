import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../models/goal.dart';
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
Future<void> openHabitForm(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    slideUpModalRoute((_) => const HabitFormScreen()),
  );
}

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
  const HabitFormScreen({super.key});

  @override
  ConsumerState<HabitFormScreen> createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends ConsumerState<HabitFormScreen> {
  final _name = TextEditingController();
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
    final bundle = ref.read(goalsProvider).value?.data;
    final goals = bundle?.active ?? const <Goal>[];
    // -1 is the explicit "none" sentinel so a dismiss (null) can be told apart
    // from clearing an already-chosen goal.
    const noneSentinel = -1;
    final options = <PickerOption<int>>[
      const PickerOption(value: noneSentinel, label: 'Yok'),
      for (final g in goals)
        PickerOption(value: g.id, label: g.name, color: hexColor(g.color)),
    ];
    final picked = await showPickerSheet<int>(
      context,
      title: 'Hedefe bağla',
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
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Bir ad gir');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      await ref.read(repositoryProvider).createHabit(HabitInput(
            name: name,
            frequency: _frequency,
            targetCount: _target,
            color: _color,
            goalId: _goalId,
          ));
      ref.invalidate(habitsProvider);
      Haptics.success();
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Alışkanlık eklendi ✓');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, 'Kaydedilemedi, tekrar dene', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final targetLabel = _frequency == 'daily' ? 'Günlük hedef' : 'Dönem hedefi';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Yeni alışkanlık', style: text.headlineMedium),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Ad',
              hintText: 'ör. Su iç, koşu, kitap oku',
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 24),
          Text('Sıklık', style: text.titleSmall),
          const SizedBox(height: 12),
          SegmentedPill<String>(
            options: const [
              ('daily', 'Günlük'),
              ('weekly', 'Haftalık'),
              ('monthly', 'Aylık'),
            ],
            selected: _frequency,
            onChanged: (v) => setState(() => _frequency = v),
          ),
          const SizedBox(height: 24),
          Text(targetLabel, style: text.titleSmall),
          const SizedBox(height: 12),
          _targetStepper(context),
          const SizedBox(height: 24),
          Text('Renk', style: text.titleSmall),
          const SizedBox(height: 12),
          _colorRow(),
          const SizedBox(height: 24),
          Text('Hedef bağlantısı (opsiyonel)', style: text.titleSmall),
          const SizedBox(height: 12),
          _goalRow(context),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Kaydet',
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
                _goalName ?? 'Yok',
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
