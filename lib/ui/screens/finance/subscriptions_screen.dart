import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/subscription.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sync_hint.dart';
import 'finance_utils.dart';
import 'subscription_form.dart';

/// When [sub] is next due, said the way a row says it: "3 gün sonra",
/// "Gecikmiş · 3 Ekim", "Ödeme tarihi yok" — or that it is paused.
String subscriptionWhen(AppL10n l, Subscription sub, DateTime today) {
  if (!sub.active) return l.subscriptionPausedLabel;
  final next = sub.nextChargeOn;
  if (next == null) return l.subscriptionNoDate;
  if (dayDelta(next, now: today) < 0) {
    return '${l.subscriptionOverdue} · ${formatDate(next)}';
  }
  return l.relativeDays(next);
}

/// Opens subscription [id]'s sheet. It reads the subscription from the
/// Subscriptions list; [name] titles the sheet until that has loaded (the
/// dashboard's upcoming payments know only a little of each).
Future<void> showSubscriptionSheet(
  BuildContext context, {
  required int id,
  String? name,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
    builder: (_) => _SubscriptionSheet(id: id, name: name),
  );
}

class _SubscriptionSheet extends ConsumerStatefulWidget {
  final int id;
  final String? name;

  const _SubscriptionSheet({required this.id, this.name});

  @override
  ConsumerState<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<_SubscriptionSheet> {
  bool _busy = false;

  /// Records the payment: an expense on its account and category, and the
  /// next due date one period on. Not safe to repeat, so the button waits
  /// for the answer, and a lost answer is not retried on its own.
  Future<void> _charge(Subscription sub) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final charge =
          await ref.read(repositoryProvider).chargeSubscription(sub.id);
      if (!mounted) return;
      Haptics.success();
      final tx = charge.transaction;
      Navigator.of(context).pop();
      showAppSnack(
        context,
        l.subscriptionCharged(formatMoney(
          tx?.amountCents ?? sub.amountCents,
          tx?.account.currency ?? sub.account.currency,
          tx?.account.subunitToUnit ?? sub.account.subunitToUnit,
        )),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final maybe = e is ApiException && e.isNetwork && e.mayHaveArrived;
      showAppSnack(
        context,
        maybe
            ? l.subscriptionChargeMaybe
            : failureMessage(e, l, fallback: l.subscriptionChargeFailed),
        isError: true,
      );
    }
  }

