/// The Habits tab against `PUT /habits/:id/logs/:date`: every tap sends the
/// count it shows, a weekly or monthly habit's day is done or not, and the
/// habit form takes a name from quick capture and words the server's
/// refusals under the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_log_sheet.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/counter_pill.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';

import '../support/fake_api.dart';

Widget _app(FakeApi api, Widget home) => ProviderScope(
  overrides: [dioProvider.overrideWithValue(api.dio)],
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
    home: home,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 3900);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Koşu (7, daily, once), Su (8, daily, 3 a day, at 1) and Kitap (11,
/// three days a week, not yet today).
Map<String, dynamic> _habits() => {
  'habits': [
    habitJson(),
    habitJson(id: 8, name: 'Su', targetCount: 3, count: 1),
    {
      ...habitJson(id: 11, name: 'Kitap', targetCount: 3),
      'frequency': 'weekly',
      'period': {
        'range_start': '2026-09-28',
        'range_end': '2026-10-04',
        'completed_count': 1,
        'complete': false,
      },
    },
  ],
  'meta': habitsMeta(totalActive: 3),
};

Finder _in(int id, Type type) => find.descendant(
  of: find.byKey(ValueKey('habit-$id')),
  matching: find.byType(type),
);

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('a daily counter sends the count it steps to, up and down', (
    tester,
  ) async {
    _tallPhone(tester);
    final api = FakeApi()..on('GET /habits', _habits());
    await tester.pumpWidget(_app(api, const HabitsScreen()));
    await _settle(tester);

    expect(_in(8, CounterPill), findsOneWidget);
    // The body counts one more; the + only shows it.
    await tester.tap(
      find.descendant(
        of: _in(8, CounterPill),
        matching: find.byIcon(Icons.add_rounded),
      ),
    );
    await _settle(tester);
    expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single, {'count': 2});

    await tester.tap(
      find.descendant(
        of: _in(8, CounterPill),
        matching: find.byIcon(Icons.remove_rounded),
      ),
    );
    await _settle(tester);
    expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').last, {'count': 1});
    await tester.pumpAndSettle();
  });

  testWidgets('a weekly habit counts days: its day is a ring, a tap sends its '
      'target, and the week\'s pill moves', (tester) async {
    _tallPhone(tester);
    const log = 'PUT /habits/11/logs/2026-10-04';
    final api = FakeApi()
      ..on('GET /habits', _habits())
      ..hold(log)
      ..on(log, {
        'habit': {
          ...habitJson(
            id: 11,
            name: 'Kitap',
            targetCount: 3,
            completed: true,
            count: 3,
          ),
          'frequency': 'weekly',
          'period': {
            'range_start': '2026-09-28',
            'range_end': '2026-10-04',
            'completed_count': 2,
            'complete': false,
          },
        },
        'meta': habitsMeta(totalActive: 3, completedToday: 1),
      });
    await tester.pumpWidget(_app(api, const HabitsScreen()));
    await _settle(tester);

    expect(
      _in(11, CounterPill),
      findsNothing,
      reason: 'not 0/3 for the day: the 3 is days a week',
    );
    expect(_in(11, CheckPop), findsOneWidget);
    expect(find.text('Bu hafta 1/3'), findsOneWidget);

    await tester.tap(_in(11, CheckPop));
    await tester.pump();
    expect(tester.widget<CheckPop>(_in(11, CheckPop)).checked, isTrue);
    expect(find.text('Bu hafta 2/3'), findsOneWidget, reason: 'at once');

    api.release(log);
    await _settle(tester);
    expect(api.bodiesOf(log).single, {'count': 3});
    expect(find.text('Bu hafta 2/3'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the counter\'s − and its body each answer a 48 dp touch, '
      'while the pill is drawn 40 dp tall', (tester) async {
    _tallPhone(tester);
    final api = FakeApi()..on('GET /habits', _habits());
    await tester.pumpWidget(_app(api, const HabitsScreen()));
    await _settle(tester);

    Rect target(IconData icon) => tester.getRect(
      find
          .ancestor(
            of: find.descendant(
              of: _in(8, CounterPill),
              matching: find.byIcon(icon),
            ),
            matching: find.byWidgetPredicate((w) => w is InkResponse),
          )
          .first,
    );
    for (final icon in [Icons.remove_rounded, Icons.add_rounded]) {
      expect(target(icon).width, greaterThanOrEqualTo(48), reason: '$icon');
      expect(target(icon).height, greaterThanOrEqualTo(48), reason: '$icon');
    }
    final pill = tester.getRect(
      find.byKey(const ValueKey('counter-pill-shape')),
    );
    expect(pill.height, 40);
    expect(pill.width, 112);
    expect(
      target(Icons.remove_rounded).overlaps(target(Icons.add_rounded)),
      isFalse,
    );

    // A touch on the count counts one more.
    await tester.tap(find.descendant(
      of: _in(8, CounterPill),
      matching: find.text('1/3'),
    ));
    await _settle(tester);
    expect(api.bodiesOf('PUT /habits/8/logs/2026-10-04').single, {'count': 2});
    await tester.pumpAndSettle();
  });

  group('the day\'s log at 200% text on a small phone, with a long name and '
      'a refusal to show', () {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      for (final id in [7, 8]) {
        testWidgets('$locale, ${id == 7 ? 'done or not' : 'a count'}: '
            'nothing overflows, and every action stays reachable', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(720, 1280);
          tester.view.devicePixelRatio = 2.0;
          tester.view.padding = const FakeViewPadding(top: 48);
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final log = 'PUT /habits/$id/logs/2026-10-04';
          final home = homeJson();
          home['today_habits'] = [
            for (final habit in home['today_habits'] as List<Map<String, dynamic>>)
              {...habit, 'name': 'Sabah erkenden kalkıp otuz dakika yürüyüş'},
          ];
          final api = FakeApi()
            ..on('GET /home', home)
            ..on(log, {
              'errors': {
                'base': ['Archived habits cannot be logged.'],
              },
              'code': 'habit_archived',
            }, status: 422);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [dioProvider.overrideWithValue(api.dio)],
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
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showHabitLogSheet(context, habitId: id),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await _settle(tester);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'nothing overflows');

          final fill = id == 8
              ? find.byKey(const ValueKey('habit-log-to-target'))
              : find.byType(CheckPop);
          final save = find.text(
            locale.languageCode == 'tr' ? 'Kaydet' : 'Save',
          );
          Future<void> tap(Finder finder) async {
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            await tester.tap(finder);
            await _settle(tester);
            await tester.pumpAndSettle();
          }

          // Fill the day, then save it.
          await tap(fill);
          Future<void> tapComplete() => tap(save);

          // Refused: the reason shows in the sheet, which grows.
          await tapComplete();
          expect(tester.takeException(), isNull, reason: 'nothing overflows');
          expect(
            find.text(
              locale.languageCode == 'tr'
                  ? 'Arşivlenmiş alışkanlık işaretlenemez'
                  : 'An archived habit can\'t be logged',
            ),
            findsOneWidget,
          );

          // Still reachable, and it goes through now — and the sheet
          // closes.
          api.onRequest(log, (_) => logAnswer(id, '2026-10-04', 3));
          await tapComplete();
          expect(api.bodiesOf(log).last, {'count': id == 8 ? 3 : 1});
          expect(save, findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('a ring says what it is to a screen reader', (tester) async {
    _tallPhone(tester);
    final handle = tester.ensureSemantics();
    final api = FakeApi()..on('GET /habits', _habits());
    await tester.pumpWidget(_app(api, const HabitsScreen()));
    await _settle(tester);
    expect(find.bySemanticsLabel('Koşu, henüz yapılmadı'), findsOneWidget);
    // The counter is one adjustable control: its name and count.
    final counter = tester
        .getSemantics(_in(8, CounterPill))
        .getSemanticsData();
    expect(counter.label, 'Su');
    expect(counter.value, '1/3');
    expect(counter.increasedValue, '2/3');
    expect(counter.decreasedValue, '0/3');
    handle.dispose();
  });

  group('the habit form', () {
    Future<Habit?> open(WidgetTester tester, FakeApi api, String name) async {
      Habit? created;
      await tester.pumpWidget(
        _app(
          api,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  created = await openHabitForm(context, initialName: name);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return created;
    }

    testWidgets('opens with the name quick capture typed, and resolves to '
        'the habit it created', (tester) async {
      final api = FakeApi();
      Habit? created;
      await tester.pumpWidget(
        _app(
          api,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  created = await openHabitForm(context, initialName: 'yoga');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'yoga'), findsOneWidget);

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(api.bodiesOf('POST /habits').single, containsPair('name', 'yoga'));
      expect(created?.id, 9);
    });

    testWidgets('a name the server refuses is worded under the field', (
      tester,
    ) async {
      final api = FakeApi()
        ..on('POST /habits', {
          'errors': {
            'name': ['Name is too long (maximum is 60 characters)'],
          },
          'code': 'validation_failed',
          'details': {
            'name': [
              {'error': 'too_long', 'count': 60},
            ],
          },
        }, status: 422);
      await open(tester, api, 'yoga');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.decoration!.errorText, 'En fazla 60 karakter olabilir');
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.text('Yeni alışkanlık'),
        findsOneWidget,
        reason: 'still open',
      );
    });
  });
}
