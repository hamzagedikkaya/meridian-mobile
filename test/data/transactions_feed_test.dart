import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/transaction.dart';

import '../support/fake_api.dart';
import '../support/read_models.dart';

/// Page [page] of a 60-row history: 50 rows, then 10.
Map<String, dynamic> _page(RequestOptions request) {
  final page = int.parse('${request.queryParameters['page'] ?? 1}');
  final ids = page == 1
      ? [for (var i = 0; i < 50; i++) 1000 - i]
      : page == 2
          ? [for (var i = 50; i < 60; i++) 1000 - i]
          : const <int>[];
  return {
    'transactions': [for (final id in ids) transactionJson(id: id)],
    'meta': {
      'total_count': 60,
      'page': page,
      'page_limit': 50,
      'filtered_income_cents': 0,
      'filtered_expense_cents': 0,
    },
  };
}

void main() {
  late FakeApi api;
  late ProviderContainer container;
  const filters = TxFilters();

  setUp(() async {
    api = FakeApi()..onRequest('GET /transactions', _page);
    container = containerFor(api);
    container.listen(transactionsProvider(filters), (_, _) {});
    await settle(api);
    await container.read(transactionsProvider(filters).notifier).loadMore();
    await settle(api);
    expect(container.read(transactionsProvider(filters)).value!.items,
        hasLength(60));
    api.clearLog();
  });

  test('a refetch reloads the pages on screen, so the list does not shrink',
      () async {
    container.read(dataSyncProvider).refresh([transactionsProvider]);
    await settle(api);
    expect(api.gets, ['/transactions', '/transactions']);
    final feed = container.read(transactionsProvider(filters)).value!;
    expect(feed.items, hasLength(60));
    expect(feed.hasMore, isFalse);
  });

  test('a delete drops the row at once, then the refetch keeps the pages',
      () async {
    final notifier = container.read(transactionsProvider(filters).notifier);
    api.on('DELETE /transactions/1000', null, status: 204);
    await container.read(repositoryProvider).deleteTransaction(1000);
    notifier.removeLocally(1000);
    expect(container.read(transactionsProvider(filters)).value!.items,
        hasLength(59));
    await settle(api);
    expect(api.gets.where((g) => g == '/transactions'), hasLength(2));
  });

  group('a long scroll (320 rows: six full pages and a short seventh)', () {
    /// The server's rows, newest first: ids 5000, 4999, … — [added] new ones
    /// on top, without [deleted].
    late List<int> rows;

    Map<String, dynamic> page(RequestOptions request) {
      final page = int.parse('${request.queryParameters['page'] ?? 1}');
      final first = (page - 1) * 50;
      final last = first + 50 > rows.length ? rows.length : first + 50;
      return {
        'transactions': [
          for (var i = first; i < last; i++) transactionJson(id: rows[i]),
        ],
        'meta': {
          'total_count': rows.length,
          'page': page,
          'page_limit': 50,
          'filtered_income_cents': 0,
          'filtered_expense_cents': 0,
        },
      };
    }

    late FakeApi long;
    late ProviderContainer c;
    late TransactionsNotifier notifier;

    List<int> ids() => [
          for (final t in c.read(transactionsProvider(filters)).value!.items)
            t.id,
        ];

    setUp(() async {
      rows = [for (var i = 0; i < 320; i++) 5000 - i];
      long = FakeApi()..onRequest('GET /transactions', page);
      c = containerFor(long);
      c.listen(transactionsProvider(filters), (_, _) {});
      await settle(long);
      notifier = c.read(transactionsProvider(filters).notifier);
      for (var i = 0; i < 6; i++) {
        await notifier.loadMore();
      }
      expect(ids(), hasLength(320));
      long.clearLog();
    });

    test('a refetch reloads five pages at most, one request each, and keeps '
        'the rows beyond them: the list keeps its length, so the scroll '
        'position holds', () async {
      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(long);
      expect(long.gets, hasLength(TransactionsNotifier.reloadPages));
      final feed = c.read(transactionsProvider(filters)).value!;
      expect(feed.items, hasLength(320));
      expect(ids(), rows, reason: 'in order, each row once');
      expect(feed.hasMore, isFalse, reason: 'the kept rows reach the end');
    });

    test('rows added on top while away shift nothing: each row is listed '
        'once, the fresh ones first', () async {
      rows = [6001, 6000, ...rows];
      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(long);
      expect(ids(), rows);
    });

    test('rows deleted elsewhere above the seam are gone; the kept rows are '
        'as they were', () async {
      rows = [...rows]..removeAt(10);
      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(long);
      expect(ids(), rows);
    });

    test('a short history after the refetch (the server has fewer rows now) '
        'is shown as the server sent it', () async {
      rows = rows.take(120).toList();
      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(long);
      expect(ids(), rows);
      expect(c.read(transactionsProvider(filters)).value!.hasMore, isFalse);
    });

    test('an edit made in the app replaces its row in place, also among the '
        'kept rows past the reloaded pages', () async {
      final deep = rows[300];
      notifier.replaceLocally(Transaction.fromJson({
        ...transactionJson(id: deep),
        'description': 'Düzeltildi',
      }));
      var feed = c.read(transactionsProvider(filters)).value!;
      expect(feed.items.firstWhere((t) => t.id == deep).description,
          'Düzeltildi');
      expect(feed.items, hasLength(320));

      // The edit's refetch keeps the edited row as it is now.
      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(long);
      feed = c.read(transactionsProvider(filters)).value!;
      expect(feed.items.firstWhere((t) => t.id == deep).description,
          'Düzeltildi');
    });

    test('an edit that takes a row out of the feed\'s filters drops it',
        () async {
      final account = FakeApi()..onRequest('GET /transactions', page);
      final ac = containerFor(account);
      const byAccount = TxFilters(accountId: 1);
      ac.listen(transactionsProvider(byAccount), (_, _) {});
      await settle(account);
      final moved = Transaction.fromJson({
        ...transactionJson(id: rows.first),
        'account': {
          'id': 2,
          'name': 'Banka',
          'color': '#6B8FA0',
          'currency': 'TRY',
          'subunit_to_unit': 100,
        },
      });
      ac.read(transactionsProvider(byAccount).notifier).replaceLocally(moved);
      final items = ac.read(transactionsProvider(byAccount)).value!.items;
      expect(items.map((t) => t.id), isNot(contains(rows.first)));
      expect(items, hasLength(49));
    });
  });

  group('a row saved in the app that sorts to another day', () {
    // The server's history: 320 rows over 64 days, five a day, newest day
    // first and, within a day, the latest created (the higher id) first —
    // `ORDER BY date DESC, created_at DESC`.
    final today = DateTime(2026, 10, 4);
    late List<({int id, DateTime date})> server;
    late FakeApi api;
    late ProviderContainer c;
    late TransactionsNotifier notifier;

    DateTime daysAgo(int days) => today.subtract(Duration(days: days));

    void sortServer() => server.sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        });

    Map<String, dynamic> rowJson(({int id, DateTime date}) row) =>
        {...transactionJson(id: row.id), 'date': isoDate(row.date)};

    Map<String, dynamic> page(RequestOptions request) {
      final page = int.parse('${request.queryParameters['page'] ?? 1}');
      final first = (page - 1) * 50;
      final last = first + 50 > server.length ? server.length : first + 50;
      return {
        'transactions': [
          for (var i = first; i < last; i++) rowJson(server[i]),
        ],
        'meta': {
          'total_count': server.length,
          'page': page,
          'page_limit': 50,
          'filtered_income_cents': 0,
          'filtered_expense_cents': 0,
        },
      };
    }

    List<int> shown() => [
          for (final t in c.read(transactionsProvider(filters)).value!.items)
            t.id,
        ];

    List<int> onServer() => [for (final row in server) row.id];

    /// Moves row [id] to [date] on the server, and returns it as the
    /// server's answer to the edit.
    Transaction edit(int id, DateTime date) {
      server = [
        for (final row in server)
          row.id == id ? (id: id, date: date) : row,
      ];
      sortServer();
      return Transaction.fromJson(rowJson((id: id, date: date)));
    }

    Future<void> loadPages(int pages) async {
      api = FakeApi()..onRequest('GET /transactions', page);
      c = containerFor(api);
      c.listen(transactionsProvider(filters), (_, _) {});
      await settle(api);
      notifier = c.read(transactionsProvider(filters).notifier);
      for (var i = 1; i < pages; i++) {
        await notifier.loadMore();
      }
    }

    setUp(() {
      server = [
        for (var i = 0; i < 320; i++) (id: 5000 - i, date: daysAgo(i ~/ 5)),
      ];
    });

    test('an edit that sends a recent row back two months, among the rows '
        'already loaded: shown there at once, and kept there by the edit\'s '
        'refetch, which reloads only the first pages', () async {
      await loadPages(7);
      expect(shown(), onServer());
      // Row 5 (yesterday) goes back to the day of row 300: past the 250
      // rows a refetch reloads.
      final moved = edit(4995, daysAgo(60));
      notifier.replaceLocally(moved);
      expect(shown(), onServer(), reason: 'at its new place at once');

      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(api);
      expect(api.gets.where((g) => g == '/transactions'),
          hasLength(7 + TransactionsNotifier.reloadPages));
      expect(shown(), onServer(),
          reason: 'still listed, once, where the server lists it');
    });

    test('an edit to the day the reloaded pages end on is kept on that day, '
        'also when the server lists it after that day\'s other rows (they '
        'were created later, though their ids are lower)', () async {
      await loadPages(7);
      // Row 5 goes to the day of rows 250-254, where the server lists it
      // last: just past the 250 rows a refetch reloads.
      final day = daysAgo(50);
      server = [
        for (final row in server)
          if (row.id != 4995) row,
      ];
      final end = server.lastIndexWhere((row) => row.date == day);
      server.insert(end + 1, (id: 4995, date: day));
      notifier.replaceLocally(
        Transaction.fromJson(rowJson((id: 4995, date: day))),
      );

      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(api);
      final items = c.read(transactionsProvider(filters)).value!.items;
      expect(items.where((t) => t.id == 4995), hasLength(1),
          reason: 'not lost between the reloaded pages and the kept rows');
      expect(items, hasLength(320));
      expect(shown().toSet(), onServer().toSet());
      final at = items.indexWhere((t) => t.id == 4995);
      expect(items[at - 1].date, day);
      expect(items[at + 1].date, day);
    });

    test('an edit within the day keeps the row where it is', () async {
      await loadPages(2);
      final before = shown();
      final edited = Transaction.fromJson({
        ...rowJson(server[3]),
        'description': 'Düzeltildi',
      });
      notifier.replaceLocally(edited);
      expect(shown(), before);
      expect(
        c.read(transactionsProvider(filters)).value!.items[3].description,
        'Düzeltildi',
      );
    });

    test('a back-dated new transaction goes among the rows already loaded, '
        'and the refetch keeps it there', () async {
      await loadPages(7);
      server = [...server, (id: 6000, date: daysAgo(55))];
      sortServer();
      notifier.replaceLocally(
        Transaction.fromJson(rowJson((id: 6000, date: daysAgo(55)))),
      );
      expect(shown(), onServer());

      c.read(dataSyncProvider).refresh([transactionsProvider]);
      await settle(api);
      expect(shown(), onServer());
    });

    test('a row sent past the rows loaded so far is left to infinite '
        'scroll, which brings it where the server lists it', () async {
      await loadPages(2);
      final moved = edit(4995, daysAgo(60));
      notifier.replaceLocally(moved);
      expect(shown(), isNot(contains(4995)));
      expect(shown(), hasLength(99));

      for (var i = 0;
          i < 6 && c.read(transactionsProvider(filters)).value!.hasMore;
          i++) {
        await notifier.loadMore();
      }
      expect(shown(), onServer());
    });
  });

  test('after a delete, infinite scroll pages on from the rows on screen and '
      'skips none', () async {
    // 120 rows; two pages loaded, then the newest is deleted.
    var rows = [for (var i = 0; i < 120; i++) 3000 - i];
    Map<String, dynamic> page(RequestOptions request) {
      final page = int.parse('${request.queryParameters['page'] ?? 1}');
      final first = (page - 1) * 50;
      final last = first + 50 > rows.length ? rows.length : first + 50;
      return {
        'transactions': [
          for (var i = first; i < last; i++) transactionJson(id: rows[i]),
        ],
        'meta': {
          'total_count': rows.length,
          'page': page,
          'page_limit': 50,
          'filtered_income_cents': 0,
          'filtered_expense_cents': 0,
        },
      };
    }

    final api = FakeApi()..onRequest('GET /transactions', page);
    final c = containerFor(api);
    c.listen(transactionsProvider(filters), (_, _) {});
    await settle(api);
    final notifier = c.read(transactionsProvider(filters).notifier);
    await notifier.loadMore();
    rows = rows.sublist(1); // deleted on the server
    notifier.removeLocally(3000);
    for (var i = 0;
        i < 5 && c.read(transactionsProvider(filters)).value!.hasMore;
        i++) {
      await notifier.loadMore();
    }
    final ids = [
      for (final t in c.read(transactionsProvider(filters)).value!.items) t.id,
    ];
    expect(ids, rows, reason: 'no row skipped, none twice');
  });

  test('a page that arrives after a refetch began is not appended', () async {
    // Start over with one page loaded and its next page in flight.
    final fresh = FakeApi()..onRequest('GET /transactions', _page);
    final c = containerFor(fresh);
    c.listen(transactionsProvider(filters), (_, _) {});
    await settle(fresh);

    fresh.hold('GET /transactions');
    final more = c.read(transactionsProvider(filters).notifier).loadMore();
    await settle(fresh);
    c.read(dataSyncProvider).refresh([transactionsProvider]);
    fresh.release('GET /transactions');
    await more;
    await settle(fresh);

    final items = c.read(transactionsProvider(filters)).value!.items;
    expect(items.map((t) => t.id).toSet(), hasLength(items.length),
        reason: 'no duplicated rows');
    expect(items, hasLength(50), reason: 'the refetch had one page to reload');
  });
}
