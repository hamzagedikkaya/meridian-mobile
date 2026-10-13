/// Haptic regressions (design-analysis §5.8, §8.9), in the whole app as it
/// runs on a phone: `MeridianApp` signed in, the real router, read models
/// and `CelebrationLayer`, the scripted API behind the real repository.
/// Every `HapticFeedback.vibrate` the platform channel receives is recorded.
///
/// 1. Check a habit on Alışkanlıklar, go back to Bugün: exactly one haptic.
/// 2. Check it in the log sheet opened over Bugün: one haptic for the tap,
///    one (confirm) for the save — one per gesture.
/// 3. A background refetch that brings a habit back done: none.
/// 4. The tap that finishes the day: exactly one, `successNotification`.
/// 5. Switching tabs: none.
/// 6. A swipe to delete: one `selectionClick` at the threshold, none for
///    the delete itself.
/// 7. A pull to refresh: one `mediumImpact`; a retry button: none.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/sync.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/ui/flows/flows.dart' as flows;
import 'package:meridian_mobile/ui/screens/habits/habit_card.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/swipe_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/fake_stores.dart';

const _light = 'HapticFeedbackType.lightImpact';
const _success = 'HapticFeedbackType.successNotification';
const _tick = 'HapticFeedbackType.selectionClick';
const _armed = 'HapticFeedbackType.mediumImpact';

/// `HapticFeedback.vibrate` calls, by argument.
final _played = <String?>[];

/// Lets the fake API answer and the screens settle (some show progress
/// that never ends while loading, so `pumpAndSettle` cannot be used).
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app on a 360×780 dp phone, signed in, at [location].
Future<GoRouter> _pumpApp(
  WidgetTester tester,
  FakeApi api, {
  String location = '/today',
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
    retry: (_, _) => null,
    child: const MeridianApp(),
  ));
  await _settle(tester);
  final router = tester.container().read(routerProvider);
  if (location != '/today') {
    router.go(location);
    await _settle(tester);
  }
  // Whatever the start-up played is not what these tests count.
  _played.clear();
  return router;
}

/// A tab of the navigation bar, by its label.
Finder _tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

/// The check of the habit card named [name] on Alışkanlıklar.
Finder _habitCheck(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(HabitCard)),
      matching: find.byType(CheckPop),
    );

/// A context inside the shell, to open sheets and forms from.
BuildContext _shellContext(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).last);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await loadAppFonts();
  });

  setUp(() {
    _played.clear();
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        _played.add(call.arguments as String?);
      }
      return null;
    });
  });

  tearDown(() {
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('1. checked on Alışkanlıklar, then back to Bugün: exactly one '
      'haptic', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api, location: '/habits');
    await tester.tap(_habitCheck('Koşu'));
    await _settle(tester);
    expect(api.requests, contains('PUT /habits/7/logs/2026-10-04'));
    await tester.tap(_tab('Bugün'));
    await _settle(tester);
    // Today shows the habit done, from the same data: it does not buzz.
    expect(_played, [_light]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. the log sheet over Bugün: one haptic for the check, one '
      'for the save', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api);
    flows.openHabitLog(_shellContext(tester), habitId: 7);
    await _settle(tester);
    final check = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(CheckPop),
    );
    expect(check, findsOneWidget);
    await tester.tap(check);
    await _settle(tester);
    expect(_played, [_light], reason: 'the tap on the check');
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    expect(api.requests, contains('PUT /habits/7/logs/2026-10-04'));
    expect(_played, [_light, _success], reason: 'the save confirms, once');
    expect(tester.takeException(), isNull);
  });

  testWidgets('3. a background refetch that completes a habit: no haptic',
      (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api, location: '/habits');
    expect(tester.widget<CheckPop>(_habitCheck('Koşu')).checked, isFalse);
    // Done on the web meanwhile; the app catches up on a refetch.
    api.on('GET /habits', habitsJson(habit7Done: true));
    tester.container().read(dataSyncProvider).refreshAll();
    await _settle(tester);
    expect(tester.widget<CheckPop>(_habitCheck('Koşu')).checked, isTrue,
        reason: 'the refetch landed');
    expect(_played, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('4. the tap that finishes the day: exactly one '
      'successNotification', (tester) async {
    final api = FakeApi()
      ..on('GET /habits', {
        'habits': [
          habitJson(),
          habitJson(
            id: 8,
            name: 'Su',
            targetCount: 3,
            count: 3,
            completed: true,
          ),
        ],
        'meta': habitsMeta(completedToday: 1),
      })
      ..on('PUT /habits/7/logs/2026-10-04', {
        ...logJson(),
        'meta': habitsMeta(completedToday: 2),
      });
    await _pumpApp(tester, api, location: '/habits');
    await tester.tap(_habitCheck('Koşu'));
    await _settle(tester, frames: 60);
    expect(api.requests, contains('PUT /habits/7/logs/2026-10-04'));
    expect(find.text('Hepsi tamam'), findsWidgets, reason: 'the day is done');
    expect(_played, [_success]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. switching tabs: no haptic', (tester) async {
    await _pumpApp(tester, FakeApi());
    for (final label in ['Ajanda', 'Finans', 'Alışkanlık', 'Günlük', 'Bugün']) {
      await tester.tap(_tab(label));
      await _settle(tester);
    }
    expect(_played, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('6. a swipe to delete: one tick at the threshold, none for the '
      'delete', (tester) async {
    final api = FakeApi();
    await _pumpApp(tester, api, location: '/finance/transactions');
    final row = find.ancestor(
      of: find.text('Kahve'),
      matching: find.byType(SwipeAction),
    );
    expect(row, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(row));
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_played, [_tick], reason: 'the threshold, crossed once');
    await gesture.up();
    await _settle(tester);
    expect(find.text('Kahve'), findsNothing, reason: 'the row is gone');
    // The undo window runs out and the delete goes out: still silent.
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(api.requests, contains('DELETE /transactions/316'));
    expect(_played, [_tick]);
    expect(tester.takeException(), isNull);
  });
  for (final (location, route, body) in [
    ('/finance', 'GET /finance/dashboard', financeDashboardJson),
    ('/journal', 'GET /journal_entries', () => {
          'entries': [journalListItemJson()],
          'meta': const {
            'entries_count': 1,
            'journal_streak': 1,
            'journal_streak_weeks': 1,
            'mood_counts': {
              'great': 0,
              'good': 1,
              'neutral': 0,
              'bad': 0,
              'awful': 0,
            },
            'range': '30d',
          },
        }),
  ]) {
    testWidgets('7. $location: a retry is silent, a pull plays armed once',
        (tester) async {
      final api = FakeApi()..fail(route, 500);
      await _pumpApp(tester, api, location: location);
      final retry = find.text('Tekrar dene');
      expect(retry, findsWidgets);
      await tester.tap(retry.first);
      await _settle(tester);
      expect(_played, isEmpty, reason: 'the retry button');
      // Back up: the pull, past its threshold.
      api.on(route, body());
      await tester.tap(find.text('Tekrar dene').first);
      await _settle(tester);
      expect(find.text('Tekrar dene'), findsNothing);
      _played.clear();
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await _settle(tester, frames: 40);
      expect(_played, [_armed]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('7. account detail: a pull plays armed once', (tester) async {
    await _pumpApp(tester, FakeApi(), location: '/finance/account/1');
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1000,
    );
    await _settle(tester, frames: 40);
    expect(_played, [_armed]);
    expect(tester.takeException(), isNull);
  });
}
