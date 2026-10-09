@Tags(['golden'])
/// Profil (Profile).
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-14.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/models/user.dart';
import 'package:meridian_mobile/ui/screens/profile/profile_screen.dart';

import 'golden_harness.dart';

// --- Fixtures -----------------------------------------------------------------

const _user = User(
  id: 1,
  displayName: 'Hamza Gedikkaya',
  initials: 'HG',
  email: 'hamza@meridian.local',
  currency: 'TRY',
  subunitToUnit: 100,
  locale: 'tr',
  themePreference: 'dark',
);

void main() {
  setUpGoldens();

  goldenScreen('profile', variants: GoldenVariant.withLargeText,
      (tester, _) async {
    await tester.pumpWidget(goldenHost(
      const ProfileScreen(),
      [
        sharedPrefsProvider.overrideWithValue(goldenPrefs),
        currentUserProvider.overrideWithValue(_user),
        apiHealthProvider.overrideWith(
          (ref) async => (ok: true, latencyMs: 12, version: '1.0.0'),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  });
}
