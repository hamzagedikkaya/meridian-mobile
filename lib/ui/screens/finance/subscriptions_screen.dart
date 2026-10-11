import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/turkish_case.dart';
import '../../../data/current_day.dart';
import '../../../data/data_scope.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/subscription.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/entity_color.dart';
import '../../flows/flows.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/collapsing_fab.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_phase_switcher.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/nokturn_row.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/sync_hint.dart';
import 'subscription_form.dart';

/// When [sub] is next due, said the way a row says it: "3 gün sonra",
/// "Gecikmiş · 3 Ekim", "Ödeme tarihi yok" — or that it is paused.
String subscriptionWhen(AppL10n l, Subscription sub, DateTime today) {
  if (!sub.active) return l.subscriptionPausedLabel;
  final next = sub.nextChargeOn;
  if (next == null) return l.subscriptionNoDate;
  if (dayDelta(next, now: today) < 0) return overdueSince(l, next, today);
  return l.relativeDays(next);
}

/// A payment past its date, said the same way wherever it is listed:
/// "Gecikmiş · 3 Ekim" — with the year when it is not [today]'s
/// ("Gecikmiş · 15 Ocak 2025"), so a payment missed long ago does not read
/// as this year's.
String overdueSince(AppL10n l, DateTime due, DateTime today) =>
    '${l.subscriptionOverdue} · '
    '${formatDate(due, withYear: due.year != today.year)}';

/// The Abonelikler page's groups, most urgent first (design-analysis §7.8).
enum SubscriptionUrgency {
  /// Its date has passed: the header is in error.
  overdue,

  /// Due within 7 days.
  thisWeek,

  /// Due later this calendar month.
  thisMonth,

  /// Due after this month, or with no date.
  later,

  /// Paused: never due.
  paused,
}

/// Which group [sub] is listed under on [today], when it is due on [due]
/// (its own date, or the one an unconfirmed skip moved it to).
SubscriptionUrgency urgencyOf(Subscription sub, DateTime? due, DateTime today) {
  if (!sub.active) return SubscriptionUrgency.paused;
  if (due == null) return SubscriptionUrgency.later;
  final days = dayDelta(due, now: today);
  if (days < 0) return SubscriptionUrgency.overdue;
  if (days <= 7) return SubscriptionUrgency.thisWeek;
  if (due.year == today.year && due.month == today.month) {
    return SubscriptionUrgency.thisMonth;
  }
  return SubscriptionUrgency.later;
}

/// [from] one [frequency] period on, the way the server moves a due date
/// after a payment (contract §4.6): weekly +7 days, monthly +1 month,
/// yearly +1 year — a day the shorter month lacks becomes its last day
/// (31 January → 28 February).
DateTime nextChargeAfter(DateTime from, String frequency) {
  DateTime clamped(int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, from.day > last ? last : from.day);
  }

  return switch (frequency) {
    'weekly' => DateTime(from.year, from.month, from.day + 7),
    'yearly' => clamped(from.year + 1, from.month),
    _ => clamped(from.year, from.month + 1),
  };
}

/// [sub] as the form would send it, with its due date moved to [next]: an
/// edit of it sends that date alone.
SubscriptionInput _withNextCharge(Subscription sub, DateTime? next) =>
    SubscriptionInput(
      name: sub.name,
      accountId: sub.account.id,
      amountCents: sub.amountCents,
      frequency: sub.frequency,
      nextChargeOn: next,
      categoryId: sub.category?.id,
      vendor: sub.vendor,
      note: sub.note,
      color: sub.color,
    );

/// Due dates moved on the phone whose write has not been confirmed by a
/// refetch yet — a skip, or the undo of one — by subscription id. Rows read
/// them over the server's date, so a skip moves its row in the frame it is
/// tapped (principle 1).
final subscriptionDueOverridesProvider =
    NotifierProvider<SubscriptionDueOverrides, Map<int, DateTime?>>(
        SubscriptionDueOverrides.new);

class SubscriptionDueOverrides extends Notifier<Map<int, DateTime?>> {
  /// The overrides whose write has answered: they go with the next list.
  final _answered = <int>{};

  @override
  Map<int, DateTime?> build() => const {};

  void set(int id, DateTime? due) {
    _answered.remove(id);
    state = {...state, id: due};
  }

