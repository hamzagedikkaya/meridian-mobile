/// Quick add (design-analysis §7.3, WP-6) against the G1 answers (contract
/// G1.5): the type chips and the app's guess, each type on its own
/// endpoint, a confirmation that names what was saved with "Düzenle" and
/// "Geri al", no ✓ for a line that saved nothing, and refusals that stay in
/// the sheet with their next step.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/quick_capture.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/flows/create_flows.dart';
import 'package:meridian_mobile/ui/flows/flows.dart';
import 'package:meridian_mobile/ui/screens/finance/transaction_form_screen.dart';
import 'package:meridian_mobile/ui/screens/today/today_screen.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/quick_capture_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';
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

/// The clock of the tests that need a fixed today: Sunday 4 October 2026,
/// `/home`'s `today`.
final _now = DateTime(2026, 10, 4, 12, 30);

/// Pumps a screen with an "open" button and opens quick add from it, as
/// [ctx] (and [day]) would. [watchHome] keeps `/home` loaded behind the
/// sheet, as Today does.
Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  CreateFlows flows = const CreateFlows(),
  Locale locale = const Locale('tr'),
  QuickAddContext ctx = QuickAddContext.today,
  DateTime? day,
  bool watchHome = false,
  List<Override> overrides = const [],
  bool settle = true,
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(api.dio),
        createFlowsProvider.overrideWithValue(flows),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildTheme(brightness),
        locale: locale,
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              if (watchHome) ref.watch(homeProvider);
              return Center(
                child: TextButton(
                  onPressed: () => openQuickAdd(context, ctx: ctx, day: day),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  if (watchHome) await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  if (settle) await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byType(FilledButton).last);
  await tester.pumpAndSettle();
}

Finder _sheet() => find.byType(TextField);

Finder _sheetTitle() => find.text('Hızlı ekle');

/// An event form that is closed without saving; what it was opened with
/// goes to [opened].
_Flows _closedEventForm([List<EventSuggestion>? opened]) => _Flows(
  onEvent: (_, suggestion) async {
    opened?.add(suggestion);
    return false;
  },
);

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

/// `-250 kahve`, saved as an expense on Cüzdan.
final _savedExpense = {
  'saved': true,
  'captured_type': 'transaction',
  'record_id': 1,
  'summary': 'kahve',
  'record': {...transactionJson(id: 1), 'description': 'kahve'},
};

