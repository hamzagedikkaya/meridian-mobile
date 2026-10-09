import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_detail_screen.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';
import 'package:meridian_mobile/ui/widgets/section_header.dart';

import '../support/fake_api.dart';

/// Signed in already, as after the splash gate.
class _SignedIn extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}

/// Lets the fake API answer and the screens settle (the tabs show
/// indeterminate progress while loading, so pumpAndSettle cannot be used).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    await initializeDateFormatting();
    SharedPreferences.setMockInitialValues({'locale': 'tr'});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('a route pushed over the tabs flies only the visible tab\'s '
      'heroes: every visited tab has a FAB, and they share the default tag',
      (tester) async {
    // Tall enough for Today's goal list, below the fold on a small surface.
    tester.view.physicalSize = const Size(1170, 3900);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sessionProvider.overrideWith(_SignedIn.new),
        dioProvider.overrideWithValue(api.dio),
      ],
      child: const MeridianApp(),
    ));
    await _settle(tester);

    // Two tabs with a FAB visited: both stay mounted, offstage.
    await tester.tap(find.text('Alışkanlık'));
    await _settle(tester);
    await tester.tap(find.text('Günlük'));
    await _settle(tester);
    await tester.tap(find.text('Bugün'));
    await _settle(tester);

    // Goals is a page pushed over the tabs, from Today's goals.
    await tester.tap(find.descendant(
      of: find.widgetWithText(SectionHeader, 'Hedefler'),
      matching: find.textContaining('Tümü'),
    ));
    await _settle(tester);
    expect(find.byType(GoalsScreen), findsOneWidget);

    // The goal tapped comes along, so the ring the hero lands on is there
    // in the detail's first frame — before /goals/3 has answered.
    await tester.tap(find.text('Kitap').first);
    // The push lands a frame after the tap (go_router parses it first).
    for (var i = 0; i < 3 && find.byType(GoalDetailScreen).evaluate().isEmpty;
        i++) {
      await tester.pump();
    }
    expect(
      find.descendant(
        of: find.byType(GoalDetailScreen),
        matching: find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'goal-ring-3'),
      ),
      findsOneWidget,
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(GoalDetailScreen), findsOneWidget);

    // Back to Today, and the same goal opened from there, with Habits and
    // Journal hidden behind it.
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    await tester.tap(find.text('Kitap').first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(GoalDetailScreen), findsOneWidget);
  });
}