  /// The write failed: the server's date shows again.
  void drop(int id) {
    _answered.remove(id);
    state = {...state}..remove(id);
  }

  /// The write went through; its refetch is on the way.
  void answered(int id) => _answered.add(id);

  /// A list came in: the answered overrides are in it now.
  void settle() {
    if (_answered.isEmpty) return;
    final next = {...state}..removeWhere((id, _) => _answered.contains(id));
    _answered.clear();
    state = next;
  }
}

/// Skips [sub]'s next payment: its due date moves one period on
/// (`PATCH next_charge_on`) without recording anything, and "Geri al" puts
/// the old date back. The row moves at once; a refusal moves it back and
/// says why. [context] is the screen's — the snackbar floats over its FAB.
Future<void> skipSubscriptionPayment(
  BuildContext context,
  WidgetRef ref,
  Subscription sub,
) async {
  final before = sub.nextChargeOn;
  if (before == null || !sub.active) return;
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final overrides = ref.read(subscriptionDueOverridesProvider.notifier);
  final next = nextChargeAfter(before, sub.frequency);
  final messenger = ScaffoldMessenger.of(context);
  Haptics.tick();
  overrides.set(sub.id, next);
  try {
    final saved = await repo.updateSubscription(
      sub,
      _withNextCharge(sub, next),
      accountCurrency: sub.account.currency,
    );
    overrides.answered(sub.id);
    if (!context.mounted) return;
    showAppSnack(
      context,
      l.subscriptionSkipped(sub.name, formatDate(next)),
      actionLabel: l.actionUndo,
      onAction: () async {
        overrides.set(sub.id, before);
        try {
          await repo.updateSubscription(
            saved,
            _withNextCharge(saved, before),
            accountCurrency: saved.account.currency,
          );
          overrides.answered(sub.id);
        } catch (_) {
          overrides.drop(sub.id);
          if (messenger.mounted) {
            showAppSnack(messenger.context, l.subscriptionUndoFailed,
                isError: true);
          }
        }
      },
    );
  } catch (e) {
    overrides.drop(sub.id);
    if (context.mounted) {
      showAppSnack(
        context,
        failureMessage(e, l, fallback: l.subscriptionSkipFailed),
        isError: true,
      );
    }
  }
}

/// The 40 dp circle of a subscription's row: its category's tone and
/// initial; without a category its own colour and `autorenew_rounded`; a
/// paused one `pause_rounded` in inkMid.
Widget subscriptionLeading(Subscription sub, NokturnColors c) {
  if (!sub.active) {
    return LeadingCircle(color: c.inkMid, icon: Icons.pause_rounded);
  }
  final category = sub.category;
  if (category != null && category.name.isNotEmpty) {
    return LeadingCircle.tone(
      entityTone(category.color, c),
      initial: trUpper(String.fromCharCode(category.name.runes.first)),
    );
  }
  return LeadingCircle.tone(
    entityTone(sub.color, c),
    icon: Icons.autorenew_rounded,
  );
}

/// Opens subscription [id]'s sheet. It reads the subscription from the
/// Subscriptions list; [name] titles the sheet until that has loaded (the
/// dashboard's upcoming payments know only a little of each).
///
/// [context] is the screen's: the edit form, the delete and their
/// snackbars outlive the sheet, and a delete's undo window ends when that
/// screen is left (see [deleteWithUndo]).
Future<void> showSubscriptionSheet(
  BuildContext context, {
  required int id,
  String? name,
}) {
  return showNokSheet<void>(
    context,
    builder: (_) => _SubscriptionSheet(host: context, id: id, name: name),
  );
}

class _SubscriptionSheet extends ConsumerStatefulWidget {
  final BuildContext host;
  final int id;
  final String? name;

  const _SubscriptionSheet({required this.host, required this.id, this.name});

