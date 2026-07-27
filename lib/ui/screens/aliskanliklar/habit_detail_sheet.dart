import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/providers.dart';
import '../../../models/habit.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import 'widgets/chain_row.dart';
import 'widgets/habit_visuals.dart';
import 'widgets/mini_heatmap.dart';

/// Habit detail bottom sheet (design §4.5): 30-day chain + stats grid + 84-day
/// mini-heatmap + archive action. Loads `fetchHabit(id, days: 84)`.
Future<void> showHabitDetailSheet(
  BuildContext context,
  Habit initial,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _HabitDetailSheet(initial: initial),
  );
}

class _HabitDetailSheet extends ConsumerStatefulWidget {
  final Habit initial;
  const _HabitDetailSheet({required this.initial});

  @override
  ConsumerState<_HabitDetailSheet> createState() => _HabitDetailSheetState();
}

class _HabitDetailSheetState extends ConsumerState<_HabitDetailSheet> {
  late Future<Habit> _future;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(repositoryProvider).fetchHabit(widget.initial.id, days: 84);
  }

  Future<void> _archive() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Alışkanlık arşivlensin mi?',
      message: '${widget.initial.name} listeden kaldırılacak.',
      confirmLabel: 'Arşivle',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _archiving = true);
    try {
      await ref.read(repositoryProvider).archiveHabit(widget.initial.id);
      ref.invalidate(habitsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnack(context, 'Arşivlendi');
    } catch (_) {
      if (!mounted) return;
      setState(() => _archiving = false);
      showAppSnack(context, 'Arşivlenemedi, tekrar dene', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: FutureBuilder<Habit>(
        future: _future,
        builder: (context, snap) {
          final habit = snap.data ?? widget.initial;
          final loading = snap.connectionState != ConnectionState.done;
          return _content(context, habit, loading);
        },
      ),
    );
  }

  Widget _content(BuildContext context, Habit habit, bool loading) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final color = hexColor(habit.color);
    final rate = habit.completionRate30d <= 1
        ? (habit.completionRate30d * 100).round()
        : habit.completionRate30d.round();
    final chain30 =
        habit.chain.length > 30 ? habit.chain.sublist(habit.chain.length - 30) : habit.chain;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(habit.name, style: text.headlineMedium)),
            ],
          ),
          if (habit.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(habit.description,
                style: text.bodyMedium!.copyWith(color: c.inkMid)),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              _stat(context, 'Seri', '🔥 ${habit.currentStreak}'),
              _stat(context, 'Rekor', '${habit.longestStreak}'),
              _stat(context, '30g oranı', '%$rate'),
            ],
          ),
          const SizedBox(height: 24),
          Text('Son 30 gün', style: text.titleSmall),
          const SizedBox(height: 12),
          ChainRow(chain: chain30, color: color),
          const SizedBox(height: 12),
          _legend(context, color),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Son 84 gün', style: text.titleSmall),
              const SizedBox(width: 8),
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: c.gold),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MiniHeatmap(chain: habit.chain, color: color),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _archiving ? null : _archive,
            icon: _archiving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.error),
                  )
                : Icon(Icons.archive_outlined, size: 18, color: c.error),
            label: Text('Arşivle', style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: text.titleLarge!.copyWith(fontFeatures: tabularFigures)),
          const SizedBox(height: 2),
          Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    Widget item(Color fill, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: fill, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 6),
            Text(label, style: text.labelSmall!.copyWith(color: c.inkMid)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(color, 'Tamam'),
        item(color.withValues(alpha: 0.4), 'Kısmi'),
        item(c.surface2, 'Eksik'),
      ],
    );
  }
}