  Future<void> _setActive(Subscription sub, bool active) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .setSubscriptionActive(sub.id, active: active);
      if (!mounted) return;
      Haptics.success();
      Navigator.of(context).pop();
      showAppSnack(
        context,
        active
            ? l.subscriptionResumedDone(sub.name)
            : l.subscriptionPausedDone(sub.name),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.subscriptionToggleFailed),
        isError: true,
      );
    }
  }

  void _edit(Subscription sub) {
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    openSubscriptionForm(host, existing: sub);
  }

  void _delete(Subscription sub) {
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final host = navigator.context;
    final repo = ref.read(repositoryProvider);
    final deletes = ref.read(deferredDeletesProvider.notifier);
    navigator.pop();
    deleteWithUndo(
      host,
      deletes,
      record: (scope: DataScope.subscriptions, id: sub.id),
      message: l.subscriptionDeleted(sub.name),
      send: () => repo.deleteSubscription(sub.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(subscriptionsProvider);
    final today = ref.watch(currentDayProvider);
    Subscription? sub;
    for (final s in async.value?.data.all ?? const <Subscription>[]) {
      if (s.id == widget.id) sub = s;
    }

    final children = <Widget>[];
    if (sub == null) {
      children.addAll([
        Text(widget.name ?? l.titleSubscriptions, style: text.titleLarge),
        const SizedBox(height: 24),
        if (async.hasFailed)
          Text(l.errServerUnreachable,
              style: text.bodyMedium!.copyWith(color: c.error))
        else if (async.hasValue)
          Text(l.errNotFound, style: text.bodyMedium!.copyWith(color: c.inkMid))
        else
          const Center(child: CircularProgressIndicator()),
      ]);
    } else {
      final s = sub;
      final note = s.note;
      final chargeable = s.active && s.nextChargeOn != null;
      children.addAll([
        Text(s.name, style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          [
            subscriptionWhen(l, s, today),
            s.account.name,
            s.category?.name ?? l.financeUncategorized,
          ].join(' · '),
          style: text.bodySmall!.copyWith(color: c.inkMid),
        ),
        const SizedBox(height: 16),
        Text(
          l.subscriptionAmountPer(
            formatMoney(s.amountCents, s.account.currency,
                s.account.subunitToUnit),
            s.frequency,
          ),
          style: text.titleLarge!.copyWith(fontFeatures: tabularFigures),
        ),
        if (s.nextChargeOn != null && s.active) ...[
          const SizedBox(height: 4),
          Text(
            l.subscriptionNextOn(formatDate(s.nextChargeOn!, withYear: true)),
            style: text.bodySmall!.copyWith(color: c.inkMid),
          ),
        ],
        if (s.vendor != null) ...[
          const SizedBox(height: 4),
          Text(s.vendor!, style: text.bodySmall!.copyWith(color: c.inkMid)),
        ],
        if (note != null) ...[
          const SizedBox(height: 12),
          Text(note, style: text.bodyMedium),
        ],
        const SizedBox(height: 24),
        if (chargeable) ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _charge(s),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.onGold),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(l.subscriptionCharge),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _edit(s),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l.actionEdit),
          ),
        ] else
          FilledButton.icon(
            onPressed: _busy ? null : () => _edit(s),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l.actionEdit),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _setActive(s, !s.active),
          icon: Icon(s.active ? Icons.pause : Icons.play_arrow, size: 18),
          label: Text(s.active ? l.subscriptionPause : l.subscriptionResume),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _busy ? null : () => _delete(s),
          style: TextButton.styleFrom(
            foregroundColor: c.error,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.actionDelete),
        ),
      ]);
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The Abonelikler page: what the active subscriptions cost a month and a
/// year (per currency — never added across currencies), then the active
/// ones by due date and the paused ones.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(subscriptionsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final today = ref.watch(currentDayProvider);
    final bundle = async.value?.data;

    Future<void> refresh() async {
      ref.read(dataSyncProvider).refresh([subscriptionsProvider]);
      await settleRefresh([ref.read(subscriptionsProvider.future)]);
    }

    List<Subscription> visible(List<Subscription> list) => withoutDeleted(
          list,
          hidden,
          DataScope.subscriptions,
          (s) => s.id,
        );

    Widget body;
    if (async.isFirstLoad) {
      body = const Center(child: CircularProgressIndicator());
    } else if (bundle == null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.cloud_off,
            title: l.errServerUnreachable,
            subtitle: l.errCheckWifi,
            actionLabel: l.actionRetry,
            onAction: refresh,
          ),
        ],
      );
    } else {
      final active = visible(bundle.active);
      final paused = visible(bundle.inactive);
      if (active.isEmpty && paused.isEmpty) {
        body = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            EmptyState(
              icon: Icons.autorenew,
              title: l.subscriptionsEmpty,
              subtitle: l.financeSubscriptionsEmpty,
              actionLabel: l.financeAddSubscription,
              onAction: () => openSubscriptionForm(context),
            ),
          ],
        );
      } else {
        body = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            if (bundle.totals.isNotEmpty) ...[
              _Totals(totals: bundle.totals),
              const SizedBox(height: 24),
            ],
            if (active.isNotEmpty) ...[
              SectionHeader(l.subscriptionsActive),
              _list(context, active, today),
              const SizedBox(height: 24),
            ],
            if (paused.isNotEmpty) ...[
              SectionHeader(l.subscriptionsPaused),
              _list(context, paused, today),
            ],
          ],
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.titleSubscriptions)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => openSubscriptionForm(context),
        icon: const Icon(Icons.add),
        label: Text(l.subscriptionsAddFab),
      ),
      body: Column(
        children: [
          if (async.refreshFailed)
            OfflineBanner(lastUpdated: async.value!.at, onRetry: refresh),
          Expanded(
            child: SyncHint.over(
              active: async.isRefetching,
              child: RefreshIndicator.adaptive(
                color: c.gold,
                onRefresh: refresh,
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<Subscription> subs,
    DateTime today,
  ) {
    final c = context.nok;
    final l = context.l10n;
    return NokturnCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < subs.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 72, color: c.divider),
            NokturnRow(
              leading: LeadingCircle(
                color: hexColor(subs[i].color, fallback: c.inkLow),
                icon: subs[i].active ? Icons.autorenew : Icons.pause,
              ),
              title: subs[i].name,
              meta: [
                subscriptionWhen(l, subs[i], today),
                l.subscriptionFrequency(subs[i].frequency),
              ].join(' · '),
              trailing: MoneyText(
                subs[i].amountCents,
                currency: subs[i].account.currency,
                subunitToUnit: subs[i].account.subunitToUnit,
                negative: true,
              ),
              onTap: () => showSubscriptionSheet(
                context,
                id: subs[i].id,
                name: subs[i].name,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the active subscriptions cost, per currency: a month (a yearly one
/// counts a twelfth), then a year.
class _Totals extends StatelessWidget {
  final List<SubscriptionTotal> totals;

  const _Totals({required this.totals});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < totals.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(
              l.subscriptionsMonthly(formatMoney(totals[i].monthlyCents,
                  totals[i].currency, totals[i].subunitToUnit)),
              style: text.titleMedium!.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(height: 2),
            Text(
              l.subscriptionsYearly(formatMoney(totals[i].yearlyCents,
                  totals[i].currency, totals[i].subunitToUnit)),
              style: text.bodySmall!.copyWith(
                color: c.inkMid,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