  @override
  ConsumerState<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<_SubscriptionSheet> {
  bool _busy = false;

  /// Why the last payment, pause or resume did not go through. Said in the
  /// sheet, which stays open: a snackbar would be under it.
  String? _error;

  /// A payment whose answer was lost (it timed out after it went out) may
  /// have been recorded. Until the subscriptions the write refetches have
  /// landed — anything newer than this, the list on screen when it failed —
  /// "Ödendi olarak kaydet" stays off, so a second payment is never one tap
  /// away from a first that may have gone through.
  Fetched<SubscriptionsBundle>? _unsureOver;

  /// Records the payment: an expense on its account and category, and the
  /// next due date one period on. Not safe to repeat (contract 4.6), so the
  /// button waits for the answer — and is off while the row's "Ödendi" is
  /// sending one — and a lost answer is not retried, on its own or by a tap
  /// before the list says what happened. "Geri al" deletes the expense and
  /// puts the due date back (D29).
  Future<void> _charge(Subscription sub) async {
    final l = context.l10n;
    final inFlight = ref.read(subscriptionChargesInFlightProvider.notifier);
    if (!inFlight.claim(sub.id)) return;
    final repo = ref.read(repositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final charge = await repo.chargeSubscription(sub.id);
      if (!mounted) return;
      Haptics.confirm();
      final tx = charge.transaction;
      final host = widget.host;
      Navigator.of(context).pop();
      if (!host.mounted) return;
      final messenger = ScaffoldMessenger.of(host);
      showAppSnack(
        host,
        l.subscriptionCharged(formatMoney(
          tx?.amountCents ?? sub.amountCents,
          tx?.account.currency ?? sub.account.currency,
          tx?.account.subunitToUnit ?? sub.account.subunitToUnit,
        )),
        actionLabel: l.actionUndo,
        onAction: () => undoSubscriptionCharge(
            messenger, l, repo, charge, sub.nextChargeOn),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      final maybe = e is ApiException && e.isNetwork && e.mayHaveArrived;
      setState(() {
        _busy = false;
        if (maybe) _unsureOver = ref.read(subscriptionsProvider).value;
        _error = maybe
            ? l.subscriptionChargeMaybe
            : failureMessage(e, l, fallback: l.subscriptionChargeFailed);
      });
    } finally {
      inFlight.release(sub.id);
    }
  }

  Future<void> _setActive(Subscription sub, bool active) async {
    final l = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .setSubscriptionActive(sub.id, active: active);
      if (!mounted) return;
      Haptics.confirm();
      final host = widget.host;
      Navigator.of(context).pop();
      if (!host.mounted) return;
      showAppSnack(
        host,
        active
            ? l.subscriptionResumedDone(sub.name)
            : l.subscriptionPausedDone(sub.name),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      setState(() {
        _busy = false;
        _error = failureMessage(e, l, fallback: l.subscriptionToggleFailed);
      });
    }
  }

  void _skip(Subscription sub) {
    final host = widget.host;
    Navigator.of(context).pop();
    if (host.mounted) skipSubscriptionPayment(host, ref, sub);
  }

  void _edit(Subscription sub) {
    final host = widget.host;
    Navigator.of(context).pop();
    if (host.mounted) openSubscriptionForm(host, existing: sub);
  }

  void _delete(Subscription sub) {
    final host = widget.host;
    Navigator.of(context).pop();
    if (host.mounted) deleteSubscription(host, ref, sub);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final async = ref.watch(subscriptionsProvider);
    final today = ref.watch(currentDayProvider);
    final charging = ref.watch(subscriptionChargesInFlightProvider);
    Subscription? sub;
    for (final s in async.value?.data.all ?? const <Subscription>[]) {
      if (s.id == widget.id) sub = s;
    }

    if (sub == null) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: widget.name ?? l.titleSubscriptions,
              entityTitle: true,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.sheetH, Gap.sm, Insets.sheetH, Gap.xxl),
              child: async.hasFailed
                  ? Text(l.errServerUnreachable,
                      style: text.bodyMedium!.copyWith(color: c.error))
                  : async.hasValue
                      ? Text(l.errNotFound,
                          style: text.bodyMedium!.copyWith(color: c.inkMid))
                      : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }
    final s = sub;
    final note = s.note;
    final chargeable = s.active && s.nextChargeOn != null;
    // A payment that may have gone through holds the button until the
    // refetched list says whether it did; so does one the row is sending.
    final unsure = _unsureOver != null && identical(async.value, _unsureOver);
    final held = _busy || unsure || charging.contains(s.id);
    final overdue = chargeable && dayDelta(s.nextChargeOn!, now: today) < 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: s.name,
          entityTitle: true,
          subtitle: [
            s.account.name,
            s.category?.name ?? l.financeUncategorized,
          ].join(' · '),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sheetH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.subscriptionAmountPer(
                    formatMoney(s.amountCents, s.account.currency,
                        s.account.subunitToUnit),
                    s.frequency,
                  ),
                  style: context.nokText.numStat,
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  overdue || !s.active || s.nextChargeOn == null
                      ? subscriptionWhen(l, s, today)
                      : l.subscriptionNextOn(
                          formatDate(s.nextChargeOn!, withYear: true)),
                  style: text.bodyMedium!
                      .copyWith(color: overdue ? c.error : c.inkMid),
                ),
                if (s.vendor != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(s.vendor!,
                      style: text.bodySmall!.copyWith(color: c.inkMid)),
                ],
                if (note != null) ...[
                  const SizedBox(height: Gap.md),
                  Text(note, style: text.bodyMedium),
                ],
                const SizedBox(height: Gap.lg),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    if (chargeable)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _edit(s),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(l.actionEdit),
                      ),
                    if (chargeable)
                      OutlinedButton.icon(
                        onPressed: held ? null : () => _skip(s),
                        icon: const Icon(Icons.skip_next_rounded, size: 18),
                        label: Text(l.subscriptionSkip),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _setActive(s, !s.active),
                      icon: Icon(
                        s.active
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(
                          s.active ? l.subscriptionPause : l.subscriptionResume),
                    ),
                  ],
                ),
                // Under the buttons the tap was on: the sheet stays open, so
                // a snackbar would be drawn under it, unseen.
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.md),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: text.bodySmall!.copyWith(color: c.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SheetActions(
          primary: chargeable
              // Sending (from here or the row's "Ödendi"): gold, locked,
              // a spinner after 150 ms (D34). Otherwise held: off.
              ? PrimaryButton(
                  icon: Icons.check_rounded,
                  label: l.subscriptionCharge,
                  loading: charging.contains(s.id),
                  onPressed: held ? null : () => _charge(s),
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(s),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: Text(l.actionEdit),
                ),
          destructive: TextButton.icon(
            onPressed: _busy ? null : () => _delete(s),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(l.actionDelete),
          ),
        ),
      ],
    );
  }
}

