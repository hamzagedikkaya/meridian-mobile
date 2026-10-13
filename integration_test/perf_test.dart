/// The performance budgets (design-analysis §8.7), measured on a phone.
///
/// Every scenario of the budget table runs inside `binding.traceAction`,
/// which records the engine's timeline; `test_driver/perf_driver.dart`
/// turns each into a `TimelineSummary`, writes it under `build/` and fails
/// the run when a frame breaks the 120 Hz budget.
///
/// The app runs as it ships — `MeridianApp`, the real router, theme, fonts
/// and read models — signed in against the scripted API of the widget tests
/// (`test/support/fake_api.dart`), so the numbers measure the UI and not the
/// network, and no server or real data is touched. The transactions list
/// is 500 rows long, served 50 to a page as the server does.
///
/// Run it on the Android 16 phone, in a **profile** build (debug numbers
/// mean nothing), with the screen on and unlocked:
///
/// ```sh
/// flutter drive --profile \
///   --driver=test_driver/perf_driver.dart \
///   --target=integration_test/perf_test.dart \
///   -d <device-id>
/// ```
///
/// Results: `build/<scenario>.timeline_summary.json` (and the full
/// `build/<scenario>.timeline.json`, which opens in Perfetto). The checklist
/// in `docs/qa-2026-10.md` says what to record.
///
/// Cold start ("Bugün içeriği < 1 sn") is not measurable from inside a test
/// (the engine is already up): measure it with
/// `flutter run --profile --trace-startup` (`build/start_up_info.json`).
/// `today_first_content_ms` below is the in-app part only — from the first
/// frame of `MeridianApp` to Today's content — and is reported, not gated.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/ui/flows/flows.dart' as flows;
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_stores.dart';

/// How many transactions the fling scrolls through (§8.7: 500).
const _transactionCount = 500;

/// The server's page size for `GET /transactions`.
const _pageSize = 50;

/// One frame at 120 Hz: what the scenarios pump between steps so the
/// engine draws every frame it would on the phone.
const _frame = Duration(microseconds: 8333);

/// [_transactionCount] rows over the last months, newest first: expenses
/// and incomes on two accounts, some categorised, a few with notes.
List<Map<String, dynamic>> _transactions() {
  final first = DateTime(2026, 10, 4);
  return [
    for (var i = 0; i < _transactionCount; i++)
      {
        ...transactionJson(id: 1000 + i),
        'kind': i % 7 == 0 ? 'income' : 'expense',
        'amount_cents': 1250 + (i * 7919) % 250000,
        'date': _iso(first.subtract(Duration(days: i ~/ 4))),
        'description': _descriptions[i % _descriptions.length],
        'note': i % 5 == 0 ? 'Not $i' : null,
        'category': i % 3 == 0
            ? null
            : {
                'id': 5,
                'name': 'Market',
                'kind': 'expense',
                'color': '#7FB069',
                'position': 0,
              },
      },
  ];
}

const _descriptions = [
  'Kahve',
  'Market alışverişi',
  'Maaş',
  'Kira',
  'Otobüs kartı',
  'Akşam yemeği',
  'Elektrik faturası',
  'Kitap',
];

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `GET /transactions`, a page at a time, as the server pages it.
Object? Function(RequestOptions request) _pagedFeed(
  List<Map<String, dynamic>> rows,
) =>
    (request) {
      final page =
          int.tryParse('${request.queryParameters['page'] ?? 1}') ?? 1;
      final start = (page - 1) * _pageSize;
      final slice = rows.skip(start).take(_pageSize).toList();
      int total(String kind) => rows
          .where((row) => row['kind'] == kind)
          .fold(0, (sum, row) => sum + (row['amount_cents'] as int));
      return {
        'transactions': slice,
        'meta': {
          'total_count': rows.length,
          'page': page,
          'page_limit': _pageSize,
          'filtered_income_cents': total('income'),
          'filtered_expense_cents': total('expense'),
        },
      };
    };

/// Signed in, Turkish, the dark theme, the system's motion setting.
Future<GoRouter> _launch(WidgetTester tester, FakeApi api) async {
  SharedPreferences.setMockInitialValues({
    PrefKeys.locale: 'tr',
    PrefKeys.themeMode: 'dark',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(api.dio),
      ...signedInOverrides(tokens: MemoryTokenStore()),
    ],
    child: const MeridianApp(),
  ));
  return tester.container().read(routerProvider);
}

