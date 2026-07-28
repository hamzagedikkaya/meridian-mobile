import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../models/goal.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../data/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_ring.dart';
import 'goal_ui.dart';

final _goalDetailProvider =
    FutureProvider.autoDispose.family<Goal, int>((ref, id) async {
  return ref.watch(repositoryProvider).fetchGoal(id);
});

class HedefDetailScreen extends ConsumerStatefulWidget {
  final int goalId;

  const HedefDetailScreen({super.key, required this.goalId});

  @override
  ConsumerState<HedefDetailScreen> createState() => _HedefDetailScreenState();
}

class _HedefDetailScreenState extends ConsumerState<HedefDetailScreen> {
  bool _busy = false;
  bool _recalcLoading = false;

  void _invalidate() {
    ref.invalidate(_goalDetailProvider(widget.goalId));
    ref.invalidate(goalsProvider);
  }

  Future<void> _mutate(Future<Goal> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await action();
      _invalidate();
      if (updated.progressPercent >= 100) Haptics.celebrate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('İşlem başarısız')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recalculate() async {
    if (_recalcLoading) return;
    setState(() => _recalcLoading = true);
    try {
      final results = await Future.wait([
        ref.read(repositoryProvider).goalRecalculate(widget.goalId),
        Future.delayed(const Duration(milliseconds: 300)),
      ]);
      _invalidate();
      if ((results.first as Goal).progressPercent >= 100) Haptics.celebrate();
    } catch (_) {
      // Keep the last-good value; the provider stays populated.
    } finally {
      if (mounted) setState(() => _recalcLoading = false);
    }
  }

  Future<void> _confirmAbandon() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hedef bırakılsın mı?',
      message: 'Bu hedefi bırakıldı olarak işaretleyeceksin.',
      confirmLabel: 'Bırak',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(repositoryProvider).abandonGoal(widget.goalId);
      _invalidate();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('İşlem başarısız')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(_goalDetailProvider(widget.goalId));
    final goal = async.value;

    return Scaffold(
      appBar: AppBar(title: Text('Hedef', style: text.headlineMedium)),
      body: goal == null
          ? (async.isLoading
              ? Center(
                  child: CircularProgressIndicator(color: context.nok.gold),
                )
              : EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Hedef yüklenemedi',
                  actionLabel: 'Tekrar dene',
                  onAction: () =>
                      ref.invalidate(_goalDetailProvider(widget.goalId)),
                ))
          : _content(goal),
    );
  }

  Widget _content(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = goalColor(goal.color);
    final pct = goal.progressPercent.clamp(0, 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Center(
          child: Hero(
            tag: 'goal-ring-${goal.id}',
            flightShuttleBuilder: goalRingFlightShuttle,
            child: ProgressRing(
              value: pct / 100,
              color: color,
              size: 160,
              strokeWidth: 10,
              center: Text(
                '%$pct',
                style: text.displayMedium!.copyWith(fontFeatures: tabularFigures),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(goal.name, style: text.titleLarge, textAlign: TextAlign.center),
        if (goal.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            goal.description,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            _StatTile(label: 'Durum', value: goalStatusLabel(goal.status)),
            const SizedBox(width: 12),
            _StatTile(
              label: 'Bitiş',
              value: goal.deadline == null ? '—' : formatDate(goal.deadline!),
            ),
            const SizedBox(width: 12),
            _StatTile(label: 'Kalan gün', value: '${goal.daysRemaining}'),
          ],
        ),
        const SizedBox(height: 24),
        _actionCard(goal),
        if (goal.status == 'active') ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: _confirmAbandon,
              child: Text(
                'Bırakıldı olarak işaretle',
                style: text.labelLarge!.copyWith(color: c.inkLow),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionCard(Goal goal) => switch (goal.targetType) {
        'habit' => _habitCard(goal),
        'financial' => _financialCard(goal),
        _ => _customCard(goal),
      };

  Widget _customCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('İlerleme', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            goalProgressLabel(goal),
            style: text.bodyMedium!
                .copyWith(color: c.inkMid, fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final d in const [-10, -1, 1, 10]) ...[
                Expanded(child: _StepButton(delta: d, onTap: () => _step(goal, d))),
                if (d != 10) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _DirectValueField(
            initial: goal.currentValue,
            onSubmit: (v) =>
                _mutate(() => ref.read(repositoryProvider).goalUpdateProgress(
                      goal.id,
                      currentValue: v,
                    )),
          ),
        ],
      ),
    );
  }

  void _step(Goal goal, int delta) {
    Haptics.tick();
    _mutate(() => ref
        .read(repositoryProvider)
        .goalUpdateProgress(goal.id, delta: delta));
  }

  Widget _habitCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final streak = goal.related?.currentStreak;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alışkanlık ilerlemesi', style: text.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 20, color: c.goldBright),
              const SizedBox(width: 6),
              Text(
                streak == null ? '—' : '$streak günlük seri',
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${formatGoalNumber(goal.currentValue)} / ${formatGoalNumber(goal.targetValue)} gün',
            style: text.headlineMedium!.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }

  Widget _financialCard(Goal goal) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final related = goal.related;
    final meta = goalMoneyMeta(goal);

    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            related?.name ?? 'Bağlı hesap',
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('Güncel bakiye', style: text.bodySmall!.copyWith(color: c.inkMid)),
          const SizedBox(height: 8),
          if (related?.balanceCents != null)
            MoneyText(
              related!.balanceCents!,
              currency: related.currency ?? meta.currency,
              subunitToUnit: related.subunitToUnit ?? meta.subunit,
              variant: MoneyVariant.title,
            )
          else
            Text(
              formatGoalMoney(goal, goal.currentValue),
              style: text.titleLarge!.copyWith(fontFeatures: tabularFigures),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Yenile',
              loading: _recalcLoading,
              onPressed: _recalculate,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: text.titleMedium!.copyWith(fontFeatures: tabularFigures),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final int delta;
  final VoidCallback onTap;

  const _StepButton({required this.delta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Text(
          delta > 0 ? '+$delta' : '$delta',
          style: text.titleSmall!.copyWith(fontFeatures: tabularFigures),
        ),
      ),
    );
  }
}

class _DirectValueField extends StatefulWidget {
  final double initial;
  final ValueChanged<num> onSubmit;

  const _DirectValueField({required this.initial, required this.onSubmit});

  @override
  State<_DirectValueField> createState() => _DirectValueFieldState();
}

class _DirectValueFieldState extends State<_DirectValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatGoalNumber(widget.initial));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (v != null) {
      FocusScope.of(context).unfocus();
      widget.onSubmit(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Değer gir'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
