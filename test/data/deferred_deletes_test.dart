/// Deletes with "Geri al" (design-research §4.3): the record leaves the
/// lists at once, nothing is sent until the undo window closes, undo sends
/// nothing, and a refused delete brings the record back.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/api.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/deferred_deletes.dart';
import 'package:meridian_mobile/data/providers.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

const _tx = (scope: DataScope.transactions, id: 316);
const _budget = (scope: DataScope.budgets, id: 2);

void main() {
  late FakeApi api;
  late ProviderContainer container;
  late DeferredDeletes deletes;

  Future<void> send316() =>
      container.read(repositoryProvider).deleteTransaction(316);

  setUp(() {
    api = FakeApi();
    container = containerFor(api);
    deletes = container.read(deferredDeletesProvider.notifier);
  });

  test('staged: off the lists at once, and nothing is sent', () async {
    deletes.stage(_tx, send: send316);
    expect(container.read(deferredDeletesProvider), {_tx});
    expect(deletes.hides(DataScope.transactions, 316), isTrue);
    expect(deletes.isWaiting(_tx), isTrue);
    await settle(api);
    expect(api.requests, isEmpty);
  });

  test('undo: back on the lists, and still nothing is sent', () async {
    deletes.stage(_tx, send: send316);
    expect(deletes.undo(_tx), isTrue);
    expect(container.read(deferredDeletesProvider), isEmpty);
    expect(await deletes.commit(_tx), isFalse, reason: 'nothing to send');
    await settle(api);
    expect(api.requests, isEmpty);
  });

  test('commit: the delete goes out and the record stays off the lists',
      () async {
    deletes.stage(_tx, send: send316);
    expect(await deletes.commit(_tx), isTrue);
    expect(api.requests, ['DELETE /transactions/316']);
    expect(container.read(deferredDeletesProvider), {_tx});
    expect(deletes.undo(_tx), isFalse, reason: 'too late: it was sent');
    // Sent once, whatever closes the window after.
    expect(await deletes.commit(_tx), isFalse);
    expect(api.requests, ['DELETE /transactions/316']);
  });

  test('a refused delete brings the record back and says why', () async {
    api.fail('DELETE /transactions/316', 500);
    Object? failure;
    deletes.stage(_tx, send: send316, onFailed: (e) => failure = e);
    expect(await deletes.commit(_tx), isFalse);
    expect(container.read(deferredDeletesProvider), isEmpty);
    expect(failure, isA<ApiException>());
  });

  test('a record already gone on the server (404) counts as deleted',
      () async {
    api.fail('DELETE /transactions/316', 404);
    Object? failure;
    deletes.stage(_tx, send: send316, onFailed: (e) => failure = e);
    expect(await deletes.commit(_tx), isTrue);
    expect(container.read(deferredDeletesProvider), {_tx});
    expect(failure, isNull);
  });

  test('one undo at a time: a newer delete sends the one still waiting',
      () async {
    deletes.stage(_tx, send: send316);
    deletes.stage(
      _budget,
      send: () => container.read(repositoryProvider).deleteBudget(2),
    );
    await settle(api);
    expect(
      api.requests.where((r) => r.startsWith('DELETE ')),
      ['DELETE /transactions/316'],
    );
    expect(deletes.isWaiting(_tx), isFalse);
    expect(deletes.isWaiting(_budget), isTrue);
  });

  test('going to the background sends every delete still waiting', () async {
    deletes.stage(_tx, send: send316);
    expect(deletes.hasWaiting, isTrue);
    await deletes.commitAll();
    expect(api.requests, ['DELETE /transactions/316']);
    expect(deletes.hasWaiting, isFalse);
  });

  test('a deleted transaction leaves every open feed, so infinite scroll '
      'pages on from the rows really left', () async {
    // Two feeds that both list it: all transactions, and its account's.
    const all = TxFilters();
    const account = TxFilters.account(1);
    api.onRequest('GET /transactions', (RequestOptions _) => {
          'transactions': [transactionJson(), transactionJson(id: 317)],
          'meta': const {'total_count': 2, 'page': 1, 'page_limit': 50},
        });
    container.listen(transactionsProvider(all), (_, _) {});
    container.listen(transactionsProvider(account), (_, _) {});
    await settle(api);

    deletes.stage(_tx, send: send316);
    // Staged: still in the feeds (the server still has it); the screens
    // leave it out.
    expect(
      container.read(transactionsProvider(all)).value!.items.map((t) => t.id),
      [316, 317],
    );
    await deletes.commit(_tx);
    for (final filters in [all, account]) {
      expect(
        container
            .read(transactionsProvider(filters))
            .value!
            .items
            .map((t) => t.id),
        [317],
        reason: '$filters',
      );
    }
  });

  test('withoutDeleted leaves out only the scope\'s hidden ids', () {
    final hidden = {_tx, (scope: DataScope.budgets, id: 317)};
    expect(
      withoutDeleted([316, 317, 318], hidden, DataScope.transactions, (id) => id),
      [317, 318],
    );
    expect(
      withoutDeleted([316, 317], const {}, DataScope.transactions, (id) => id),
      [316, 317],
    );
  });
}
