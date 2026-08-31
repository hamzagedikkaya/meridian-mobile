import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
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

class JournalDetailScreen extends ConsumerWidget {
  final int entryId;
  const JournalDetailScreen({super.key, required this.entryId});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l.journalDeleteTitle,
      message: l.journalDeleteBody,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    Haptics.danger();
    try {
      await ref.read(repositoryProvider).deleteJournalEntry(entryId);
      ref.invalidate(journalProvider);
      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.localized(l), isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(journalEntryProvider(entryId));
    final entry = async.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.titleJournalEntry),
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
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(l.actionEdit)),
                PopupMenuItem(value: 'delete', child: Text(l.actionDelete)),
              ],
            ),
        ],
      ),
      body: async.hasError && entry == null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: l.journalLoadFailed,
              subtitle: l.errCheckWifi,
              actionLabel: l.actionRetry,
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
          // Bones under shimmer: shape only, no language.
          Text('███ █████ ████',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          Text(
            '████ ███████ ████ ██████ ███████ ████ ████████ ██ ███ ████ '
            '██████ ████ ██████ ████ ████ ███████ ██ █████ ██████.',
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
    final l = context.l10n;
    final children = <Widget>[];
    if (entry.mood != null) {
      children.add(MoodEmoji(
        emoji: moodEmojiFor(entry.mood, serverEmoji: entry.moodEmoji),
        size: 28,
      ));
      children.add(const SizedBox(width: 8));
      children.add(Text(
        l.moodLabel(entry.mood!),
        style: text.titleMedium,
      ));
    }
    if (entry.energyLevel != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 16));
        children.add(Container(width: 1, height: 16, color: c.divider));
        children.add(const SizedBox(width: 16));
      }
      children.add(Text(l.journalEnergy,
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
              Text(context.l10n.journalGratitude,
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