/// Deletes [sub] the forgiving way: off every list at once, "Geri al" for
/// six seconds, then the DELETE. [context] is the screen's.
void deleteSubscription(BuildContext context, WidgetRef ref, Subscription sub) {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  deleteWithUndo(
    context,
    ref.read(deferredDeletesProvider.notifier),
    record: (scope: DataScope.subscriptions, id: sub.id),
    message: l.subscriptionDeleted(sub.name),
    send: () => repo.deleteSubscription(sub.id),
  );
}

/// The Abonelikler page (design-analysis §7.8): what the active
/// subscriptions cost a month and a year (per currency — never added across
/// currencies), then every subscription by how soon it is due — overdue,
/// this week, this month, later — and the paused ones. A payment due this
/// week or overdue is marked paid, or skipped, right on its row.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final l = context.l10n;
    final async = ref.watch(subscriptionsProvider);
    final hidden = ref.watch(deferredDeletesProvider);
    final today = ref.watch(currentDayProvider);
    final overrides = ref.watch(subscriptionDueOverridesProvider);
    // A list that comes in carries the skips that have answered.
    ref.listen(subscriptionsProvider, (previous, next) {
      if (next.hasValue && !identical(previous?.value, next.value)) {
        ref.read(subscriptionDueOverridesProvider.notifier).settle();
      }
    });
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

    final LoadPhase phase;
    if (async.isFirstLoad) {
      phase = LoadPhase.waiting;
    } else if (bundle == null) {
      phase = LoadPhase.error;
    } else {
      phase = LoadPhase.content;
    }
    Widget failed() => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState.error(onRetry: refresh),
            ),
          ],
        );

    Widget body;
    var empty = false;
    if (bundle == null) {
      body = failed();
    } else {
      final active = visible(bundle.active);
      final paused = visible(bundle.inactive);
      if (active.isEmpty && paused.isEmpty) {
        empty = true;
        body = CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.autorenew_rounded,
                title: l.subscriptionsEmpty,
                subtitle: l.financeSubscriptionsEmpty,
                actionLabel: l.financeAddSubscription,
                onAction: () => openSubscriptionForm(context),
              ),
            ),
          ],
        );
      } else {
        final groups = <SubscriptionUrgency, List<Subscription>>{};
        DateTime? dueOf(Subscription s) =>
            overrides.containsKey(s.id) ? overrides[s.id] : s.nextChargeOn;
        for (final s in [...active, ...paused]) {
          groups.putIfAbsent(urgencyOf(s, dueOf(s), today), () => []).add(s);
        }
        for (final list in groups.values) {
          // Soonest first; no date last, then by name.
          list.sort((a, b) {
            final da = dueOf(a), db = dueOf(b);
            if (da != null && db != null && da != db) return da.compareTo(db);
            if ((da == null) != (db == null)) return da == null ? 1 : -1;
            return a.name.compareTo(b.name);
          });
        }
        body = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(Insets.gutter, Gap.sm, Insets.gutter,
              CollapsingFab.clearance(context)),
          children: [
            if (bundle.totals.isNotEmpty)
              _Hero(
                totals: bundle.totals,
                active: active.length,
                paused: paused.length,
              ),
            for (final urgency in SubscriptionUrgency.values)
              if (groups[urgency] case final subs?) ...[
                const SizedBox(height: Gap.xxl),
                _GroupHeader(urgency: urgency, count: subs.length),
                NokturnCard(
                  variant: NokCardVariant.list,
                  child: Column(
                    children: [
                      for (var i = 0; i < subs.length; i++) ...[
                        if (i > 0) NokturnRow.divider(),
                        SubscriptionRow(
                          key: ValueKey(subs[i].id),
                          host: context,
                          sub: subs[i],
                          due: dueOf(subs[i]),
                          urgency: urgency,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
          ],
        );
      }
    }

    return CollapsingFabScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l.titleSubscriptions)),
        floatingActionButton: CollapsingFab(
          icon: Icons.add_rounded,
          label: l.subscriptionsAddFab,
          // The empty state carries the same action.
          hidden: empty,
          onPressed: () => openSubscriptionForm(context),
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
                  child: LoadPhaseSwitcher(
                    phase: phase,
                    skeleton: (_) => const _SubscriptionsSkeleton(),
                    content: (_) => body,
                    error: (_) => failed(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Abonelikler page while it first loads (§4.26): the hero card, then
/// a group of rows — circle, name, meta, amount — in bones.
class _SubscriptionsSkeleton extends StatelessWidget {
  const _SubscriptionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          Insets.gutter, Gap.sm, Insets.gutter, Gap.x5),
      children: const [
        NokturnCard(
          variant: NokCardVariant.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone.text(width: 120),
              SizedBox(height: Gap.xs),
              Bone.text(width: 160, lineHeight: 40),
              SizedBox(height: Gap.xxs),
              Bone.text(width: 200),
            ],
          ),
        ),
        SizedBox(height: Gap.xxl),
        SizedBox(
          height: Hit.min,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Bone.text(width: 96, lineHeight: 22),
          ),
        ),
        SizedBox(height: Gap.xs),
        NokturnCard(
          variant: NokCardVariant.list,
          child: Column(
            children: [_BoneRow(), _BoneRow(), _BoneRow(), _BoneRow()],
          ),
        ),
      ],
    );
  }
}

