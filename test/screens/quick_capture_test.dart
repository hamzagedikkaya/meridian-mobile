/// Quick capture against the G1 answers (contract G1.5): a confirmation that
/// says what was saved, no ✓ for a line that saved nothing, and refusals that
/// stay in the sheet with their next step.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/quick_capture.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/flows/create_flows.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/quick_capture_sheet.dart';

import '../support/fake_api.dart';

const _post = 'POST /quick_captures';

/// Stands in for the create forms other parts build.
class _Flows extends CreateFlows {
  _Flows({this.onAccount, this.onEvent, this.created});

  final Future<bool> Function(BuildContext context)? onAccount;
  final Future<bool> Function(BuildContext, EventSuggestion)? onEvent;
  final Habit? created;
  final habitNames = <String?>[];

  @override
  Future<bool> Function(BuildContext context)? get account => onAccount;

  @override
  Future<bool> Function(BuildContext, EventSuggestion)? get event => onEvent;

  @override
  Future<Habit?> habit(BuildContext context, {String? name}) async {
    habitNames.add(name);
    return created;
  }
}

Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  CreateFlows flows = const CreateFlows(),
  Locale locale = const Locale('tr'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        createFlowsProvider.overrideWithValue(flows),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: locale,
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showQuickCaptureSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byType(FilledButton).last);
  await tester.pumpAndSettle();
}

Finder _sheet() => find.byType(TextField);

Map<String, dynamic> _refusal(
  String code,
  String text, [
  Map<String, Object?> extra = const {},
]) => {
  'errors': {
    'text': [text],
  },
  'code': code,
  ...extra,
};

Map<String, dynamic> _suggestion(DateTime day, {String? time = '15:00'}) => {
  'saved': false,
  'captured_type': 'event_suggestion',
  'record_id': null,
  'summary': 'yarın 15:00 dişçi',
  'message': 'Bir etkinlik gibi görünüyor — henüz kaydedilmedi.',
  'suggestion': {
    'title': 'dişçi',
    'date': isoDate(day),
    'time': time,
    'start_at': time == null ? null : '${isoDate(day)}T$time:00.000+03:00',
    'all_day': time == null,
    'keyword': 'yarın',
  },
};

