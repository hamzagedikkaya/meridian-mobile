import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';

/// Semantic haptics (design-analysis §5.8, §8.9): the constant each meaning
/// plays, the API < 30 fallbacks, one haptic per gesture, and none from
/// data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// `HapticFeedback.vibrate` calls, by argument (null: plain vibrate()).
  final played = <String?>[];
  var clock = Duration.zero;

  setUp(() {
    played.clear();
    clock = Duration.zero;
    Haptics.debugReset(now: () => clock);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        played.add(call.arguments as String?);
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Haptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('the constants', () {
    test('each meaning plays its own constant (API 30+)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Haptics.debugReset(androidSdk: 34, now: () => clock);
      final expected = {
        Haptics.tick: 'HapticFeedbackType.selectionClick',
        Haptics.check: 'HapticFeedbackType.lightImpact',
        Haptics.armed: 'HapticFeedbackType.mediumImpact',
        Haptics.confirm: 'HapticFeedbackType.successNotification',
        Haptics.reject: 'HapticFeedbackType.errorNotification',
      };
      for (final MapEntry(key: call, value: constant) in expected.entries) {
        played.clear();
        clock += const Duration(seconds: 1);
        call();
        await settle();
        expect(played, [constant]);
      }
    });

    test('below API 30: CONFIRM falls back to lightImpact, REJECT to '
        'vibrate() (D11)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Haptics.debugReset(androidSdk: 29, now: () => clock);
      Haptics.confirm();
      await settle();
      clock += const Duration(seconds: 1);
      Haptics.reject();
      await settle();
      expect(played, ['HapticFeedbackType.lightImpact', null]);
    });

    test('the API level is read from meridian/device', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Haptics.channel, (call) async {
        return call.method == 'sdkInt' ? 28 : null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Haptics.channel, null));
      await Haptics.init();
      expect(Haptics.androidSdk, 28);
      Haptics.reject();
      await settle();
      expect(played, [null], reason: 'vibrate() below API 30');
    });
  });

  group('the coalescer', () {
    test('one gesture plays once: the highest it asked for', () async {
      // The tap that finishes the day: check + confirm → confirm only.
      Haptics.check();
      Haptics.confirm();
      Haptics.tick();
      await settle();
      expect(played, ['HapticFeedbackType.successNotification']);
    });

    test('within 80 ms only a stronger haptic plays', () async {
      Haptics.check();
      await settle();
      clock += const Duration(milliseconds: 40);
      Haptics.tick();
      await settle();
      Haptics.check();
      await settle();
      expect(played, ['HapticFeedbackType.lightImpact'],
          reason: 'equal or weaker inside the window is dropped');
      Haptics.reject();
      await settle();
      expect(played.last, 'HapticFeedbackType.errorNotification');
      clock += const Duration(milliseconds: 100);
      Haptics.tick();
      await settle();
      expect(played.last, 'HapticFeedbackType.selectionClick');
      expect(played, hasLength(3));
    });
  });

  group('CheckPop', () {
    Widget host(bool checked, {VoidCallback? onToggle, VoidCallback? onTap}) =>
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: CheckPop(
                checked: checked,
                color: const Color(0xFF6B8E5A),
                onToggle: onToggle,
                onTap: onTap,
              ),
            ),
          ),
        );

    testWidgets('a refresh that checks it plays no haptic and no pop',
        (tester) async {
      await tester.pumpWidget(host(false, onTap: () {}));
      await tester.pumpWidget(host(true, onTap: () {}));
      await tester.pumpAndSettle();
      expect(played, isEmpty);
      final scale = tester.widget<ScaleTransition>(find.descendant(
          of: find.byType(CheckPop), matching: find.byType(ScaleTransition)));
      expect(scale.scale.value, 1.0);
    });

    testWidgets('a tap that checks it plays one check', (tester) async {
      var checked = false;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => host(
          checked,
          onToggle: () => setState(() => checked = !checked),
        ),
      ));
      await tester.tap(find.byType(CheckPop));
      await tester.pumpAndSettle();
      expect(played, ['HapticFeedbackType.lightImpact']);
      // Unchecking is silent.
      clock += const Duration(seconds: 1);
      await tester.tap(find.byType(CheckPop));
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
    });

    testWidgets('an older call site: the check its tap causes plays once; a '
        'later refresh none', (tester) async {
      var checked = false;
      late StateSetter set;
      await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return host(checked, onTap: () => setState(() => checked = true));
      }));
      await tester.tap(find.byType(CheckPop));
      await tester.pumpAndSettle();
      expect(played, ['HapticFeedbackType.lightImpact']);
      // Unchecked and checked again by data (the web): silent.
      set(() => checked = false);
      await tester.pump();
      clock += const Duration(seconds: 5);
      await tester.pump(const Duration(seconds: 5));
      set(() => checked = true);
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
    });
  });
}
