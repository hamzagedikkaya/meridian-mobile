/// The app's flow entry points (design-analysis §9, WP-4): one call per
/// thing a screen can start — add something, open a record's sheet or form,
/// mark a payment — so every screen opens the same surface the same way,
/// and the screens being redesigned only call these.
///
/// Each resolves once its surface is closed: to what was saved where there
/// is something (`await` it as `void` where that does not matter), or
/// null when nothing was.
///
/// The surfaces themselves still live with their screens; these delegate
/// to them (with an import prefix, since some share a name with these).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/formats.dart';
import '../../core/haptics.dart';
import '../../core/session.dart';
import '../../data/current_day.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../l10n/app_l10n.dart';
import '../../models/account.dart';
import '../../models/event.dart';
import '../../models/finance_dashboard.dart';
import '../../models/goal.dart';
import '../../models/habit.dart';
import '../../models/quick_capture.dart';
import '../../models/subscription.dart';
import '../../models/todo.dart';
import '../../models/transaction.dart';
import '../screens/agenda/event_form.dart' as event_form;
import '../screens/finance/transaction_form_screen.dart' as tx_form;
import '../screens/goals/goal_form.dart' as goal_form;
import '../screens/habits/habit_detail_sheet.dart' as habit_detail;
import '../screens/habits/habit_log_sheet.dart' as habit_log;
import '../screens/today/widgets/quick_capture_sheet.dart' as quick_capture;
import '../screens/agenda/todo_sheet.dart' as todo_sheet;
import '../widgets/app_snackbar.dart';

// --- Quick add ----------------------------------------------------------------

/// Where quick add was opened from: what it offers first and the day a new
/// task or event lands on (§7.3).
enum QuickAddContext { today, agenda }

/// Opens quick add: one line that becomes a task, a payment, a habit
/// check-in or an event. [ctx] and [day] say where it was opened (Agenda's
/// day headings pass their day): a task added as one is due on [day], else
/// today on Today and on no day from Agenda.
Future<void> openQuickAdd(
  BuildContext context, {
  QuickAddContext ctx = QuickAddContext.today,
  DateTime? day,
}) =>
    quick_capture.showQuickCaptureSheet(context, ctx: ctx, day: day);

// --- Finance --------------------------------------------------------------------

/// Opens the new-transaction form, filled in as far as the caller knows:
/// [initialKind] (`expense`, `income` or `transfer`), the amount in the
/// account currency's minor units, the description, and the account (an
/// account's own page passes its [accountId]). The transaction as saved,
/// or null.
Future<Transaction?> openTransactionForm(
  BuildContext context, {
  String? initialKind,
  int? initialAmountCents,
  String? initialDescription,
  int? accountId,
}) =>
    tx_form.openTransactionForm(
      context,
      initialAccountId: accountId,
      initialKind: initialKind,
      initialAmountCents: initialAmountCents,
      initialDescription: initialDescription,
    );

/// What [markSubscriptionPaid] needs of a subscription — the Subscriptions
/// page's [Subscription] or the dashboard's upcoming [SubscriptionItem].
@immutable
class SubscriptionLite {
  final int id;
  final String name;
  final int amountCents;

  /// The due date being paid; the undo puts it back.
  final DateTime? nextChargeOn;
  final AccountRef account;

  const SubscriptionLite({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.nextChargeOn,
    required this.account,
  });

  factory SubscriptionLite.of(Subscription s) => SubscriptionLite(
        id: s.id,
        name: s.name,
        amountCents: s.amountCents,
        nextChargeOn: s.nextChargeOn,
        account: s.account,
      );

  factory SubscriptionLite.ofItem(SubscriptionItem s) => SubscriptionLite(
        id: s.id,
        name: s.name,
        amountCents: s.amountCents,
        nextChargeOn: s.nextChargeOn,
        account: s.account,
      );
}