/// One row in bones: the 40 dp circle, a name and a meta line, an amount.
class _BoneRow extends StatelessWidget {
  const _BoneRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Insets.rowH, vertical: Insets.rowV),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Bone.circle(size: LeadingCircle.size),
            SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(width: 120, lineHeight: 22),
                  SizedBox(height: Gap.xxs),
                  Bone.text(width: 88),
                ],
              ),
            ),
            SizedBox(width: Gap.sm),
            Bone.text(width: 64, lineHeight: 22),
          ],
        ),
      ),
    );
  }
}

/// A group's title (a [SectionHeader]'s rhythm: at least 48 dp, a header
/// for screen readers) and how many it holds — the overdue group's both in
/// error.
class _GroupHeader extends StatelessWidget {
  final SubscriptionUrgency urgency;
  final int count;

  const _GroupHeader({required this.urgency, required this.count});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final overdue = urgency == SubscriptionUrgency.overdue;
    final title = switch (urgency) {
      SubscriptionUrgency.overdue => l.subscriptionOverdue,
      SubscriptionUrgency.thisWeek => l.subscriptionsThisWeek,
      SubscriptionUrgency.thisMonth => l.subscriptionsThisMonth,
      SubscriptionUrgency.later => l.subscriptionsLater,
      SubscriptionUrgency.paused => l.subscriptionsPaused,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Hit.min),
        child: Semantics(
          header: true,
          label: '$title, $count',
          excludeSemantics: true,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium!
                      .copyWith(color: overdue ? c.error : null),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                '$count',
                style: context.nokText.numMeta
                    .copyWith(color: overdue ? c.error : c.inkMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One subscription on the Abonelikler page (design-analysis §7.8).
///
/// A tap opens its sheet; a long press offers Düzenle · Atla · Durdur ·
/// Sil (also TalkBack actions). One due this week or overdue moves its
/// amount into the meta line and gets an inline "Ödendi" — locked from the
/// first tap until the answer, so a double tap records one payment (D29) —
/// and a ⋯ menu with Atla and Düzenle. The others show the amount at the
/// end.
class SubscriptionRow extends ConsumerWidget {
  final Subscription sub;

  /// The page's context: what a row starts — a payment, a skip, a delete —
  /// outlives the row, which moves to another group as its date changes.
  final BuildContext host;

  /// When it is due as shown: its own date, or where a skip moved it.
  final DateTime? due;
  final SubscriptionUrgency urgency;

  const SubscriptionRow({
    super.key,
    required this.sub,
    required this.host,
    required this.due,
    required this.urgency,
  });

  bool get _due =>
      urgency == SubscriptionUrgency.overdue ||
      urgency == SubscriptionUrgency.thisWeek;

  void _open() => showSubscriptionSheet(host, id: sub.id, name: sub.name);

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final c = context.nok;
    final chargeable = sub.active && sub.nextChargeOn != null;
    final picked = await showNokSheet<_RowAction>(
      context,
      title: sub.name,
      builder: (sheet) {
        Widget row(_RowAction action, IconData icon, String label,
                {bool danger = false}) =>
            ListTile(
              leading: Icon(icon, color: danger ? c.error : c.inkMid),
              title: Text(label,
                  style: danger ? TextStyle(color: c.error) : null),
              onTap: () => Navigator.of(sheet).pop(action),
            );
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(_RowAction.edit, Icons.edit_outlined, l.actionEdit),
              if (chargeable)
                row(_RowAction.skip, Icons.skip_next_rounded,
                    l.subscriptionSkip),
              row(
                _RowAction.toggle,
                sub.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                sub.active ? l.subscriptionPause : l.subscriptionResume,
              ),
              row(_RowAction.delete, Icons.delete_outline_rounded,
                  l.actionDelete,
                  danger: true),
              const SizedBox(height: Gap.sm),
            ],
          ),
        );
      },
    );
    // The row may have moved meanwhile (a refresh): its ref is gone then.
    if (picked == null || !context.mounted || !host.mounted) return;
    _run(ref, picked);
  }

  Future<void> _run(WidgetRef ref, _RowAction action) async {
    final context = host;
    final l = context.l10n;
    switch (action) {
      case _RowAction.edit:
        openSubscriptionForm(context, existing: sub);
      case _RowAction.skip:
        skipSubscriptionPayment(context, ref, sub);
      case _RowAction.delete:
        deleteSubscription(context, ref, sub);
      case _RowAction.toggle:
        final active = !sub.active;
        final repo = ref.read(repositoryProvider);
        try {
          await repo.setSubscriptionActive(sub.id, active: active);
          if (!context.mounted) return;
          showAppSnack(
            context,
            active
                ? l.subscriptionResumedDone(sub.name)
                : l.subscriptionPausedDone(sub.name),
          );
        } catch (e) {
          if (!context.mounted) return;
          showAppSnack(
            context,
            failureMessage(e, l, fallback: l.subscriptionToggleFailed),
            isError: true,
          );
        }
    }
  }

  void _pay(WidgetRef ref) =>
      markSubscriptionPaid(host, ref, SubscriptionLite.of(sub));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final today = ref.watch(currentDayProvider);
    final paying = ref.watch(subscriptionChargesInFlightProvider
        .select((ids) => ids.contains(sub.id)));
    // A skip on its way: Ödendi waits for it, so the payment is recorded
    // against the date the server has.
    final skipping = ref.watch(subscriptionDueOverridesProvider
        .select((o) => o.containsKey(sub.id)));
    final money = formatMoney(
        sub.amountCents, sub.account.currency, sub.account.subunitToUnit);
    final semanticActions = <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(label: l.actionEdit): () =>
          _run(ref, _RowAction.edit),
      if (sub.active && sub.nextChargeOn != null)
        CustomSemanticsAction(label: l.subscriptionSkip): () =>
            _run(ref, _RowAction.skip),
      CustomSemanticsAction(
              label: sub.active ? l.subscriptionPause : l.subscriptionResume):
          () => _run(ref, _RowAction.toggle),
      CustomSemanticsAction(label: l.actionDelete): () =>
          _run(ref, _RowAction.delete),
    };

    if (!_due || due == null) {
      final shown = due == sub.nextChargeOn
          ? sub
          : _withDue(sub, due);
      return NokturnRow(
        leading: subscriptionLeading(sub, c),
        title: sub.name,
        meta: [
          subscriptionWhen(l, shown, today),
          l.subscriptionFrequency(sub.frequency),
        ].join(' · '),
        trailing: MoneyText(
          sub.amountCents,
          currency: sub.account.currency,
          subunitToUnit: sub.account.subunitToUnit,
          negative: sub.active,
          color: sub.active ? null : c.inkMid,
        ),
        onTap: _open,
        onLongPress: () => _actions(context, ref),
        semanticActions: semanticActions,
      );
    }

    final overdue = urgency == SubscriptionUrgency.overdue;
    final when = overdue ? overdueSince(l, due!, today) : l.relativeDays(due!);
    final whenStyle =
        text.bodySmall!.copyWith(color: overdue ? c.error : c.inkMid);
    // When, then the amount: the date may wrap to two lines beside the
    // controls but is never cut; the amount keeps a line of its own.
    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No line limit: [_stacked] gives it the room it needs.
        Text(when, style: whenStyle),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l.subscriptionAmountPer(money, sub.frequency),
            style: text.bodySmall!.copyWith(
              color: c.inkMid,
              fontFeatures: tabularFigures,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: l.subscriptionPaidFor(sub.name),
          excludeSemantics: true,
          button: true,
          enabled: !paying && !skipping,
          onTap: paying || skipping ? null : () => _pay(ref),
          child: OutlinedButton(
            onPressed: paying || skipping ? null : () => _pay(ref),
            style: OutlinedButton.styleFrom(
              // 36 dp to see, 48 dp to hit.
              minimumSize: const Size(_paidMinWidth, 36),
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
            child: Text(l.subscriptionPaid),
          ),
        ),
        // 8 dp between the two 48 dp targets (§8.2).
        const SizedBox(width: Gap.sm),
        PopupMenuButton<_RowAction>(
          tooltip: l.subscriptionMoreActions,
          icon: Icon(Icons.more_horiz_rounded, color: c.inkMid),
          enabled: !paying,
          onSelected: (action) => _run(ref, action),
          itemBuilder: (_) => [
            if (!skipping)
              PopupMenuItem(
                value: _RowAction.skip,
                child: Text(l.subscriptionSkip),
              ),
            PopupMenuItem(
              value: _RowAction.edit,
              child: Text(l.actionEdit),
            ),
          ],
        ),
      ],
    );
    final row = LayoutBuilder(builder: (context, constraints) {
      final stacked = _stacked(
        context,
        width: constraints.maxWidth,
        when: when,
        whenStyle: whenStyle,
        paidLabel: l.subscriptionPaid,
      );
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          // Beside the texts, the ⋯ button's 48 dp box ends 8 dp from the
          // edge: its glyph lines up with the 20 dp margin.
          padding: EdgeInsets.fromLTRB(Insets.rowH, Insets.rowV,
              stacked ? Insets.rowH : Gap.sm, Insets.rowV),
          child: Row(
            children: [
              subscriptionLeading(sub, c),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Narrow beside the controls: it wraps rather than
                    // losing its second word.
                    Text(
                      sub.name,
                      style: text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    meta,
                    // Too narrow beside them: the controls go under the
                    // texts, so the name and the date keep the width.
                    if (stacked) controls,
                  ],
                ),
              ),
              if (!stacked) ...[const SizedBox(width: Gap.sm), controls],
            ],
          ),
        ),
      );
    });
    return Semantics(
      customSemanticsActions: semanticActions,
      child: InkWell(
        onTap: _open,
        onLongPress: () => _actions(context, ref),
        child: row,
      ),
    );
  }

  /// "Ödendi"'s narrowest pill.
  static const _paidMinWidth = 56.0;

  /// The narrowest the texts may be beside the controls: a name's first
  /// word, "3 gün sonra", the amount.
  static const _minTextWidth = 96.0;

  /// Whether, in a row [width] wide, the controls go under the texts: when
  /// beside them the texts would be narrower than [_minTextWidth], or the
  /// date [when] would need more than two lines — it is never cut
  /// (design-analysis §7.8), whatever the text size or the phone.
  bool _stacked(
    BuildContext context, {
    required double width,
    required String when,
    required TextStyle whenStyle,
    required String paidLabel,
  }) {
    if (!width.isFinite) return false;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final labelStyle = Theme.of(context)
            .outlinedButtonTheme
            .style
            ?.textStyle
            ?.resolve(const {}) ??
        Theme.of(context).textTheme.labelLarge!;
    final label = TextPainter(
      text: TextSpan(text: paidLabel, style: labelStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final paid = math.max(_paidMinWidth, label.width + 2 * Gap.md);
    label.dispose();
    // Ödendi, the 8 dp gap, the ⋯ button's 48 dp — and a little slack for
    // rounding.
    final controls = paid + Gap.sm + Hit.min + 2;
    final textWidth = width -
        Insets.rowH -
        LeadingCircle.size -
        Gap.md -
        Gap.sm -
        controls -
        Gap.sm;
    if (textWidth < _minTextWidth) return true;
    final date = TextPainter(
      text: TextSpan(text: when, style: whenStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 2,
    )..layout(maxWidth: textWidth);
    final cut = date.didExceedMaxLines;
    date.dispose();
    return cut;
  }
}

/// [sub] as a row shows it while a skip moves it to [due].
Subscription _withDue(Subscription sub, DateTime? due) => Subscription(
      id: sub.id,
      name: sub.name,
      vendor: sub.vendor,
      amountCents: sub.amountCents,
      frequency: sub.frequency,
      nextChargeOn: due,
      startDate: sub.startDate,
      endDate: sub.endDate,
      active: sub.active,
      color: sub.color,
      note: sub.note,
      monthlyAmountCents: sub.monthlyAmountCents,
      yearlyAmountCents: sub.yearlyAmountCents,
      account: sub.account,
      category: sub.category,
    );

enum _RowAction { edit, skip, toggle, delete }

/// What the active subscriptions cost, per currency — a month (a yearly one
/// counts a twelfth) in Fraunces, then a year and how many are active and
/// paused.
class _Hero extends StatelessWidget {
  final List<SubscriptionTotal> totals;
  final int active;
  final int paused;

  const _Hero({
    required this.totals,
    required this.active,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final counts = [
      if (active > 0) l.subscriptionsActiveCount(active),
      if (paused > 0) l.subscriptionsPausedCount(paused),
    ];
    return NokturnCard(
      variant: NokCardVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.subscriptionsMonthlyLabel,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          for (var i = 0; i < totals.length; i++) ...[
            SizedBox(height: i == 0 ? Gap.xs : Gap.md),
            MoneyText(
              totals[i].monthlyCents,
              currency: totals[i].currency,
              subunitToUnit: totals[i].subunitToUnit,
              variant: MoneyVariant.title,
              color: c.inkHi,
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              [
                l.subscriptionsYearly(formatMoney(totals[i].yearlyCents,
                    totals[i].currency, totals[i].subunitToUnit)),
                // The counts once, under the first currency.
                if (i == 0) ...counts,
              ].join(' · '),
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
