import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/providers.dart';

import 'fake_api.dart';

/// A container wired to [api]: the real repository, DataSync and read models,
/// with only the network faked. No automatic retries, so a failing fetch
/// settles at once.
ProviderContainer containerFor(FakeApi api, {List<Override> overrides = const []}) =>
    ProviderContainer.test(
      overrides: [dioProvider.overrideWithValue(api.dio), ...overrides],
      retry: (_, _) => null,
    );

/// Every read model as a screen would hold it, keyed by the GET path it
/// fetches. Listening keeps each one active, like a visible screen.
Map<String, ProviderListenable<AsyncValue<Object?>>> readModelsByPath() => {
      '/home': homeProvider,
      '/me/options': meOptionsProvider,
      '/habits': habitsProvider,
      '/habits/7': habitDetailProvider(7),
      '/goals': goalsProvider,
      '/goals/3': goalDetailProvider(3),
      '/accounts': accountsProvider,
      '/accounts/1': accountDetailProvider(1),
      '/currencies': currenciesProvider,
      '/finance/dashboard': financeDashboardProvider,
      '/finance_categories': categoriesProvider,
      '/finance_categories/5': categoryUsageProvider(5),
      '/budgets': budgetsProvider,
      '/subscriptions': subscriptionsProvider,
      '/transactions': transactionsProvider(const TxFilters()),
      '/transactions/316': transactionDetailProvider(316),
      '/todos': todosProvider(const TodoQuery(filter: 'today')),
      '/todo_lists': todoListsProvider,
      '/events': eventsTodayProvider,
      '/events/12': eventDetailProvider(12),
      '/journal_entries': journalProvider('30d'),
      '/journal_entries/20': journalEntryProvider(20),

      // A new read model is listed in its work package's region.
      // region shell (WP-4)
      // endregion

      // region today (WP-5)
      // endregion

      // region quick capture (WP-6)
      // endregion

      // region agenda (WP-7)
      // endregion

      // region finance (WP-8)
      // endregion

      // region transactions (WP-9)
      // endregion

      // region categories, budgets, subscriptions (WP-10)
      // endregion

      // region habits (WP-11)
      // endregion

      // region goals (WP-12)
      // endregion

      // region journal (WP-13)
      // endregion

      // region profile (WP-14)
      // endregion

      // region search (WP-16)
      // endregion
    };

/// Shows every read model (as visible screens would) and waits until each
/// has loaded, then clears the request log.
Future<void> showEverything(ProviderContainer container, FakeApi api) async {
  for (final model in readModelsByPath().values) {
    container.listen(model, (_, _) {});
  }
  await settle(api);
  for (final entry in readModelsByPath().entries) {
    final value = container.read(entry.value);
    if (!value.hasValue) {
      throw StateError('${entry.key} did not load: $value');
    }
  }
  api.clearLog();
}

/// Lets queued work run to completion: DataSync's flush, Riverpod's
/// refresh, the fake HTTP round trips. Waits until the request log has
/// stopped growing — for long enough that a request which follows another
/// one's answer (a refetch queued by a write's report) is not missed.
Future<void> settle(FakeApi api) async {
  var quiet = 0;
  var seen = api.requests.length;
  for (var i = 0; i < 400 && quiet < 20; i++) {
    await Future<void>.delayed(Duration.zero);
    if (api.requests.length == seen) {
      quiet++;
    } else {
      seen = api.requests.length;
      quiet = 0;
    }
  }
}