/// The subscriptions whose "Ödendi" is on its way: a payment is not safe
/// to repeat (each `POST /subscriptions/:id/charge` records one more), so
/// a button showing it is off from the first tap until the answer
/// (D29) — watch this to draw it so. One whose answer was lost stays in
/// it until the subscriptions fetched after it say whether it went through
/// ([SubscriptionChargesInFlight.holdUntilRefetched]).
final subscriptionChargesInFlightProvider =
    NotifierProvider<SubscriptionChargesInFlight, Set<int>>(
        SubscriptionChargesInFlight.new);

class SubscriptionChargesInFlight extends Notifier<Set<int>> {
  /// Payments whose answer was lost, and the list each was lost over.
  final _unsure = <int, Fetched<SubscriptionsBundle>?>{};
  ProviderSubscription<AsyncValue<Fetched<SubscriptionsBundle>>>? _watch;

  /// Each session starts without any: they are the signed-in account's.
  @override
  Set<int> build() {
    ref.watch(sessionProvider.select((s) => s is SessionLoggedIn));
    ref.onDispose(_stopWatching);
    _unsure.clear();
    return const {};
  }

  /// Claims [id]; false when a payment of it is already on its way.
  bool claim(int id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }

  void release(int id) {
    _unsure.remove(id);
    if (_unsure.isEmpty) _stopWatching();
    state = {...state}..remove(id);
  }

  /// Keeps [id] claimed after a payment whose answer was lost: it may have
  /// been recorded, so no "Ödendi" — a row's, the dashboard's or the
  /// sheet's — may send another until a list of subscriptions newer than
  /// the one on hand has landed. A refetch that fails keeps it held.
  void holdUntilRefetched(int id) {
    _unsure[id] = ref.read(subscriptionsProvider).value;
    state = {...state, id};
    _watch ??= ref.listen(subscriptionsProvider, (_, next) {
      if (next is! AsyncData<Fetched<SubscriptionsBundle>>) return;
      final landed = [
        for (final MapEntry(:key, :value) in _unsure.entries)
          if (!identical(next.value, value)) key,
      ];
      for (final id in landed) {
        release(id);
      }
    });
  }

  void _stopWatching() {
    _watch?.close();
    _watch = null;
  }
}

/// Records [s]'s payment (`POST /subscriptions/:id/charge`: an expense on
/// its account and the next due date one period on), then says so with
/// "Geri al" — which deletes that expense and puts the due date back
/// (§6.6, D29). A second call for the same subscription while the first is
/// on its way does nothing. The charge as recorded, or null.
Future<SubscriptionCharge?> markSubscriptionPaid(
  BuildContext context,
  WidgetRef ref,
  SubscriptionLite s,
) async {
  final inFlight = ref.read(subscriptionChargesInFlightProvider.notifier);
  if (!inFlight.claim(s.id)) return null;
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  var unsure = false;
  try {
    final charge = await repo.chargeSubscription(s.id);
    // "Ödendi" confirms (§5.8).
    Haptics.confirm();
    if (context.mounted) {
      final tx = charge.transaction;
      final messenger = ScaffoldMessenger.of(context);
      showAppSnack(
        context,
        l.subscriptionCharged(formatMoney(
          tx?.amountCents ?? s.amountCents,
          tx?.account.currency ?? s.account.currency,
          tx?.account.subunitToUnit ?? s.account.subunitToUnit,
        )),
        actionLabel: l.actionUndo,
        onAction: () =>
            undoSubscriptionCharge(messenger, l, repo, charge, s.nextChargeOn),
      );
    }
    return charge;
  } catch (e) {
    if (context.mounted) {
      // A lost answer may still have recorded it: say so rather than
      // invite a second payment.
      final maybe = e is ApiException && e.isNetwork && e.mayHaveArrived;
      unsure = maybe;
      showAppSnack(
        context,
        maybe
            ? l.subscriptionChargeMaybe
            : failureMessage(e, l, fallback: l.subscriptionChargeFailed),
        isError: true,
      );
    } else {
      unsure = e is ApiException && e.isNetwork && e.mayHaveArrived;
      Haptics.reject();
    }
    return null;
  } finally {
    // A lost answer holds every "Ödendi" of it until the list says.
    unsure ? inFlight.holdUntilRefetched(s.id) : inFlight.release(s.id);
  }
}