/// Lets [duration] of frames run, one 120 Hz frame at a time.
Future<void> _run(WidgetTester tester, Duration duration) async {
  final frames = duration.inMicroseconds ~/ _frame.inMicroseconds;
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
  }
}

/// Pumps until [finder] shows, for at most [timeout].
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('timed out waiting for $finder');
    }
    await tester.pump(_frame);
  }
}

/// A tab of the navigation bar, by its label.
Finder _tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

/// A context inside the shell, to open sheets and forms from.
BuildContext _shellContext(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).last);

/// Closes the sheet or form on top (the system back).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _run(tester, const Duration(milliseconds: 500));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Every frame the framework schedules is drawn, as in the app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    await initializeDateFormatting();
    await Haptics.init();
  });

  testWidgets('performance budgets (§8.7)', (tester) async {
    final api = FakeApi()
      ..onRequest('GET /transactions', _pagedFeed(_transactions()));

    // --- Today's first content -------------------------------------------
    final started = Stopwatch()..start();
    final router = await _launch(tester, api);
    await _waitFor(tester, find.byType(CheckPop));
    started.stop();
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['today_first_content_ms'] =
        started.elapsedMilliseconds;
    await _run(tester, const Duration(seconds: 1));

    // --- Tab switches (FadeThrough) -----------------------------------------
    await binding.traceAction(() async {
      for (var round = 0; round < 2; round++) {
        for (final label in [
          'Ajanda',
          'Finans',
          'Alışkanlık',
          'Günlük',
          'Bugün',
        ]) {
          await tester.tap(_tab(label));
          await _run(tester, const Duration(milliseconds: 600));
        }
      }
    }, reportKey: 'tab_switch');

    // --- Check-off on Today and on Habits ---------------------------------
    await binding.traceAction(() async {
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byType(CheckPop).first);
        await _run(tester, const Duration(milliseconds: 700));
      }
    }, reportKey: 'check_off_today');

    await tester.tap(_tab('Alışkanlık'));
    await _run(tester, const Duration(milliseconds: 600));
    await _waitFor(tester, find.byType(CheckPop));
    await binding.traceAction(() async {
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byType(CheckPop).first);
        await _run(tester, const Duration(milliseconds: 700));
      }
    }, reportKey: 'check_off_habits');

    // --- Sheet open and close (quick add, the habit's log) ------------------
    await tester.tap(_tab('Bugün'));
    await _run(tester, const Duration(milliseconds: 600));
    await binding.traceAction(() async {
      for (var i = 0; i < 3; i++) {
        flows.openQuickAdd(_shellContext(tester));
        await _run(tester, const Duration(milliseconds: 600));
        await _back(tester);
        flows.openHabitLog(_shellContext(tester), habitId: 7);
        await _run(tester, const Duration(milliseconds: 600));
        await _back(tester);
      }
    }, reportKey: 'sheet_open');

    // --- The keypad at eight keys a second ----------------------------------
    flows.openTransactionForm(_shellContext(tester));
    await _run(tester, const Duration(milliseconds: 700));
    await _waitFor(tester, find.byType(AmountKeypad));
    Finder key(String label) => find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.text(label),
        );
    await binding.traceAction(() async {
      for (final digit in '1234567890'.split('')) {
        await tester.tap(key(digit));
        await _run(tester, const Duration(milliseconds: 125));
      }
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.byIcon(Icons.backspace_outlined),
        ));
        await _run(tester, const Duration(milliseconds: 125));
      }
    }, reportKey: 'keypad');
    await _back(tester);
    // The form asks before it drops a typed amount; the keys above cleared
    // it, so it closes. If a discard prompt is up anyway, leave it.
    if (find.byType(AmountKeypad).evaluate().isNotEmpty) await _back(tester);

    // --- 500 transactions, flung down and back ------------------------------
    router.go('/finance/transactions');
    await _run(tester, const Duration(seconds: 1));
    await _waitFor(tester, find.text(_descriptions.first));
    final list = find.byType(Scrollable).first;
    await binding.traceAction(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(list, const Offset(0, -1200), 4000);
        await _run(tester, const Duration(milliseconds: 1200));
      }
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, 1500), 5000);
        await _run(tester, const Duration(milliseconds: 1200));
      }
    }, reportKey: 'transactions_fling');
  });
}
