import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/reduce_motion.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/theme/app_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer.test(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    return c;
  }

  test('off by default; the switch is stored on the device', () async {
    final c = await container({});
    expect(c.read(reduceMotionProvider), isFalse);
    await c.read(reduceMotionProvider.notifier).set(true);
    expect(c.read(reduceMotionProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefKeys.reduceMotion), 'true');
  });

  test('read back on the next launch', () async {
    final c = await container({PrefKeys.reduceMotion: 'true'});
    expect(c.read(reduceMotionProvider), isTrue);
  });

  test('a device setting: kept across a sign-out', () {
    expect(PrefKeys.keptOnSignOut, contains(PrefKeys.reduceMotion));
  });

  Future<bool> reducedUnder(WidgetTester tester,
      {required bool system, required bool app}) async {
    late bool reduced;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(disableAnimations: system),
      child: MotionPreference(
        reduce: app,
        child: Builder(builder: (context) {
          reduced = Motion.reduced(context);
          return const SizedBox();
        }),
      ),
    ));
    return reduced;
  }

  testWidgets('the app switch and the system flag are one signal',
      (tester) async {
    expect(await reducedUnder(tester, system: false, app: false), isFalse);
    expect(await reducedUnder(tester, system: true, app: false), isTrue);
    expect(await reducedUnder(tester, system: false, app: true), isTrue);
    expect(await reducedUnder(tester, system: true, app: true), isTrue);
  });
}