void main() {
  setUpAll(initializeDateFormatting);

  group('a saved line closes the sheet and says what was saved', () {
    testWidgets('a todo', (tester) async {
      final api = FakeApi();
      await _open(tester, api);
      await _send(tester, 'süt al');
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi: süt al'), findsOneWidget);
      expect(api.bodiesOf(_post).single, {'text': 'süt al'});
    });

    testWidgets('an expense, with its amount and account currency', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'transaction',
          'record_id': 1237,
          'summary': 'market',
          'message': 'Captured as a transaction.',
          'record': {
            ...transactionJson(id: 1237),
            'amount_cents': 125050,
            'description': 'market',
          },
        }, status: 201);
      await _open(tester, api);
      await _send(tester, '-1.250,50 market');
      expect(
        find.text('Harcama eklendi · −1.250,50 ₺ · market'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Captured'),
        findsNothing,
        reason: 'the server\'s own sentence is not shown',
      );
    });

    testWidgets('an income, in English', (tester) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'transaction',
          'record_id': 1238,
          'summary': 'maaş',
          'record': {
            ...transactionJson(id: 1238),
            'kind': 'income',
            'amount_cents': 150000,
            'description': 'maaş',
          },
        }, status: 201);
      await _open(tester, api, locale: const Locale('en'));
      await _send(tester, '+1500 maaş');
      expect(find.text('Income added · +1,500.00 ₺ · maaş'), findsOneWidget);
    });

    testWidgets('a habit check-in', (tester) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'habit_log',
          'record_id': 1151,
          'summary': 'Su',
          'record': {
            'id': 1151,
            'habit_id': 8,
            'date': '2026-10-04',
            'count': 3,
            'completed': true,
          },
        }, status: 201);
      await _open(tester, api);
      await _send(tester, 'alışkanlık: su');
      expect(find.text('“Su” bugün tamamlandı'), findsOneWidget);
    });

    testWidgets('a kind this app does not know yet still says it was saved', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'reminder',
          'record_id': 3,
          'summary': 'ilaç',
        }, status: 201);
      await _open(tester, api);
      await _send(tester, 'ilaç');
      expect(find.text('Kaydedildi: ilaç'), findsOneWidget);
    });
  });

  group('a line that names a day saves nothing, and the sheet says so', () {
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    testWidgets('no ✓: the sheet stays, with what was read and "save as a '
        'task"', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api);
      await _send(tester, 'yarın 15:00 dişçi');

      expect(_sheet(), findsOneWidget, reason: 'nothing was saved');
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.text('Bir etkinlik gibi görünüyor — henüz kaydedilmedi.'),
        findsOneWidget,
      );
      expect(find.text('dişçi · Yarın · 15:00'), findsOneWidget);
      expect(find.text('Görev olarak kaydet'), findsOneWidget);
      // The event form is offered next to it.
      expect(find.text('Etkinlik olarak ekle'), findsOneWidget);
    });

    testWidgets('without an event form, only "save as a task" is offered', (
      tester,
    ) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api, flows: _Flows());
      await _send(tester, 'yarın 15:00 dişçi');
      expect(find.text('Görev olarak kaydet'), findsOneWidget);
      expect(find.text('Etkinlik olarak ekle'), findsNothing);
    });

    testWidgets('"save as a task" sends the same line with as=todo', (
      tester,
    ) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api);
      await _send(tester, 'yarın 15:00 dişçi');

      api.on(_post, captureTodoJson(title: 'yarın 15:00 dişçi'), status: 201);
      await tester.tap(find.text('Görev olarak kaydet'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf(_post).last, {
        'text': 'yarın 15:00 dişçi',
        'as': 'todo',
      });
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi: yarın 15:00 dişçi'), findsOneWidget);
    });

    testWidgets('"save as a task" that cannot reach the server is retried '
        'as a task', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api);
      await _send(tester, 'yarın 15:00 dişçi');

      api.failNetwork(_post);
      await tester.tap(find.text('Görev olarak kaydet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);

      api.on(_post, captureTodoJson(title: 'yarın 15:00 dişçi'), status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf(_post).last, {
        'text': 'yarın 15:00 dişçi',
        'as': 'todo',
      });
      expect(_sheet(), findsNothing);
    });

    testWidgets('an all-day suggestion says so', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow, time: null));
      await _open(tester, api);
      await _send(tester, 'yarın dişçi');
      expect(find.text('dişçi · Yarın · Tüm gün'), findsOneWidget);
    });

    testWidgets('once there is an event form, "add as an event" opens it '
        'with what was read', (tester) async {
      EventSuggestion? opened;
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(
        tester,
        api,
        flows: _Flows(
          onEvent: (_, suggestion) async {
            opened = suggestion;
            return true;
          },
        ),
      );
      await _send(tester, 'yarın 15:00 dişçi');
      await tester.tap(find.text('Etkinlik olarak ekle'));
      await tester.pumpAndSettle();
      expect(opened!.title, 'dişçi');
      expect(opened!.time, '15:00');
      expect(_sheet(), findsNothing);
    });

    testWidgets('editing the line clears the suggestion', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api);
      await _send(tester, 'yarın 15:00 dişçi');
      await tester.enterText(find.byType(TextField), 'dişçi randevusu al');
      await tester.pump();
      expect(find.text('Görev olarak kaydet'), findsNothing);
    });
  });

  group('a refusal stays in the sheet, with the line kept', () {
    testWidgets('no_account: the message, and once there is an account form, '
        'an action that opens it and then sends the line again', (
      tester,
    ) async {
      var accounts = 0;
      final api = FakeApi()
        ..on(
          _post,
          _refusal('no_account', 'İlk hesabını oluştur'),
          status: 422,
        );
      await _open(
        tester,
        api,
        flows: _Flows(
          onAccount: (_) async {
            accounts++;
            api.on(_post, {
              'saved': true,
              'captured_type': 'transaction',
              'record_id': 1,
              'summary': 'kahve',
              'record': {...transactionJson(id: 1), 'description': 'kahve'},
            }, status: 201);
            return true;
          },
        ),
      );
      await _send(tester, '-250 kahve');

      expect(_sheet(), findsOneWidget);
      expect(
        find.text('Tutarı kaydetmek için önce bir hesap oluşturman gerek'),
        findsOneWidget,
      );
      expect(find.text('-250 kahve'), findsOneWidget, reason: 'kept');

      await tester.tap(find.text('Hesap oluştur'));
      await tester.pumpAndSettle();
      expect(accounts, 1);
      expect(api.bodiesOf(_post), hasLength(2), reason: 'sent again');
      expect(_sheet(), findsNothing);
      expect(find.textContaining('Harcama eklendi'), findsOneWidget);
    });

    testWidgets('no_account opens the account form with a cash account '
        'ready, and the line goes again once it is created',
        (tester) async {
      final api = FakeApi()
        ..on('GET /accounts', {'accounts': const []})
        ..on(
          _post,
          _refusal('no_account', 'Create your first account'),
          status: 422,
        );
      await _open(tester, api);
      await _send(tester, '-250 kahve');
      expect(
        find.text('Tutarı kaydetmek için önce bir hesap oluşturman gerek'),
        findsOneWidget,
      );
      expect(
        find.text('Create your first account'),
        findsNothing,
        reason: 'never the server\'s raw sentence',
      );

      await tester.tap(find.text('Hesap oluştur'));
      await tester.pumpAndSettle();
      // The form, named after its type.
      expect(find.text('Yeni hesap'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nakit'), findsOneWidget);

      api.on(_post, {
        'saved': true,
        'captured_type': 'transaction',
        'record_id': 1,
        'summary': 'kahve',
        'record': {...transactionJson(id: 1), 'description': 'kahve'},
      }, status: 201);
      await tester.tap(find.text('Hesabı oluştur'));
      await tester.pumpAndSettle();

      expect(api.bodiesOf('POST /accounts').single, {
        'name': 'Nakit',
        'account_type': 'cash',
        'currency': 'TRY',
        'initial_balance_cents': 0,
        'color': '#D4A853',
      });
      expect(api.bodiesOf(_post), hasLength(2), reason: 'sent again');
      expect(_sheet(), findsNothing);
      expect(find.textContaining('Harcama eklendi'), findsOneWidget);
    });

    testWidgets('unknown_habit: creates the habit with the typed name, then '
        'logs it for today', (tester) async {
      final created = Habit.fromJson(
        habitJson(id: 8, name: 'Yoga', targetCount: 3),
      );
      final flows = _Flows(created: created);
      final api = FakeApi()
        ..on(
          _post,
          _refusal(
            'unknown_habit',
            "'yoga' alışkanlığı yok. Oluşturulsun mu?",
            {'name': 'yoga'},
          ),
          status: 422,
        );
      await _open(tester, api, flows: flows);
      await _send(tester, 'alışkanlık: yoga');

      expect(find.text('“yoga” adında bir alışkanlık yok'), findsOneWidget);
      await tester.tap(find.text('“yoga” alışkanlığını oluştur'));
      await tester.pumpAndSettle();

      expect(flows.habitNames, ['yoga']);
      expect(api.requests, contains('PUT /habits/8/logs/2026-10-04'));
      expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single, {
        'count': 1,
      });
      expect(_sheet(), findsNothing);
      expect(find.text('“Yoga” işaretlendi'), findsOneWidget);
    });

    testWidgets('unknown_habit, and the form closed without saving: the sheet '
        'stays as it was', (tester) async {
      final flows = _Flows();
      final api = FakeApi()
        ..on(
          _post,
          _refusal('unknown_habit', 'x', {'name': 'yoga'}),
          status: 422,
        );
      await _open(tester, api, flows: flows);
      await _send(tester, 'alışkanlık: yoga');
      await tester.tap(find.text('“yoga” alışkanlığını oluştur'));
      await tester.pumpAndSettle();
      expect(_sheet(), findsOneWidget);
      expect(api.requests.where((r) => r.startsWith('PUT')), isEmpty);
    });

    testWidgets('invalid_amount: why, by reason', (tester) async {
      final api = FakeApi()
        ..on(
          _post,
          _refusal('invalid_amount', 'The amount must be greater than zero.', {
            'reason': 'zero',
          }),
          status: 422,
        );
      await _open(tester, api);
      await _send(tester, '-0 kahve');
      expect(find.text('Tutar sıfırdan büyük olmalı'), findsOneWidget);
      expect(_sheet(), findsOneWidget);
    });

    testWidgets('an empty line is refused in the sheet, without a request', (
      tester,
    ) async {
      final api = FakeApi();
      await _open(tester, api);
      await _send(tester, '   ');
      expect(find.text('Önce bir şey yaz'), findsOneWidget);
      expect(api.requests, isEmpty);
    });

    testWidgets('the server\'s "empty" reads the same', (tester) async {
      final api = FakeApi()
        ..on(_post, _refusal('empty', 'Boş girdi'), status: 422);
      await _open(tester, api);
      await _send(tester, 'habit:');
      expect(find.text('Önce bir şey yaz'), findsOneWidget);
    });

    testWidgets('a title that is too long is worded by the app', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_post, {
          'errors': {
            'title': ['Title is too long (maximum is 200 characters)'],
          },
          'code': 'validation_failed',
          'details': {
            'title': [
              {'error': 'too_long', 'count': 200},
            ],
          },
        }, status: 422);
      await _open(tester, api);
      await _send(tester, 'x' * 250);
      expect(find.text('En fazla 200 karakter olabilir'), findsOneWidget);
    });

    testWidgets('no connection: the line is kept and a retry sends it again', (
      tester,
    ) async {
      final api = FakeApi()..failNetwork(_post);
      await _open(tester, api);
      await _send(tester, 'süt al');
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);
      expect(find.text('süt al'), findsOneWidget);

      api.on(_post, captureTodoJson(), status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi: süt al'), findsOneWidget);
    });
  });

  group('a small phone with the keyboard up: the answer and its next step '
      'stay reachable, and "Ekle" stays above the keyboard', () {
    // 360×640 dp, a 24 dp status bar and a 280 dp keyboard: about 330 dp
    // left for the sheet.
    const keyboard = 280.0;
    const keyboardTop = 640.0 - keyboard;
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    void smallPhone(WidgetTester tester, {double textScale = 1}) {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(top: 48);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 2);
      addTearDown(tester.view.reset);
      if (textScale != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
    }

    /// No overflow; the button is whole above the keyboard, and [shown] —
    /// the answer's action — whole between it and the status bar. With
    /// [partly], [shown] (the line, taller than the room left at 200% text)
    /// need only be on screen there: the sheet scrolls to the rest.
    void expectLaidOut(
      WidgetTester tester,
      Finder shown, {
      bool partly = false,
    }) {
      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      final add = tester.getRect(find.byType(FilledButton).last);
      expect(add.bottom, lessThanOrEqualTo(keyboardTop),
          reason: '"Ekle" is not under the keyboard');
      final rect = tester.getRect(shown);
      if (partly) {
        expect(rect.top, lessThan(add.top));
        expect(rect.bottom, greaterThan(24));
      } else {
        expect(rect.bottom, lessThanOrEqualTo(add.top));
        expect(rect.top, greaterThanOrEqualTo(24));
      }
    }

    for (final locale in const [Locale('tr'), Locale('en')]) {
      for (final withEventForm in [false, true]) {
        testWidgets('an event suggestion ($locale, event form: '
            '$withEventForm): "save as a task" is on screen and works', (
          tester,
        ) async {
          smallPhone(tester);
          final api = FakeApi()..on(_post, _suggestion(tomorrow));
          await _open(
            tester,
            api,
            locale: locale,
            flows: withEventForm
                ? _Flows(onEvent: (_, _) async => true)
                : const CreateFlows(),
          );
          await _send(tester, 'yarın 15:00 dişçi');
          final saveAsTask = find.text(
            locale.languageCode == 'tr' ? 'Görev olarak kaydet' : 'Save as a task',
          );
          expectLaidOut(tester, saveAsTask);

          api.on(_post, captureTodoJson(title: 'yarın 15:00 dişçi'),
              status: 201);
          await tester.tap(saveAsTask);
          await tester.pumpAndSettle();
          expect(api.bodiesOf(_post).last, {
            'text': 'yarın 15:00 dişçi',
            'as': 'todo',
          }, reason: 'the tap reached the action, not "Ekle" under it');
          expect(_sheet(), findsNothing);
        });
      }
    }

    testWidgets('an unknown habit: its "create" action is on screen and '
        'works', (tester) async {
      smallPhone(tester);
      final flows = _Flows();
      final api = FakeApi()
        ..on(
          _post,
          _refusal('unknown_habit', 'x', {'name': 'sabah erkenden yürüyüş'}),
          status: 422,
        );
      await _open(tester, api, flows: flows);
      await _send(tester, 'alışkanlık: sabah erkenden yürüyüş');
      final create = find.text('“sabah erkenden yürüyüş” alışkanlığını oluştur');
      expectLaidOut(tester, create);

      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(flows.habitNames, ['sabah erkenden yürüyüş']);
    });

    testWidgets('at 200% text, the empty sheet', (tester) async {
      smallPhone(tester, textScale: 2);
      await _open(tester, FakeApi());
      expectLaidOut(tester, find.byType(TextField), partly: true);
    });

    testWidgets('at 200% text, a refusal with its next step', (tester) async {
      smallPhone(tester, textScale: 2);
      final api = FakeApi()
        ..on(_post, _refusal('unknown_habit', 'x', {'name': 'yoga'}),
            status: 422);
      await _open(tester, api, flows: _Flows());
      await _send(tester, 'alışkanlık: yoga');
      expectLaidOut(tester, find.text('“yoga” alışkanlığını oluştur'));
    });
  });

  group('a capture that timed out', () {
    testWidgets('after the line went out: it may have been saved, so no '
        'retry is offered and the line is kept', (tester) async {
      final api = FakeApi()..timeOut(_post);
      await _open(tester, api);
      await _send(tester, '-250 kahve');
      expect(
        find.text(
          'Sunucu zamanında yanıt vermedi — kaydedilmiş olabilir. '
          'Yeniden göndermeden önce kontrol et.',
        ),
        findsOneWidget,
      );
      expect(find.text('Tekrar dene'), findsNothing);
      expect(find.text('-250 kahve'), findsOneWidget, reason: 'kept');
      expect(api.bodiesOf(_post), hasLength(1), reason: 'not sent again');
    });

    testWidgets('and in English', (tester) async {
      final api = FakeApi()..timeOut(_post, type: DioExceptionType.sendTimeout);
      await _open(tester, api, locale: const Locale('en'));
      await _send(tester, '-250 coffee');
      expect(
        find.text(
          'The server didn\'t answer in time — it may have been saved. '
          'Check before sending it again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('before it could connect: nothing reached the server, so a '
        'retry is safe', (tester) async {
      final api = FakeApi()
        ..timeOut(_post, type: DioExceptionType.connectionTimeout);
      await _open(tester, api);
      await _send(tester, 'süt al');
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);

      api.on(_post, captureTodoJson(), status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi: süt al'), findsOneWidget);
    });
  });

  testWidgets('the hint teaches the sign money needs', (tester) async {
    await _open(tester, FakeApi());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, contains('-250'));
    expect(field.decoration!.hintText, contains('+1.500'));
    expect(field.decoration!.hintText, contains('alışkanlık:'));
  });
}
