/// Managing a goal from its screen (contract G4): editing without losing its
/// link, linking and relinking, the server's status rules (abandon with
/// undo, reopen — with a higher target when it reached its own — and mark
/// achieved), and delete with undo.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/flows/flows.dart' as flows;
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_kind_tile.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _goal({
  String type = 'custom',
  String status = 'active',
  num current = 40,
  num target = 100,
  String source = 'manual',
  Map<String, dynamic>? related,
}) => {
  ...goalJson(current: current),
  'target_type': type,
  'status': status,
  'target_value': target,
  'progress_percent': (current * 100 / target).clamp(0, 100),
  'progress_source': source,
  'related': related,
};

const _account = {
  'type': 'Account',
  'id': 1,
  'name': 'Cüzdan',
  'balance_cents': 125000,
  'currency': 'TRY',
  'subunit_to_unit': 100,
};

Future<void> _pump(WidgetTester tester, FakeApi api) async {
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
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
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
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Diğer işlemler'));
  await _settle(tester);
  await tester.tap(
    find.descendant(of: find.byType(ListTile), matching: find.text(item)),
  );
  await _settle(tester);
}

/// Types [digits] on the open keypad sheet ("." is the decimal key, which
/// shows "," in Turkish).
Future<void> _type(WidgetTester tester, String digits) async {
  for (final ch in digits.split('')) {
    final key = find.descendant(
      of: find.byType(AmountKeypad),
      matching: find.text(ch == '.' ? ',' : ch),
    );
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pump();
  }
}

/// Clears the keypad sheet's amount (a long press on ⌫).
Future<void> _clear(WidgetTester tester) async {
  await tester.longPress(find.byIcon(Icons.backspace_outlined));
  await tester.pump();
}

