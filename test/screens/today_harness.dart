/// What Today reads besides `/home`, served without a network: the
/// accounts (the money chip, the first-run card), the week's journal (the
/// journal card), today's events, the Habits list (yesterday's nudge) and
/// the finance dashboard (a late payment's nudge). Shared by Today's
/// screen tests and goldens (WP-5).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/finance_dashboard.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/journal.dart';

/// One active cash account.
Map<String, dynamic> todayAccountJson() => {
  'id': 1,
  'name': 'Cüzdan',
  'account_type': 'cash',
  'currency': 'TRY',
  'subunit_to_unit': 100,
  'color': '#D4A574',
  'initial_balance_cents': 0,
  'balance_cents': 500000,
  'archived': false,
  'archived_at': null,
};

/// A journal list item written on [date] (`YYYY-MM-DD`).
Map<String, dynamic> todayJournalEntryJson(String date, {int id = 20}) => {
  'id': id,
  'date': date,
  'title': null,
  'body_plain': 'Sakin bir gün. Akşam yürüyüşe çıktım.',
  'mood': 'good',
  'mood_emoji': '🙂',
  'energy_level': 3,
  'weather': null,
  'tags': const [],
  'has_gratitude': false,
  'created_at': '${date}T19:00:00.000+03:00',
};

/// The read models Today shows besides `/home`, as given, fetched [at].
/// Null leaves that model alone (it fetches as it would).
List<Override> todayReadOverrides({
  required DateTime at,
  List<Map<String, dynamic>>? accounts = const [],
  List<Map<String, dynamic>>? journal = const [],
  List<Map<String, dynamic>>? events,
  List<Map<String, dynamic>>? habits = const [],
  List<Map<String, dynamic>>? subscriptions = const [],
}) => [
  if (accounts != null)
    accountsProvider.overrideWith(
      (ref) async =>
          Fetched([for (final a in accounts) Account.fromJson(a)], at),
    ),
  if (journal != null)
    journalProvider.overrideWith(
      (ref, range) async => Fetched(
        JournalBundle.fromJson({
          'entries': journal,
          'meta': {
            'entries_count': journal.length,
            'journal_streak': journal.isEmpty ? 0 : 1,
            'mood_counts': const <String, int>{},
            'range': range,
          },
        }),
        at,
      ),
    ),
  if (events != null)
    eventsProvider.overrideWith(
      (ref, window) async =>
          Fetched([for (final e in events) Event.fromJson(e)], at),
    ),
  if (habits != null)
    habitsProvider.overrideWithBuild(
      (ref, _) => Fetched(
        HabitsBundle.fromJson({'habits': habits, 'meta': const {}}),
        at,
      ),
    ),
  if (subscriptions != null)
    financeDashboardProvider.overrideWith(
      (ref) async => Fetched(
        FinanceDashboard.fromJson({
          'currency': 'TRY',
          'subunit_to_unit': 100,
          'upcoming_subscriptions': subscriptions,
        }),
        at,
      ),
    ),
];
