@Tags(['golden'])
/// Hızlı ekle (quick add, design-analysis §7.3): the sheet empty — the type
/// chips and the examples — with a line the app reads as an expense
/// ("Otomatik · Harcama", "Harcama ekle"), and with a refusal that offers
/// the next step.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-6.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/ui/flows/flows.dart';

import '../support/fake_api.dart';
import 'golden_harness.dart';

/// A plain screen to open the sheet over, and the sheet opened on it.
Future<void> _openSheet(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(
    goldenHost(
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openQuickAdd(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      [
        dioProvider.overrideWithValue(api.dio),
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
      ],
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('quick_add', (tester, variant) async {
    await _openSheet(tester, FakeApi());
  });

  goldenScreen('quick_add_guess', (tester, variant) async {
    await _openSheet(tester, FakeApi());
    await tester.enterText(
      find.byType(TextField),
      fx('−85 kahve', const {'−85 kahve': '−85 coffee'}),
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('quick_add_error', (tester, variant) async {
    final api = FakeApi()
      ..on(
        'POST /quick_captures',
        {
          'errors': {
            'text': ['İlk hesabını oluştur'],
          },
          'code': 'no_account',
        },
        status: 422,
      );
    await _openSheet(tester, api);
    await tester.enterText(
      find.byType(TextField),
      fx('−85 kahve', const {'−85 kahve': '−85 coffee'}),
    );
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
  });
}