/// The keypad sheet's button.
Finder _sheetButton(String label) => find.widgetWithText(PrimaryButton, label);

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('edit: every field prefilled, only the change sent — the '
      'account it tracks stays linked', (tester) async {
    final api = FakeApi()
      ..on('GET /goals/3', {
        'goal': _goal(type: 'financial', source: 'account', related: _account),
      });
    await _pump(tester, api);

    await tester.tap(find.byTooltip('Düzenle'));
    await _settle(tester);
    expect(find.byType(GoalFormScreen), findsOneWidget);
    expect(find.text('Hedefi düzenle'), findsOneWidget);
    expect(find.text('Cüzdan'), findsOneWidget, reason: 'its link, shown');

    await tester.enterText(
      find.widgetWithText(TextField, 'Hedef adı'),
      'Tatil fonu',
    );
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'name': 'Tatil fonu'},
    ]);
    expect(find.byType(GoalFormScreen), findsNothing);
  });

  testWidgets('a habit goal without a habit says so, and links one from its '
      'screen', (tester) async {
    final api = FakeApi()..on('GET /goals/3', {'goal': _goal(type: 'habit')});
    await _pump(tester, api);
    expect(find.textContaining('Bağlı alışkanlık yok'), findsOneWidget);
    // Logged by hand meanwhile.
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.text('Alışkanlık bağla'));
    await _settle(tester);
    await tester.tap(find.text('Koşu'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'related': 'Habit-7'},
    ]);
    expect(find.text('“Koşu” bağlandı'), findsOneWidget);
  });

  testWidgets('a financial goal without an account counts total income — '
      'never called a balance — and offers to link one', (tester) async {
    final api = FakeApi()
      ..on('GET /goals/3', {
        'goal': _goal(type: 'financial', source: 'income'),
      });
    await _pump(tester, api);
    expect(find.text('Toplam gelir'), findsOneWidget);
    expect(find.text('Güncel bakiye'), findsNothing);
    expect(find.text('Hesap bağla'), findsOneWidget);
    expect(find.text('+1'), findsNothing, reason: 'progress is computed');
  });

  testWidgets('abandon: at once, with undo — which reopens it', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    await _menu(tester, 'Bırak');
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'abandoned'},
    ]);
    expect(find.text('Hedef bırakıldı'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3').last, {'status': 'active'});
  });

  testWidgets('reopen: a goal past its target asks for a higher one first', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /goals/3', {'goal': _goal(status: 'achieved', current: 120)});
    await _pump(tester, api);
    expect(find.text('Başarıldı'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Yeniden aç'));
    await _settle(tester);
    expect(find.text('Hedefi yeniden aç'), findsOneWidget);

    // On the keypad, never the system keyboard.
    expect(find.byType(AmountKeypad), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Not above the progress: said under the amount, nothing sent.
    await _type(tester, '110');
    await tester.tap(_sheetButton('Yeniden aç'));
    await _settle(tester);
    expect(find.textContaining('mevcut ilerlemeden'), findsOneWidget);
    expect(api.bodiesOf('PATCH /goals/3'), isEmpty);

    await _clear(tester);
    await _type(tester, '150');
    await tester.tap(_sheetButton('Yeniden aç'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'active', 'target_value': 150},
    ]);
    expect(find.text('Hedef yeniden açıldı'), findsOneWidget);
  });

  testWidgets('reopen: an abandoned goal below its target reopens at once', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /goals/3', {'goal': _goal(status: 'abandoned')});
    await _pump(tester, api);
    await _menu(tester, 'Yeniden aç');
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'active'},
    ]);
  });

  testWidgets('reopen refused because the progress reached the target '
      'elsewhere: the goal is fetched again and the higher-target sheet asks, '
      'from the progress the server gave', (tester) async {
    var refused = false;
    final api = FakeApi()
      ..on('GET /goals/3', {'goal': _goal(status: 'abandoned')})
      ..onRequest('PATCH /goals/3', (request) {
        if (refused) {
          return {'goal': _goal(status: 'active', current: 120, target: 150)};
        }
        refused = true;
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: request,
            statusCode: 422,
            data: {
              'errors': {
                'status': ['x'],
              },
              'code': 'target_reached',
              'current_value': 120.0,
              'target_value': 100.0,
              'progress_source': 'account',
            },
          ),
        );
      });
    await _pump(tester, api);
    api.clearLog();
    await _menu(tester, 'Yeniden aç');
    expect(api.gets, contains('/goals/3'), reason: 'the stale goal refetched');
    expect(find.text('Hedefi yeniden aç'), findsOneWidget);
    expect(find.textContaining('120'), findsWidgets);
    expect(find.textContaining('Hedef değere zaten ulaşıldı'), findsNothing);

    await _type(tester, '150');
    await tester.tap(_sheetButton('Yeniden aç'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'active'},
      {'status': 'active', 'target_value': 150},
    ]);
  });

  testWidgets('the server\'s status refusal is worded, and the goal is '
      'fetched again', (tester) async {
    final api = FakeApi()
      ..on('PATCH /goals/3', {
        'errors': {
          'status': ['x'],
        },
        'code': 'target_not_reached',
        'current_value': 40.0,
        'target_value': 100.0,
        'progress_source': 'account',
      }, status: 422);
    await _pump(tester, api);
    api.clearLog();
    await tester.tap(find.text('Tamamlandı olarak işaretle'));
    await _settle(tester);
    expect(find.text('Hedef değere henüz ulaşılmadı'), findsOneWidget);
    expect(api.gets, contains('/goals/3'));
    // The value shown at once is taken back.
    expect(find.text('40 / 100\u00A0kitap'), findsOneWidget);
  });

  testWidgets('the higher-target keypad scrolls on a small screen with large '
      'text, its button always in reach', (tester) async {
    final api = FakeApi()
      ..on('GET /goals/3', {'goal': _goal(status: 'achieved', current: 120)});
    await _pump(tester, api);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Yeniden aç'));
    await _settle(tester);
    expect(find.text('Hedefi yeniden aç'), findsOneWidget);

    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    await _type(tester, '150');
    final button = _sheetButton('Yeniden aç');
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(568));
    await tester.tap(button);
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'active', 'target_value': 150},
    ]);
  });

  testWidgets('"Değer gir" opens the keypad: decimals with the language\'s '
      'mark, sent at once', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    await tester.tap(find.text('Değer gir'));
    await _settle(tester);
    expect(find.byType(AmountKeypad), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'no system keyboard');

    await _clear(tester);
    await _type(tester, '7.5');
    expect(find.text('7,5\u00A0kitap'), findsOneWidget);
    await tester.tap(_sheetButton('Tamam'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3/update_progress'), [
      {'current_value': 7.5},
    ]);
  });

  testWidgets('mark achieved: only a goal logged by hand, which is set to its '
      'target', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    // In the goal's own card, not the menu.
    await tester.tap(find.byTooltip('Diğer işlemler'));
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Tamamlandı olarak işaretle'),
      ),
      findsNothing,
    );
    await tester.tapAt(Offset.zero);
    await _settle(tester);
    await tester.tap(find.text('Tamamlandı olarak işaretle'));
    await _settle(tester);
    expect(api.bodiesOf('PATCH /goals/3'), [
      {'status': 'achieved', 'current_value': 100.0},
    ]);
  });

  testWidgets('a linked goal cannot be marked achieved by hand', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /goals/3', {
        'goal': _goal(type: 'financial', source: 'account', related: _account),
      });
    await _pump(tester, api);
    await tester.tap(find.byTooltip('Diğer işlemler'));
    await _settle(tester);
    expect(find.text('Tamamlandı olarak işaretle'), findsNothing);
    expect(find.text('Bırak'), findsOneWidget);
  });

  testWidgets('delete: back to the list without it, with undo; the delete '
      'goes when the snackbar does', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    await _menu(tester, 'Hedefi sil');
    expect(find.byType(GoalDetailScreen), findsNothing);
    expect(find.text('“Kitap” silindi'), findsOneWidget);
    expect(api.requests, isNot(contains('DELETE /goals/3')));

    await _settle(tester);
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(api.requests, contains('DELETE /goals/3'));
  });

  testWidgets('delete undone: nothing is sent', (tester) async {
    final api = FakeApi();
    await _pump(tester, api);
    await _menu(tester, 'Hedefi sil');
    await tester.tap(find.text('Geri al'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(api.requests, isNot(contains('DELETE /goals/3')));
  });

  testWidgets('the Goals grid drops a goal being deleted at once, and opens '
      'achieved and abandoned goals', (tester) async {
    final api = FakeApi()
      ..on('GET /goals', {
        'active': [goalJson()],
        'achieved': [
          {
            ..._goal(status: 'achieved', current: 100),
            'id': 5,
            'name': 'Bitti',
          },
        ],
        'abandoned': const [],
      })
      ..on('GET /goals/5', {
        'goal': {
          ..._goal(status: 'achieved', current: 100),
          'id': 5,
          'name': 'Bitti',
        },
      });
    await _pump(tester, api);
    await _menu(tester, 'Hedefi sil');
    GoRouter.of(tester.element(find.text('open'))).go('/goals');
    await _settle(tester);
    expect(find.text('Kitap'), findsNothing, reason: 'being deleted');

    await tester.tap(find.textContaining('Başarılanlar'));
    await _settle(tester);
    await tester.tap(find.text('Bitti'));
    await _settle(tester);
    expect(find.byType(GoalDetailScreen), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Yeniden aç'), findsOneWidget);
  });

  testWidgets('a deadline-less goal shows no days left, an overdue one how '
      'long ago', (tester) async {
    final api = FakeApi()
      ..on('GET /goals/3', {
        'goal': {
          ..._goal(),
          'deadline': '2026-09-01',
          'days_remaining': -33,
          'deadline_badge': {'state': 'overdue', 'days': 33},
        },
      });
    await _pump(tester, api);
    expect(find.text('33 gün geçti'), findsOneWidget);
  });

  testWidgets('a habit\'s "set a goal for it" opens the form as a habit goal '
      'already linked to that habit', (tester) async {
    tester.view.physicalSize = const Size(1290, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(api.dio)],
        retry: (_, _) => null,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('tr'),
          supportedLocales: AppL10n.supportedLocales,
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => flows.openGoalForm(context, habitId: 7),
                  child: const Text('set a goal'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('set a goal'));
    await _settle(tester);

    final form = tester.widget<GoalFormScreen>(find.byType(GoalFormScreen));
    expect(form.initialHabitId, 7);
    // The habit kind chosen, the habit named on the link row, and no
    // starting value: the habit counts the progress.
    final chosen = tester
        .widgetList<GoalKindTile>(find.byType(GoalKindTile))
        .where((t) => t.selected ?? false)
        .map((t) => t.type);
    expect(chosen, ['habit']);
    expect(find.text('Koşu'), findsOneWidget);
    expect(find.text('Bir alışkanlık bağlı değil'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '30 gün koş');
    await tester.tap(find.text('Hedef değer'));
    await _settle(tester);
    await _clear(tester);
    await _type(tester, '30');
    await tester.tap(_sheetButton('Tamam'));
    await _settle(tester);
    await tester.tap(find.text('Hedef oluştur'));
    await _settle(tester);

    final body = api.bodiesOf('POST /goals').single as Map;
    expect(body['target_type'], 'habit');
    expect(body['related'], 'Habit-7');
    expect(body['target_value'], 30);
    expect(body.containsKey('current_value'), isFalse);
  });
}
