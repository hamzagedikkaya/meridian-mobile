import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/habit.dart';
import '../../models/quick_capture.dart';
import '../screens/agenda/event_form.dart';
import '../screens/finance/account_form.dart';
import '../screens/habits/habit_form.dart';

/// The create forms a screen opens for something that is not its own tab's
/// — quick capture turning a refusal into the next step ("create the
/// account", "create the habit", "add it as an event"), and later the Today
/// "Ekle" button — so every entry point opens the same form, and a test can
/// stand in for it.
///
/// A flow that does not exist yet is null, and the action that would open it
/// is not offered. Each one resolves once the form is closed and says
/// whether something was created, so the caller can carry on (quick capture
/// sends the line again).
class CreateFlows {
  const CreateFlows();

  /// The new-account form (`POST /accounts`); true once an account was
  /// created. Quick capture's `no_account` answer opens it, then sends the
  /// line again.
  Future<bool> Function(BuildContext context)? get account =>
      (context) async => await openAccountForm(context) != null;

  /// The new-event form, prefilled from a quick-capture suggestion (its
  /// title, day and time); true once the event was saved.
  Future<bool> Function(BuildContext context, EventSuggestion suggestion)?
  get event => (context, suggestion) async =>
      await openEventForm(context, suggestion: suggestion) != null;

  /// The habit form with [name] filled in; the habit it created, or null
  /// when it was closed without saving.
  Future<Habit?> habit(BuildContext context, {String? name}) =>
      openHabitForm(context, initialName: name);
}

final createFlowsProvider = Provider<CreateFlows>((ref) => const CreateFlows());
