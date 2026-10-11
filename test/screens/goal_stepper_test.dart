/// The goal detail's manual stepper (design-analysis §7.11, WP-12): taps
/// show at once and merge into one `update_progress`, taps during a request
/// go after it, a failure springs back with REJECT, crossing 100 % confirms
/// once, leaving never loses a step — and the detail never shows a spinner.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/widgets/progress_ring.dart';

import '../support/fake_api.dart';

const _progress = 'PATCH /goals/3/update_progress';

/// "x / 100 kitap", as the progress line writes it.
String _line(num current) => '$current / 100 kitap';

Future<GoRouter> _pump(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(1290, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/goals/3'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/goals/:id',
        builder: (_, state) =>
            GoalDetailScreen(goalId: int.parse(state.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(api.dio)],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('open'));
  await _settle(tester);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a number's roll play out: it starts on the frame that builds the
/// new value and comes to rest on the frame after it ends.
Future<void> _rest(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

double _ring(WidgetTester tester) =>
    tester.state<ProgressRingState>(find.byType(ProgressRing)).paintedValue;

void main() {
  setUpAll(initializeDateFormatting);

  /// `HapticFeedback.vibrate` arguments played so far.
  final played = <String?>[];

  setUp(() {
    played.clear();
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        played.add(call.arguments as String?);
      }
      return null;
    });
  });

  tearDown(() {
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('ten quick "+1"s show at once and go as one PATCH with the '
      'value they add up to', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    expect(find.text(_line(40)), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('+1'));
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Every tap is on screen before anything is sent: numbers rolled, the
    // ring on its way.
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump();
    expect(find.text(_line(50)), findsOneWidget);
    expect(find.text('%50'), findsOneWidget);
    expect(_ring(tester), closeTo(0.5, 0.01));
    expect(api.bodiesOf(_progress), isEmpty, reason: 'still within 400 ms');
    expect(played, contains('HapticFeedbackType.selectionClick'));

    // The server's answer, read back after the write.
    api.on('GET /goals/3', {'goal': goalJson(current: 50)});
    await tester.pump(const Duration(milliseconds: 150));
    await _settle(tester);
    expect(api.bodiesOf(_progress), [
      {'current_value': 50},
    ]);
    expect(find.text(_line(50)), findsOneWidget);
  });

  testWidgets('taps while a request is in flight add up and go after it', (
    tester,
  ) async {
    final api = FakeApi()..hold(_progress);
    await _pump(tester, api);

    await tester.tap(find.text('+1'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(api.bodiesOf(_progress), [
      {'current_value': 41},
    ]);

    await tester.tap(find.text('+1'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('+10'));
    await _rest(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.bodiesOf(_progress), hasLength(1), reason: 'one at a time');
    expect(find.text(_line(52)), findsOneWidget);

    api.release(_progress);
    await _settle(tester);
    expect(api.bodiesOf(_progress), [
      {'current_value': 41},
      {'current_value': 52},
    ]);
  });

  testWidgets('a step the server refuses springs back to the last value it '
      'confirmed, with REJECT and "Tekrar dene"', (tester) async {
    final api = FakeApi()..fail(_progress, 500);
    await _pump(tester, api);

    await tester.tap(find.text('+10'));
    await _rest(tester);
    expect(find.text(_line(50)), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.text(_line(40)), findsOneWidget);
    expect(_ring(tester), closeTo(0.4, 0.01));
    expect(played, contains('HapticFeedbackType.errorNotification'));
    expect(find.widgetWithText(SnackBarAction, 'Tekrar dene'), findsOneWidget);

    // "Tekrar dene" sends the refused value again.
    api.on(_progress, {'goal': goalJson(current: 50)});
    await tester.tap(find.widgetWithText(SnackBarAction, 'Tekrar dene'));
    await _settle(tester);
    expect(api.bodiesOf(_progress), [
      {'current_value': 50},
      {'current_value': 50},
    ]);
  });

  testWidgets('crossing 100 % by the steps confirms once', (tester) async {
    final api = FakeApi()..on('GET /goals/3', {'goal': goalJson(current: 95)});
    await _pump(tester, api);
    played.clear();

    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(played, ['HapticFeedbackType.successNotification']);
    await _rest(tester);
    expect(find.text('%100'), findsOneWidget);

    // Down and up again: no second celebration.
    await tester.tap(find.text('−10'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('+10'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      played.where((p) => p == 'HapticFeedbackType.successNotification'),
      hasLength(1),
    );
    await _settle(tester);
  });

  testWidgets('leaving before the wait is over still sends the step', (
    tester,
  ) async {
    final api = FakeApi();
    await _pump(tester, api);
    await tester.tap(find.text('+1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(find.byType(GoalDetailScreen), findsNothing);
    expect(api.bodiesOf(_progress), [
      {'current_value': 41},
    ]);
  });

  testWidgets('nothing below zero: the minus steps stop there', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /goals/3', {'goal': goalJson(current: 4)});
    await _pump(tester, api);
    await tester.tap(find.text('−10'));
    await _rest(tester);
    expect(find.text(_line(0)), findsOneWidget);
    // Disabled at zero.
    await tester.tap(find.text('−1'));
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);
    expect(api.bodiesOf(_progress), [
      {'current_value': 0},
    ]);
  });

  testWidgets('a goal opened without its preview never shows a spinner — the '
      'frame, then its skeleton', (tester) async {
    final api = FakeApi()..hold('GET /goals/3');
    tester.view.physicalSize = const Size(1290, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/goals/3',
      routes: [
        GoRoute(
          path: '/goals/:id',
          builder: (_, state) =>
              GoalDetailScreen(goalId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(api.dio)],
        retry: (_, _) => null,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('tr'),
          supportedLocales: AppL10n.supportedLocales,
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
    }
    api.release('GET /goals/3');
    await _settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_line(40)), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
