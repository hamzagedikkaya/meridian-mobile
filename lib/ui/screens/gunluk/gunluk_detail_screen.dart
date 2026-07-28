import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../models/journal.dart';
import '../../../theme/app_colors.dart';
import '../../../ui/widgets/app_snackbar.dart';
import '../../../ui/widgets/confirm_dialog.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/skeletons.dart';
import 'journal_editor.dart';
import 'journal_providers.dart';
import 'widgets/energy_dots.dart';
import 'widgets/journal_card.dart';
import 'widgets/mood.dart';

class GunlukDetailScreen extends ConsumerWidget {
  final int entryId;
  const GunlukDetailScreen({super.key, required this.entryId});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Kayıt silinsin mi?',
      message: 'Bu günlük kaydı kalıcı olarak silinecek.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    Haptics.danger();
    try {
      await ref.read(repositoryProvider).deleteJournalEntry(entryId);
      ref.invalidate(journalProvider);
      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journalEntryProvider(entryId));
    final entry = async.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Günlük'),
        actions: [
          if (entry != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  openJournalEditor(context, entry: entry);
                } else if (v == 'delete') {
                  _delete(context, ref);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                PopupMenuItem(value: 'delete', child: Text('Sil')),
              ],
            ),
        ],
      ),
      body: async.hasError && entry == null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: 'Kayıt yüklenemedi',
              subtitle: 'Aynı Wi-Fi ağında olduğundan emin ol',
              actionLabel: 'Tekrar dene',
              onAction: () => ref.invalidate(journalEntryProvider(entryId)),
            )
          : entry == null
              ? _loading(context)
              : _DetailBody(entry: entry),
    );
  }

  Widget _loading(BuildContext context) {
    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('25 Mayıs 2026',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          Text(
            'Bugün oldukça sakin geçti. Sabah yürüyüşe çıktım ve gün boyu '
            'enerjim yüksek kaldı. Akşam biraz kitap okudum ve erken uyudum.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final JournalEntry entry;
  const _DetailBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final hasTitle = (entry.title ?? '').trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(formatWeekday(entry.date),
            style: text.labelMedium!.copyWith(color: c.inkMid)),
        const SizedBox(height: 4),
        Text(formatDate(entry.date, withYear: true),
            style: text.headlineLarge),
        if (hasTitle) ...[
          const SizedBox(height: 8),
          Text(entry.title!, style: text.titleLarge),
        ],
        const SizedBox(height: 16),
        _moodEnergyRow(context),
        const SizedBox(height: 20),
        if ((entry.bodyHtml ?? '').isNotEmpty)
          HtmlWidget(
            entry.bodyHtml!,
            textStyle: text.bodyLarge!.copyWith(color: c.inkHi),
          )
        else if ((entry.bodyPlain ?? '').isNotEmpty)
          Text(entry.bodyPlain!, style: text.bodyLarge),
        if ((entry.gratitude ?? '').isNotEmpty) ...[
          const SizedBox(height: 24),
          _gratitudeBox(context),
        ],
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: 24),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in entry.tags) TagPill(t)],
          ),
        ],
      ],
    );
  }

  Widget _moodEnergyRow(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final children = <Widget>[];
    if (entry.mood != null) {
      children.add(MoodEmoji(
        emoji: moodEmojiFor(entry.mood, serverEmoji: entry.moodEmoji),
        size: 28,
      ));
      children.add(const SizedBox(width: 8));
      children.add(Text(
        journalMoodLabels[entry.mood] ?? entry.mood!,
        style: text.titleMedium,
      ));
    }
    if (entry.energyLevel != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 16));
        children.add(Container(width: 1, height: 16, color: c.divider));
        children.add(const SizedBox(width: 16));
      }
      children.add(Text('Enerji',
          style: text.bodySmall!.copyWith(color: c.inkMid)));
      children.add(const SizedBox(width: 8));
      children.add(EnergyDots(level: entry.energyLevel!, size: 8));
    }
    if (entry.weather != null) {
      children.add(const Spacer());
      children.add(Flexible(
        child: Text(entry.weather!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall!.copyWith(color: c.inkMid)),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(children: children);
  }

  Widget _gratitudeBox(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.goldContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.goldDim.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, size: 14, color: c.onGoldContainer),
              const SizedBox(width: 6),
              Text('MİNNET',
                  style: text.labelMedium!.copyWith(color: c.onGoldContainer)),
            ],
          ),
          const SizedBox(height: 8),
          Text(entry.gratitude!,
              style: text.bodyMedium!.copyWith(color: c.onGoldContainer)),
        ],
      ),
    );
  }
}
