@Tags(['golden'])
/// Profil (Profile), its sign-out sheet and the server settings.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-14.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/current_day.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/ui/screens/profile/profile_screen.dart';
import 'package:meridian_mobile/ui/screens/profile/server_screen.dart';
import 'package:meridian_mobile/ui/widgets/server_url_field.dart';

import '../support/fake_stores.dart';
import 'golden_harness.dart';

// --- Fixtures -----------------------------------------------------------------

User get _user => User(
      id: 1,
      displayName: 'Hamza Gedikkaya',
      initials: 'HG',
      email: 'hamza@meridian.local',
      currency: 'TRY',
      subunitToUnit: 100,
      locale: goldenVariant.lang,
      themePreference: 'dark',
      timezone: 'Istanbul',
      timezoneIana: 'Europe/Istanbul',
      utcOffset: const Duration(hours: 3),
      weeklyReviewDay: 0,
    );

Future<void> _pumpProfile(WidgetTester tester, {String? draft}) async {
  await tester.pumpWidget(goldenHost(
    const ProfileScreen(),
    [
      sharedPrefsProvider.overrideWithValue(goldenPrefs),
      currentUserProvider.overrideWithValue(_user),
      deviceUtcOffsetProvider.overrideWithValue(const Duration(hours: 3)),
      draftStoreProvider.overrideWithValue(MemoryDraftStore(draft)),
      apiHealthProvider.overrideWith(
        (ref) async => (ok: true, latencyMs: 38, version: '1.0.0'),
      ),
    ],
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpGoldens();

  goldenScreen('profile', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await _pumpProfile(tester);
  });

  // The rest of the list: Data, Server, About and signing out.
  goldenScreen('profile_end', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await _pumpProfile(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
  });

  goldenScreen('logout_sheet', (tester, _) async {
    await _pumpProfile(
      tester,
      draft: jsonEncode({'title': '', 'body': 'Yarım kalan yazı'}),
    );
    await tester.scrollUntilVisible(
      find.byIcon(Icons.logout_rounded),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pumpAndSettle();
  });

  goldenScreen('server', (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const ServerScreen(),
      [
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        serverPingProvider.overrideWithValue(
          (url) async => (ok: true, latencyMs: 38, version: '1.0.0'),
        ),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
  });
}