void main() {
  setUpAll(initializeDateFormatting);

  group('a saved line closes the sheet and says what was saved', () {
    testWidgets('a todo: a line that reads as a task is added as one, due '
        'on the day quick add was opened for', (tester) async {
      final api = FakeApi()
        ..on('POST /todos', {
          'todo': {...todoJson(id: 41), 'title': 'süt al'},
        }, status: 201);
      await _open(
        tester,
        api,
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );
      await tester.enterText(find.byType(TextField), 'süt al');
      await tester.pump();
      expect(find.text('Otomatik · Görev'), findsOneWidget);
      expect(find.text('Görev ekle'), findsOneWidget);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi · süt al'), findsOneWidget);
      expect(api.bodiesOf(_post), isEmpty);
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'süt al',
        'priority': 'medium',
        'due_date': '2026-10-04',
      });
    });

    testWidgets('a time without a day word is a task too, as the server '
        'would save it', (tester) async {
      final api = FakeApi();
      await _open(
        tester,
        api,
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );
      await tester.enterText(find.byType(TextField), 'dişçi 15:00');
      await tester.pump();
      expect(find.text('Otomatik · Görev'), findsOneWidget);
      expect(find.text('Görev ekle'), findsOneWidget);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(api.bodiesOf(_post), isEmpty);
      expect(
        (api.bodiesOf('POST /todos').single as Map)['title'],
        'dişçi 15:00',
      );
    });

    testWidgets('an expense, with its amount in the account currency and the '
        'account it went to', (tester) async {
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
        find.text('Harcama eklendi · −₺1.250,50 · Cüzdan'),
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
      expect(find.text('Income added · +₺1,500 · Cüzdan'), findsOneWidget);
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
      await _send(tester, 'alışkanlık: ilaç');
      expect(find.text('Kaydedildi: ilaç'), findsOneWidget);
    });
  });

  group('a line that names a day saves nothing, and the sheet says so', () {
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    testWidgets('no ✓: the event form opens, as the button said, and once '
        'it is closed the sheet stays, with what was read and "save as a '
        'task"', (tester) async {
      final opened = <EventSuggestion>[];
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api, flows: _closedEventForm(opened));
      await tester.enterText(find.byType(TextField), 'yarın 15:00 dişçi');
      await tester.pump();
      expect(find.text('Etkinlik olarak aç'), findsOneWidget);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();

      expect(opened.single.title, 'dişçi');

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
      await _open(tester, api, flows: _closedEventForm());
      await _send(tester, 'yarın 15:00 dişçi');

      api.on(_post, captureTodoJson(title: 'yarın 15:00 dişçi'), status: 201);
      await tester.tap(find.text('Görev olarak kaydet'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf(_post).last, {
        'text': 'yarın 15:00 dişçi',
        'as': 'todo',
      });
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi · yarın 15:00 dişçi'), findsOneWidget);
    });

    testWidgets('"save as a task" that cannot reach the server is retried '
        'as a task', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api, flows: _closedEventForm());
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
      await _open(tester, api, flows: _closedEventForm());
      await _send(tester, 'yarın dişçi');
      expect(find.text('dişçi · Yarın · Tüm gün'), findsOneWidget);
    });

    testWidgets('"Etkinlik olarak aç" opens the event form with what was '
        'read, and saving it closes the sheet', (tester) async {
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
      expect(opened!.title, 'dişçi');
      expect(opened!.time, '15:00');
      expect(_sheet(), findsNothing);
    });

    testWidgets('editing the line clears the suggestion', (tester) async {
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api, flows: _closedEventForm());
      await _send(tester, 'yarın 15:00 dişçi');
      await tester.enterText(find.byType(TextField), 'dişçi randevusu al');
      await tester.pumpAndSettle();
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

      await tester.tap(find.text('Nakit hesabı aç'));
      await tester.pumpAndSettle();
      expect(accounts, 1);
      expect(api.bodiesOf(_post), hasLength(2), reason: 'sent again');
      expect(_sheet(), findsNothing);
      expect(find.textContaining('Harcama eklendi'), findsOneWidget);
    });

    testWidgets('no_account opens the account form with a cash account '
        'ready, and the line goes again once it is created', (tester) async {
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

      await tester.tap(find.text('Nakit hesabı aç'));
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
        ..on('POST /todos', {
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
      await _send(tester, '-250 kahve');
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);
      expect(find.text('-250 kahve'), findsOneWidget);

      api.on(_post, _savedExpense, status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf(_post), hasLength(2));
      expect(_sheet(), findsNothing);
      expect(find.textContaining('Harcama eklendi'), findsOneWidget);
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
      expect(
        add.bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: '"Ekle" is not under the keyboard',
      );
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
            flows: withEventForm ? _closedEventForm() : _Flows(),
          );
          await _send(tester, 'yarın 15:00 dişçi');
          final saveAsTask = find.text(
            locale.languageCode == 'tr'
                ? 'Görev olarak kaydet'
                : 'Save as a task',
          );
          expectLaidOut(tester, saveAsTask);

          api.on(
            _post,
            captureTodoJson(title: 'yarın 15:00 dişçi'),
            status: 201,
          );
          await tester.tap(saveAsTask);
          await tester.pumpAndSettle();
          expect(
            api.bodiesOf(_post).last,
            {'text': 'yarın 15:00 dişçi', 'as': 'todo'},
            reason: 'the tap reached the action, not "Ekle" under it',
          );
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
      final create = find.text(
        '“sabah erkenden yürüyüş” alışkanlığını oluştur',
      );
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
        ..on(
          _post,
          _refusal('unknown_habit', 'x', {'name': 'yoga'}),
          status: 422,
        );
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
      await _send(tester, '-250 kahve');
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);

      api.on(_post, _savedExpense, status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(_sheet(), findsNothing);
      expect(find.textContaining('Harcama eklendi'), findsOneWidget);
    });
  });

  group('the type chips and the guess', () {
    testWidgets('an empty line: "Otomatik" and "Ekle"; the chip and the '
        'button then follow what the line looks like', (tester) async {
      await _open(tester, FakeApi());
      expect(find.text('Hızlı ekle'), findsOneWidget, reason: 'the title');
      expect(find.text('Otomatik'), findsOneWidget);
      expect(find.text('Ekle'), findsOneWidget);

      Future<void> type(String line, String chip, String button) async {
        await tester.enterText(find.byType(TextField), line);
        await tester.pump();
        expect(find.text(chip), findsOneWidget, reason: line);
        expect(find.text(button), findsOneWidget, reason: line);
      }

      await type('-85 kahve', 'Otomatik · Harcama', 'Harcama ekle');
      await type('+1.500 maaş', 'Otomatik · Gelir', 'Gelir ekle');
      await type(
        'yarın 15:00 dişçi',
        'Otomatik · Etkinlik',
        'Etkinlik olarak aç',
      );
      await type(
        'Alışkanlık: su',
        'Otomatik · Alışkanlık',
        'Alışkanlığı işaretle',
      );
      await type('süt al', 'Otomatik · Görev', 'Görev ekle');
      // A time alone is not a day: the server saves it as a task.
      await type('dişçi 15:00', 'Otomatik · Görev', 'Görev ekle');
      await type(
        'pazar 10:00 kahvaltı',
        'Otomatik · Etkinlik',
        'Etkinlik olarak aç',
      );
      // A type picked wins over the guess.
      await tester.tap(find.text('Harcama'));
      await tester.pump();
      expect(find.text('Harcama ekle'), findsOneWidget);
    });

    testWidgets('in English', (tester) async {
      await _open(tester, FakeApi(), locale: const Locale('en'));
      expect(find.text('Quick add'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '-85 coffee');
      await tester.pump();
      expect(find.text('Auto · Expense'), findsOneWidget);
      expect(find.text('Add expense'), findsOneWidget);
    });

    testWidgets('examples under an empty line write themselves in, and go '
        'once there is text', (tester) async {
      await _open(tester, FakeApi());
      for (final example in const [
        '−85 kahve',
        '+1.500 maaş',
        'yarın 15:00 dişçi',
        'alışkanlık: su',
        'süt al',
      ]) {
        expect(find.text(example), findsOneWidget);
      }
      await tester.tap(find.text('−85 kahve'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '−85 kahve',
      );
      expect(find.text('+1.500 maaş'), findsNothing);
      expect(find.text('Otomatik · Harcama'), findsOneWidget);
    });

    testWidgets('the keyboard is up in the sheet\'s first frame', (
      tester,
    ) async {
      await _open(tester, FakeApi(), settle: false);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('each type goes to its own endpoint', () {
    final fixedClock = [clockProvider.overrideWithValue(() => _now)];

    testWidgets('"Görev" on Today: POST /todos, due today; the snackbar '
        'offers "Düzenle" and "Geri al"', (tester) async {
      final api = FakeApi()
        ..on('POST /todos', {
          'todo': {...todoJson(id: 41), 'title': 'süt al'},
        }, status: 201)
        ..on('DELETE /todos/41', null, status: 204);
      await _open(tester, api, overrides: fixedClock);
      await tester.tap(find.text('Görev'));
      await tester.pump();
      await _send(tester, 'süt al');

      expect(api.bodiesOf('POST /todos').single, {
        'title': 'süt al',
        'priority': 'medium',
        'due_date': '2026-10-04',
      });
      expect(api.bodiesOf(_post), isEmpty);
      expect(_sheet(), findsNothing);
      expect(find.text('Görev eklendi · süt al'), findsOneWidget);
      expect(find.text('Düzenle'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(api.requests, contains('DELETE /todos/41'));
    });

    testWidgets('"Görev" from Agenda: no due date (the inbox); from a held '
        'day heading: that day', (tester) async {
      final api = FakeApi();
      await _open(tester, api, ctx: QuickAddContext.agenda);
      await tester.tap(find.text('Görev'));
      await tester.pump();
      await _send(tester, 'süt al');
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'süt al',
        'priority': 'medium',
      });

      final dayApi = FakeApi();
      await _open(
        tester,
        dayApi,
        ctx: QuickAddContext.agenda,
        day: DateTime(2026, 10, 9),
      );
      await tester.tap(find.text('Görev'));
      await tester.pump();
      await _send(tester, 'süt al');
      expect(
        (dayApi.bodiesOf('POST /todos').single as Map)['due_date'],
        '2026-10-09',
      );
    });

    testWidgets('"Otomatik" on a task line from Agenda: no due date; from a '
        'held day heading: that day', (tester) async {
      final api = FakeApi();
      await _open(tester, api, ctx: QuickAddContext.agenda);
      await _send(tester, 'süt al');
      expect(api.bodiesOf(_post), isEmpty);
      expect(api.bodiesOf('POST /todos').single, {
        'title': 'süt al',
        'priority': 'medium',
      });

      final dayApi = FakeApi();
      await _open(
        tester,
        dayApi,
        ctx: QuickAddContext.agenda,
        day: DateTime(2026, 10, 9),
      );
      await _send(tester, 'süt al');
      expect(dayApi.bodiesOf(_post), isEmpty);
      expect(
        (dayApi.bodiesOf('POST /todos').single as Map)['due_date'],
        '2026-10-09',
      );
    });

    testWidgets('"Görev" that cannot reach the server keeps the line, and a '
        'retry sends the task again', (tester) async {
      final api = FakeApi()..failNetwork('POST /todos');
      await _open(tester, api, overrides: fixedClock);
      await tester.tap(find.text('Görev'));
      await tester.pump();
      await _send(tester, 'süt al');
      expect(find.textContaining('Sunucuya ulaşılamıyor'), findsOneWidget);
      expect(find.text('süt al'), findsOneWidget, reason: 'kept');

      api.on('POST /todos', {
        'todo': {...todoJson(id: 41), 'title': 'süt al'},
      }, status: 201);
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf('POST /todos'), hasLength(2));
      expect(_sheet(), findsNothing);
    });

    for (final (chip, kind) in const [
      ('Harcama', 'expense'),
      ('Gelir', 'income'),
    ]) {
      testWidgets('"$chip": the sheet closes and the transaction form opens '
          'with the amount and the rest of the line', (tester) async {
        final api = FakeApi();
        await _open(tester, api);
        await tester.tap(find.text(chip));
        await tester.pump();
        await _send(tester, 'kahve 1.250,50');

        expect(api.requests.where((r) => r.startsWith('POST')), isEmpty);
        expect(_sheetTitle(), findsNothing);
        final form = tester.widget<TransactionFormScreen>(
          find.byType(TransactionFormScreen),
        );
        expect(form.initialKind, kind);
        expect(form.initialAmountCents, 125050);
        expect(form.initialDescription, 'kahve');
        expect(form.initialAccountId, 1, reason: 'the only account');
      });
    }

    testWidgets('"Harcama" with gram gold last used: the amount in its '
        'units, and the form starts on it', (tester) async {
      SharedPreferences.setMockInitialValues({PrefKeys.lastAccountId: 2});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            accountJson(),
            accountJson(id: 2, name: 'Altın', currency: 'GAU', subunit: 1),
          ],
        });
      await _open(
        tester,
        api,
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      await tester.tap(find.text('Harcama'));
      await tester.pump();
      await _send(tester, '85 kahve');

      final form = tester.widget<TransactionFormScreen>(
        find.byType(TransactionFormScreen),
      );
      expect(form.initialAccountId, 2);
      expect(form.initialAmountCents, 85, reason: '85 gr, not 8.500');
      expect(form.initialDescription, 'kahve');
    });

    testWidgets('"Harcama" with an archived account last used and two '
        'active ones: no account is picked, and the amount reads as typed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({PrefKeys.lastAccountId: 3});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeApi()
        ..on('GET /accounts', {
          'accounts': [
            accountJson(),
            accountJson(id: 2, name: 'Altın', currency: 'GAU', subunit: 1),
            accountJson(id: 3, name: 'Eski', archived: true),
          ],
        });
      await _open(
        tester,
        api,
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      await tester.tap(find.text('Harcama'));
      await tester.pump();
      await _send(tester, '85 kahve');

      final form = tester.widget<TransactionFormScreen>(
        find.byType(TransactionFormScreen),
      );
      expect(form.initialAccountId, isNull);
      expect(form.initialAmountCents, 8500);
    });

    testWidgets('"Harcama" while the accounts cannot load: the amount is '
        'left out rather than read in the wrong currency', (tester) async {
      final api = FakeApi()..on('GET /accounts', {'error': 'x'}, status: 500);
      await _open(tester, api);
      await tester.tap(find.text('Harcama'));
      await tester.pump();
      await _send(tester, '85 kahve');

      final form = tester.widget<TransactionFormScreen>(
        find.byType(TransactionFormScreen),
      );
      expect(form.initialAccountId, isNull);
      expect(form.initialAmountCents, isNull);
      expect(form.initialDescription, 'kahve');
    });

    testWidgets('"Etkinlik": the event form, titled with the line, on the '
        'day; nothing is sent', (tester) async {
      final opened = <EventSuggestion>[];
      final api = FakeApi();
      await _open(
        tester,
        api,
        flows: _closedEventForm(opened),
        ctx: QuickAddContext.agenda,
        day: DateTime(2026, 10, 9),
      );
      await tester.tap(find.text('Etkinlik'));
      await tester.pump();
      expect(find.text('Etkinlik olarak aç'), findsOneWidget);
      await _send(tester, 'dişçi');
      expect(opened.single.title, 'dişçi');
      expect(opened.single.date, DateTime(2026, 10, 9));
      expect(api.requests.where((r) => r.startsWith('POST')), isEmpty);
      expect(_sheet(), findsOneWidget, reason: 'the form was closed');
    });

    testWidgets('"Etkinlik" on a line that names a day: the server reads its '
        'day and time, and the form opens with them', (tester) async {
      final tomorrow = DateTime(2026, 10, 5);
      final opened = <EventSuggestion>[];
      final api = FakeApi()..on(_post, _suggestion(tomorrow));
      await _open(tester, api, flows: _closedEventForm(opened));
      await tester.tap(find.text('Etkinlik'));
      await tester.pump();
      await _send(tester, 'yarın 15:00 dişçi');
      expect(api.bodiesOf(_post).single, {'text': 'yarın 15:00 dişçi'});
      expect(opened.single.title, 'dişçi');
      expect(opened.single.date, tomorrow);
      expect(opened.single.time, '15:00');
      expect(find.byType(SnackBar), findsNothing, reason: 'nothing saved');
    });

    testWidgets('"Alışkanlık": today\'s habits; a tap logs one, closes the '
        'sheet, and "Geri al" puts the count back', (tester) async {
      final api = FakeApi();
      await _open(tester, api, watchHome: true);
      await tester.tap(find.text('Alışkanlık'));
      await tester.pump();
      await tester.tap(find.text('Alışkanlığı işaretle'));
      await tester.pumpAndSettle();

      expect(find.text('Hangi alışkanlık?'), findsOneWidget);
      expect(find.text('Koşu'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget, reason: 'Su, at 1 of 3');

      await tester.tap(find.text('Su'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single, {
        'count': 2,
      });
      expect(find.text('Hangi alışkanlık?'), findsNothing);
      expect(find.text('“Su” işaretlendi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').last, {'count': 1});
    });

    testWidgets('the habit step goes back to the line, which is kept', (
      tester,
    ) async {
      await _open(tester, FakeApi(), watchHome: true);
      await tester.enterText(find.byType(TextField), 'su');
      await tester.tap(find.text('Alışkanlık'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      // Su, named by the line, comes first.
      expect(
        tester.getTopLeft(find.text('Su')).dy,
        lessThan(tester.getTopLeft(find.text('Koşu')).dy),
      );
      await tester.tap(find.byTooltip('Geri dön'));
      await tester.pumpAndSettle();
      expect(find.text('su'), findsOneWidget);
    });

    testWidgets('back from the habit step before its transition ends: the '
        'line leaving and the line coming back each keep their examples', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await _open(tester, FakeApi(), watchHome: true);
      await tester.tap(find.text('Alışkanlık'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byTooltip('Geri dön'));
      await tester.pump();
      // Both lines are in the tree, whole: one answer key each, none taken
      // from the other.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('−85 kahve'), findsNWidgets(2));
      // Frame by frame through the rest of both transitions, the keyboard
      // going down meanwhile: both lines lay out again.
      for (var i = 0; i < 30; i++) {
        tester.view.viewInsets = FakeViewPadding(bottom: 600.0 - i * 20);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame $i');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Hangi alışkanlık?'), findsNothing);
      expect(find.text('−85 kahve'), findsOneWidget);
    });
  });

  group('the result names what was saved, with "Düzenle" and "Geri al"', () {
    testWidgets('a todo: "Geri al" deletes it, "Düzenle" opens it', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('POST /todos', {
          'todo': {...todoJson(id: 40), 'title': 'süt al'},
        }, status: 201)
        ..on('DELETE /todos/40', null, status: 204);
      await _open(tester, api);
      await _send(tester, 'süt al');
      expect(find.text('Görev eklendi · süt al'), findsOneWidget);

      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.text('Görevi düzenle'), findsOneWidget);
      expect(api.requests, isNot(contains('DELETE /todos/40')));
    });

    testWidgets('an expense: "Geri al" deletes the transaction', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'transaction',
          'record_id': 1237,
          'summary': 'kahve',
          'record': {
            ...transactionJson(id: 1237),
            'amount_cents': 8500,
            'description': 'kahve',
          },
        }, status: 201)
        ..on('DELETE /transactions/1237', null, status: 204);
      await _open(tester, api);
      await _send(tester, '−85 kahve');
      expect(find.text('Harcama eklendi · −₺85 · Cüzdan'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(api.requests, contains('DELETE /transactions/1237'));
    });

    testWidgets('an expense: "Düzenle" opens the transaction in its form', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(_post, {
          'saved': true,
          'captured_type': 'transaction',
          'record_id': 1237,
          'summary': 'kahve',
          'record': {...transactionJson(id: 1237), 'description': 'kahve'},
        }, status: 201);
      await _open(tester, api);
      await _send(tester, '-138,74 kahve');
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      final form = tester.widget<TransactionFormScreen>(
        find.byType(TransactionFormScreen),
      );
      expect(form.existing!.id, 1237);
    });

    testWidgets('a habit check-in: "Geri al" sets the day back to what it '
        'was', (tester) async {
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
            'count': 2,
            'completed': false,
          },
        }, status: 201);
      await _open(tester, api, watchHome: true);
      await _send(tester, 'alışkanlık: su');
      expect(find.text('“Su” işaretlendi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single, {
        'count': 1,
      });
    });
  });

  for (final chip in [true, false]) {
    testWidgets('${chip ? '"Görev"' : '"Otomatik"'} on Today: the task shows '
        'on Today\'s card', (tester) async {
      final api = FakeApi()
        ..on('POST /todos', {
          'todo': {...todoJson(id: 41), 'title': 'süt al', 'due_time': null},
        }, status: 201);
      await pumpWithRoutes(tester, api, home: const TodayScreen());
      expect(find.text('süt al'), findsNothing);

      openQuickAdd(tester.element(find.byType(TodayScreen)));
      await settleFrames(tester);
      if (chip) {
        await tester.tap(find.text('Görev'));
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), 'süt al');
      await tester.pump();
      // What /home lists once the task is saved.
      api.on(
        'GET /home',
        homeJson(
          todos: [
            todoJson(),
            {...todoJson(id: 41), 'title': 'süt al', 'due_time': null},
          ],
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Görev ekle'));
      await settleFrames(tester);

      expect(
        (api.bodiesOf('POST /todos').single as Map)['due_date'],
        '2026-10-04',
      );
      expect(
        find.descendant(
          of: find.byType(TodayScreen),
          matching: find.text('süt al'),
        ),
        findsOneWidget,
      );
    });
  }

  // Moved here from events_test.dart (WP-6 owns quick add): with the real
  // event form.
  testWidgets('"Etkinlik olarak aç" opens the real event form with the '
      'suggestion, and saving it closes both', (tester) async {
    final api = FakeApi()
      ..on('POST /quick_captures', {
        'saved': false,
        'captured_type': 'event_suggestion',
        'record_id': null,
        'summary': 'yarın 15:00 dişçi',
        'message': 'x',
        'suggestion': {
          'title': 'dişçi',
          'date': '2026-10-05',
          'time': '15:00',
          'start_at': '2026-10-05T15:00:00.000+03:00',
          'all_day': false,
          'keyword': 'yarın',
        },
      });
    await pumpWithRoutes(
      tester,
      api,
      home: opener((context) => showQuickCaptureSheet(context)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'yarın 15:00 dişçi');
    await tester.pump();
    await tester.tap(find.text('Etkinlik olarak aç'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni etkinlik'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'dişçi'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);

    await tester.tap(find.text('Kaydet'));
    await settleFrames(tester);
    expect(api.bodiesOf('POST /events').single, {
      'title': 'dişçi',
      'start_at': '2026-10-05T15:00',
      'end_at': '2026-10-05T16:00',
      'all_day': false,
      'color': recordSwatches.first,
      'event_type': 'personal',
    });
    await tester.pumpAndSettle();
    expect(find.text('Yeni etkinlik'), findsNothing);
    expect(find.text('Hızlı ekle'), findsNothing, reason: 'the sheet too');
  });

  group('accessibility', () {
    testWidgets('every control is a labelled 48 dp target — the line, the '
        'habit step', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, FakeApi(), watchHome: true);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('Alışkanlık'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('text contrast ($brightness): the empty line, a refusal, '
          'the habit step', (tester) async {
        final handle = tester.ensureSemantics();
        final api = FakeApi()
          ..on(
            _post,
            _refusal('no_account', 'İlk hesabını oluştur'),
            status: 422,
          );
        await _open(
          tester,
          api,
          watchHome: true,
          brightness: brightness,
          flows: _Flows(onAccount: (_) async => false),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await _send(tester, '-85 kahve');
        expect(find.text('Nakit hesabı aç'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(find.text('Alışkanlık'));
        await tester.pump();
        await tester.tap(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        expect(find.text('Hangi alışkanlık?'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('reduced motion: the answer is there in one frame', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _open(tester, FakeApi());
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      final message = find.text('Önce bir şey yaz');
      expect(message, findsOneWidget);
      for (final fade in tester.widgetList<FadeTransition>(
        find.ancestor(of: message, matching: find.byType(FadeTransition)),
      )) {
        expect(fade.opacity.value, 1);
      }
    });
  });
}
