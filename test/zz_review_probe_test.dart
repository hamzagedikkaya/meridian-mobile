import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/date_utils.dart';
import 'package:meridian_mobile/models/quick_capture.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/flows/create_flows.dart';
import 'package:meridian_mobile/ui/screens/today/widgets/quick_capture_sheet.dart';

import 'support/fake_api.dart';

const _post = 'POST /quick_captures';

class _Flows extends CreateFlows {
  const _Flows();
  @override
  Future<bool> Function(BuildContext, EventSuggestion)? get event =>
      (_, _) async => true;
}

Future<void> _open(WidgetTester tester, FakeApi api,
    {Locale locale = const Locale('tr'),
    CreateFlows flows = const CreateFlows()}) async {
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

Map<String, dynamic> _suggestion(DateTime day, {String? time = '15:00'}) => {
      'saved': false,
      'captured_type': 'event_suggestion',
      'record_id': null,
      'summary': 'yarın 15:00 dişçi',
      'message': 'x',
      'suggestion': {
        'title': 'dişçi randevusu ve sonra eczaneye uğra',
        'date': isoDate(day),
        'time': time,
        'start_at': null,
        'all_day': time == null,
        'keyword': 'yarın',
      },
    };

void _smallPhoneWithKeyboard(WidgetTester tester, {double keyboard = 260}) {
  // iPhone SE (2nd/3rd gen): 375 x 667 logical, @2x.
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.devicePixelRatio = 2.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  tester.view.padding = const FakeViewPadding(top: 40, bottom: 0);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(initializeDateFormatting);

  for (final locale in const [Locale('tr'), Locale('en')]) {
    for (final withEvent in [false, true]) {
      testWidgets(
          'suggestion on a small phone with the keyboard up ($locale, event form: $withEvent)',
          (tester) async {
        _smallPhoneWithKeyboard(tester, keyboard: 291);
        final api = FakeApi()
          ..on(_post, _suggestion(DateTime.now().add(const Duration(days: 1))));
        await _open(tester, api,
            locale: locale,
            flows: withEvent ? const _Flows() : const CreateFlows());
        await tester.enterText(find.byType(TextField), 'yarın 15:00 dişçi');
        await tester.tap(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        final e = tester.takeException();
        // ignore: avoid_print
        print('[$locale event:$withEvent] exception: $e');
      });
    }
  }

  for (final kb in [0.0, 216.0, 260.0, 291.0]) {
    testWidgets('baseline sheet, keyboard $kb', (tester) async {
      _smallPhoneWithKeyboard(tester, keyboard: kb);
      final api = FakeApi();
      await _open(tester, api);
      final e = tester.takeException();
      final size = tester.getSize(find.byType(BottomSheet));
      // ignore: avoid_print
      print('[baseline kb=$kb] exception: $e sheet=$size');
    });
    testWidgets('suggestion sheet, keyboard $kb', (tester) async {
      _smallPhoneWithKeyboard(tester, keyboard: kb);
      final api = FakeApi()
        ..on(_post, _suggestion(DateTime.now().add(const Duration(days: 1))));
      await _open(tester, api);
      await tester.enterText(find.byType(TextField), 'yarın 15:00 dişçi');
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      final e = tester.takeException();
      final sheet = tester.getRect(find.byType(BottomSheet));
      final field = tester.getRect(find.byType(TextField));
      final card = tester.getRect(find.text('Görev olarak kaydet'));
      // ignore: avoid_print
      print('[suggestion kb=$kb] exception: $e sheet=$sheet field=$field saveAsTask=$card');
    });
  }

  testWidgets('unknown habit refusal on a small phone (tr)', (tester) async {
    _smallPhoneWithKeyboard(tester, keyboard: 291);
    final api = FakeApi()
      ..on(_post, {
        'errors': {
          'text': ['x']
        },
        'code': 'unknown_habit',
        'name': 'sabah erkenden kalkıp yürüyüş',
      }, status: 422);
    await _open(tester, api);
    await tester.enterText(
        find.byType(TextField), 'alışkanlık: sabah erkenden kalkıp yürüyüş');
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    final e = tester.takeException();
    // ignore: avoid_print
    print('[unknown habit] exception: $e');
  });
}