/// Takes a payment back: moves the due date back to [dueBefore], then
/// deletes the expense it recorded — in that order, since deleting a
/// payment does not move the date (contract 4.6): should the date fail,
/// nothing has changed (unless its answer was lost: then the date may be
/// back, and the message says the payment is still recorded); should the
/// delete fail, only the expense is left, and the message says where to
/// delete it. Said on [messenger] when it
/// fails, as the screen that paid may be gone.
Future<void> undoSubscriptionCharge(
  ScaffoldMessengerState messenger,
  AppL10n l,
  MeridianRepository repo,
  SubscriptionCharge charge,
  DateTime? dueBefore,
) async {
  final sub = charge.subscription;
  if (dueBefore != null) {
    try {
      await repo.updateSubscription(
        sub,
        SubscriptionInput(
          name: sub.name,
          accountId: sub.account.id,
          amountCents: sub.amountCents,
          frequency: sub.frequency,
          nextChargeOn: dueBefore,
          categoryId: sub.category?.id,
          vendor: sub.vendor,
          note: sub.note,
          color: sub.color,
        ),
        accountCurrency: sub.account.currency,
      );
    } catch (e) {
      // A lost answer may have moved the date back all the same: the row
      // may say it is due again while its payment is still recorded.
      final maybe = e is ApiException && e.isNetwork && e.mayHaveArrived;
      showAppSnackOn(
        messenger,
        maybe ? l.subscriptionUndoUnsure : l.subscriptionUndoNothingChanged,
        isError: true,
      );
      return;
    }
  }
  final tx = charge.transaction;
  if (tx == null) return;
  try {
    await repo.deleteTransaction(tx.id);
  } catch (_) {
    showAppSnackOn(messenger, l.subscriptionUndoFailed, isError: true);
  }
}

// --- Agenda ---------------------------------------------------------------------

/// Opens the task sheet: a new task due on [initialDate] (none: no date),
/// or [existing] to edit. The task as saved, or null.
Future<Todo?> openTodoSheet(
  BuildContext context, {
  Todo? existing,
  DateTime? initialDate,
}) =>
    todo_sheet.openTodoSheet(context, existing: existing, due: initialDate);

/// Opens the event form: [existing] to edit, or a new event on [day]
/// (today without one), titled [title] when the caller has one (quick
/// add's line). The event as saved, or null.
Future<Event?> openEventForm(
  BuildContext context, {
  Event? existing,
  DateTime? day,
  String? title,
}) {
  if (existing == null && title != null && title.trim().isNotEmpty) {
    final on = day ??
        ProviderScope.containerOf(context, listen: false)
            .read<DateTime>(currentDayProvider);
    return event_form.openEventForm(
      context,
      suggestion: EventSuggestion(
        title: title.trim(),
        date: DateTime(on.year, on.month, on.day),
        allDay: false,
      ),
    );
  }
  return event_form.openEventForm(context, existing: existing, day: day);
}

// --- Goals ----------------------------------------------------------------------

/// Opens the goal form: [existing] to edit, or a new goal of [type]
/// (`financial`, `habit`, `custom`). With [habitId], a new habit goal
/// already linked to that habit (`related: Habit-<id>`) — the habit's "Bu
/// alışkanlık için hedef koy". The goal as saved, or null.
Future<Goal?> openGoalForm(
  BuildContext context, {
  Goal? existing,
  String? type,
  int? habitId,
}) =>
    goal_form.openGoalForm(
      context,
      goal: existing,
      type: type,
      habitId: habitId,
    );

// --- Habits ---------------------------------------------------------------------

/// Opens habit [habitId]'s log for [date] (today without one): set the day's
/// count exactly, mark it done or reset it.
Future<void> openHabitLog(
  BuildContext context, {
  required int habitId,
  DateTime? date,
}) =>
    habit_log.showHabitLogSheet(context, habitId: habitId, date: date);

/// Opens [habit]'s detail sheet — from another screen, such as a habit
/// goal's "Alışkanlığa git" (WP-12). Resolves when it is closed.
Future<void> openHabitDetail(BuildContext context, Habit habit) =>
    habit_detail.showHabitDetailSheet(context, habit);
