import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/haptics.dart';
import 'package:meridian_mobile/core/reduce_motion.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/data/data_scope.dart';
import 'package:meridian_mobile/data/lingering_todos.dart';
import 'package:meridian_mobile/data/recent_changes.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/theme/app_motion.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/habits/widgets/counter_pill.dart';
import 'package:meridian_mobile/ui/widgets/agenda_rows.dart';
import 'package:meridian_mobile/ui/widgets/animated_fraction.dart';
import 'package:meridian_mobile/ui/widgets/celebration_layer.dart';
import 'package:meridian_mobile/ui/widgets/charts.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/entrance.dart';
import 'package:meridian_mobile/ui/widgets/load_phase_switcher.dart';
import 'package:meridian_mobile/ui/widgets/pace_line.dart';
import 'package:meridian_mobile/ui/widgets/paced_progress_bar.dart';
import 'package:meridian_mobile/ui/widgets/progress_ring.dart';
import 'package:meridian_mobile/ui/widgets/rolling_number.dart';
import 'package:meridian_mobile/ui/widgets/row_motion.dart';
import 'package:meridian_mobile/ui/widgets/sync_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';

/// The motion components (design-analysis §4.19–4.30, §5, §8.5, §8.9):
/// what moves, what never does, and that reduced motion shows the end state
/// in one frame.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    DigitSlots.clearCache();
  });

  setUp(() {
    // No vibrator in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    Haptics.debugReset();
  });

  Widget app(
    Widget child, {
    bool reduced = false,
    double width = 360,
    TextScaler? scaler,
  }) =>
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('tr'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: scaler ?? MediaQuery.textScalerOf(context),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  const hero = TextStyle(
    fontFamily: 'Fraunces',
    fontSize: 40,
    height: 46 / 40,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );

  /// The haptics played from now on, by their `HapticFeedbackType`.
  List<String?> recordHaptics() {
    final played = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        played.add(call.arguments as String?);
      }
      return null;
    });
    return played;
  }

  group('RollingNumber', () {
    testWidgets('digit slots: "1" and "0" take the same width', (tester) async {
      Future<double> widthOf(String text) async {
        await tester.pumpWidget(app(Align(
          alignment: Alignment.topLeft,
          child: RollingNumber(
              key: ValueKey(text), text: text, style: hero, fractionScale: 1),
        )));
        return tester.getSize(find.byType(RollingNumber)).width;
      }

      final one = await widthOf('1');
      final zero = await widthOf('0');
      expect(one, closeTo(zero, 0.01));
      expect(DigitSlots.slotWidth(hero), closeTo(27.0, 0.05),
          reason: "Fraunces SemiBold '0' is 1350/2000 em: 27 dp at 40 sp");
      expect(await widthOf('111'), closeTo(await widthOf('808'), 0.01));
    });

    testWidgets('+₺1.234.567,89 at 40 sp fits 280 dp on one line',
        (tester) async {
      await tester.pumpWidget(app(
        const RollingNumber(text: '+₺1.234.567,89', style: hero),
        width: 280,
      ));
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(RollingNumber), matching: find.byType(RichText)));
      expect(paragraph.size.height, closeTo(46, 0.5), reason: 'one line');
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getSize(find.byType(RollingNumber)).width,
          lessThanOrEqualTo(280));
      // It is scaled down, not cut: the full text is there.
      expect(find.text('+₺1.234.567,89'), findsOneWidget);
      expect(paragraph.size.width, greaterThan(280));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refresh (background) cross-fades: nothing moves',
        (tester) async {
      Widget number(String text) => app(RollingNumber(
            text: text,
            style: hero,
            cause: NumberCause.background,
          ));
      await tester.pumpWidget(number('₺1.234,00'));
      await tester.pumpWidget(number('₺1.299,00'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final moving = tester
            .widgetList<Transform>(find.descendant(
                of: find.byType(RollingNumber),
                matching: find.byType(Transform)))
            .where((t) => t.transform.getTranslation().y.abs() > 0.01);
        expect(moving, isEmpty);
      }
      await tester.pumpAndSettle();
      expect(find.text('₺1.299,00'), findsOneWidget);
      expect(find.text('₺1.234,00'), findsNothing);
    });

    testWidgets('a change by the user rolls only the digits that changed',
        (tester) async {
      Widget number(String text) => app(RollingNumber(
            text: text,
            style: hero,
            cause: NumberCause.user,
          ));
      await tester.pumpWidget(number('₺1.234,00'));
      await tester.pumpWidget(number('₺1.239,00'));
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester
          .widgetList<Transform>(find.descendant(
              of: find.byType(RollingNumber), matching: find.byType(Transform)))
          .where((t) => t.transform.getTranslation().y.abs() > 0.01);
      // The outgoing 4 and the incoming 9: one slot.
      expect(moving, hasLength(2));
      await tester.pumpAndSettle();
      expect(find.text('₺1.239,00'), findsOneWidget);
    });

    testWidgets('reduced motion: the final value in one frame, every cause',
        (tester) async {
      for (final cause in NumberCause.values) {
        Widget number(String text) => app(
              RollingNumber(text: text, style: hero, cause: cause),
              reduced: true,
            );
        await tester.pumpWidget(number('₺10,00'));
        await tester.pumpWidget(number('₺99,00'));
        expect(find.text('₺99,00'), findsOneWidget, reason: '$cause');
        expect(find.text('₺10,00'), findsNothing, reason: '$cause');
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse, reason: '$cause');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a screen reader hears the whole amount once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const RollingNumber(
        text: '−₺250,00',
        style: hero,
        semanticsLabel: '−₺250,00',
      )));
      expect(find.bySemanticsLabel('−₺250,00'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('each digit sits in the middle of its slot (§3.7)',
        (tester) async {
      await tester.pumpWidget(app(const Align(
        alignment: Alignment.topLeft,
        child: RollingNumber(text: '17', style: hero, fractionScale: 1),
      )));
      final rich = find.descendant(
          of: find.byType(RollingNumber), matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      final left = tester.getTopLeft(find.byType(RollingNumber)).dx;
      final textLeft = tester.getTopLeft(rich).dx;
      final slot = DigitSlots.slotWidth(hero);
      final step = slot + hero.letterSpacing!;
      double advance(String digit) {
        final tp = TextPainter(
          text: TextSpan(text: digit, style: hero.copyWith(letterSpacing: 0)),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      }

      for (final (i, digit) in [(0, '1'), (1, '7')]) {
        final pen = textLeft +
            paragraph
                .getOffsetForCaret(TextPosition(offset: i), Rect.zero)
                .dx;
        expect(pen + advance(digit) / 2, closeTo(left + i * step + slot / 2, 0.1),
            reason: "'$digit' is centred in slot $i");
      }
    });

    /// The glyphs moving vertically in the number right now.
    List<String> movingGlyphs(WidgetTester tester) => [
          for (final e in find
              .descendant(
                  of: find.byType(RollingNumber),
                  matching: find.byType(Transform))
              .evaluate())
            if ((e.widget as Transform).transform.getTranslation().y.abs() >
                0.01)
              for (final t in find
                  .descendant(
                      of: find.byWidget(e.widget), matching: find.byType(Text))
                  .evaluate())
                (t.widget as Text).data!,
        ];

    testWidgets('999 → 1.000: the ₺ stays; only digit slots are born and roll',
        (tester) async {
      Widget number(String text) =>
          app(RollingNumber(text: text, style: hero, cause: NumberCause.user));
      await tester.pumpWidget(number('₺999'));
      await tester.pumpWidget(number('₺1.000'));
      await tester.pump(const Duration(milliseconds: 60));
      final moving = movingGlyphs(tester);
      expect(moving, isNot(contains('₺')));
      expect(moving.where((g) => g == '9'), hasLength(3));
      expect(moving.where((g) => g == '0'), hasLength(3));
      await tester.pumpAndSettle();
      expect(find.text('₺1.000'), findsOneWidget);
    });

    testWidgets('a shorter fraction still rolls the right way: 12,50 → 12,6 '
        'goes up', (tester) async {
      Widget number(String text) => app(RollingNumber(
            text: text,
            style: hero,
            cause: NumberCause.user,
            decimalSeparator: ',',
          ));
      await tester.pumpWidget(number('₺12,50'));
      await tester.pumpWidget(number('₺12,6'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(movingGlyphs(tester), unorderedEquals(['5', '0', '6']));
      final incoming = tester
          .widgetList<Transform>(find.ancestor(
              of: find.text('6'), matching: find.byType(Transform)))
          .map((t) => t.transform.getTranslation().y)
          .firstWhere((y) => y.abs() > 0.01);
      // Up: the new digit rises from below.
      expect(incoming, greaterThan(0));
      await tester.pumpAndSettle();
    });
  });

  group('CheckPop', () {
    Widget pop({required bool checked, required VoidCallback onToggle, bool box = false}) =>
        box
            ? CheckPop.checkbox(
                checked: checked, color: Colors.green, onToggle: onToggle)
            : CheckPop(checked: checked, color: Colors.green, onToggle: onToggle);

    for (final box in [false, true]) {
      testWidgets('the check pop stays within [0.88, 1.06] and moves ≤ 0.06 '
          'a frame (${box ? 'checkbox' : 'ring'})', (tester) async {
        var checked = false;
        await tester.pumpWidget(app(Center(
          child: StatefulBuilder(
            builder: (context, setState) => pop(
              checked: checked,
              box: box,
              onToggle: () => setState(() => checked = !checked),
            ),
          ),
        )));
        double scale() => tester
            .widget<ScaleTransition>(find.descendant(
                of: find.byType(CheckPop),
                matching: find.byType(ScaleTransition)))
            .scale
            .value;

        // A held press, then the tap.
        final gesture =
            await tester.startGesture(tester.getCenter(find.byType(CheckPop)));
        var last = scale();
        for (var t = 0; t < 120; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          final s = scale();
          expect(s, inInclusiveRange(0.88, 1.06));
          expect((s - last).abs(), lessThanOrEqualTo(0.06));
          last = s;
        }
        await gesture.up();
        for (var t = 0; t < 600; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          final s = scale();
          expect(s, inInclusiveRange(0.88, 1.06));
          expect((s - last).abs(), lessThanOrEqualTo(0.06));
          last = s;
        }
        expect(checked, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(scale(), 1.0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }

    for (final viaOnTap in [false, true]) {
      testWidgets('a tap taken back after a failed write un-fills in 200 ms, '
          'without a pop (${viaOnTap ? 'onTap' : 'onToggle'})', (tester) async {
        var checked = false;
        late StateSetter set;
        await tester.pumpWidget(app(Center(
          child: StatefulBuilder(builder: (context, setState) {
            set = setState;
            void flip() => setState(() => checked = !checked);
            return viaOnTap
                ? CheckPop(checked: checked, color: Colors.green, onTap: flip)
                : CheckPop(
                    checked: checked, color: Colors.green, onToggle: flip);
          }),
        )));
        double fill() => ((tester
                .widget<CustomPaint>(find.descendant(
                    of: find.byType(CheckPop),
                    matching: find.byType(CustomPaint)))
                .painter as dynamic)
            .fill as Animation<double>)
            .value;
        await tester.tap(find.byType(CheckPop));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(fill(), 1.0);

        // The write fails: the screen puts the old state back.
        set(() => checked = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(fill(), allOf(greaterThan(0.0), lessThan(1.0)),
            reason: 'on its way out, not gone in one frame');
        final scale = tester
            .widget<ScaleTransition>(find.descendant(
                of: find.byType(CheckPop),
                matching: find.byType(ScaleTransition)))
            .scale
            .value;
        expect(scale, 1.0, reason: 'no pop');
        await tester.pump(const Duration(milliseconds: 150));
        expect(fill(), 0.0);

        // A later data change is the data's: at once.
        set(() => checked = true);
        await tester.pump();
        expect(fill(), 1.0);
        await tester.pumpAndSettle();
      });

      testWidgets('once the write has had its time, a change back is the '
          'data\'s: at once (${viaOnTap ? 'onTap' : 'onToggle'})',
          (tester) async {
        var checked = false;
        late StateSetter set;
        await tester.pumpWidget(app(Center(
          child: StatefulBuilder(builder: (context, setState) {
            set = setState;
            void flip() => setState(() => checked = !checked);
            return viaOnTap
                ? CheckPop(checked: checked, color: Colors.green, onTap: flip)
                : CheckPop(
                    checked: checked, color: Colors.green, onToggle: flip);
          }),
        )));
        double fill() => ((tester
                .widget<CustomPaint>(find.descendant(
                    of: find.byType(CheckPop),
                    matching: find.byType(CustomPaint)))
                .painter as dynamic)
            .fill as Animation<double>)
            .value;
        await tester.tap(find.byType(CheckPop));
        await tester.pumpAndSettle();
        expect(fill(), 1.0);

        // The write went through; later the web unchecks it.
        await tester.pump(const Duration(seconds: 10));
        set(() => checked = false);
        await tester.pump();
        expect(fill(), 0.0, reason: 'a web edit shows at once (§4.22)');
        await tester.pumpAndSettle();
      });
    }

    testWidgets('reduced motion: filled at once, no scale', (tester) async {
      var checked = false;
      await tester.pumpWidget(app(
        Center(
          child: StatefulBuilder(
            builder: (context, setState) => pop(
              checked: checked,
              onToggle: () => setState(() => checked = !checked),
            ),
          ),
        ),
        reduced: true,
      ));
      await tester.tap(find.byType(CheckPop));
      await tester.pump();
      expect(checked, isTrue);
      final scale = tester.widget<ScaleTransition>(find.descendant(
          of: find.byType(CheckPop), matching: find.byType(ScaleTransition)));
      expect(scale.scale.value, 1.0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('is a checkable button for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(Center(
        child: CheckPop(
          checked: true,
          color: Colors.green,
          onToggle: () {},
          semanticLabel: 'Sabah koşusu',
        ),
      )));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Sabah koşusu')),
        matchesSemantics(
          label: 'Sabah koşusu',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(find.byType(CheckPop)), const Size(48, 48));
      handle.dispose();
    });

    group('onTap (older call sites)', () {
      late StateSetter setChecked;
      var checked = false;

      Widget host(VoidCallback Function(StateSetter set) onTap) => app(Center(
            child: StatefulBuilder(builder: (context, setState) {
              setChecked = setState;
              return CheckPop(
                checked: checked,
                color: Colors.green,
                onTap: onTap(setState),
              );
            }),
          ));

      setUp(() => checked = false);

      testWidgets('a check the tap makes pops with one check haptic',
          (tester) async {
        final played = recordHaptics();
        await tester.pumpWidget(
            host((set) => () => set(() => checked = true)));
        await tester.tap(find.byType(CheckPop));
        await tester.pump();
        expect(played, ['HapticFeedbackType.lightImpact']);
        await tester.pumpAndSettle();
      });

      testWidgets('a tap that changes nothing, then the data checks it: no '
          'pop, no haptic (§8.9)', (tester) async {
        final played = recordHaptics();
        // A counted habit stepping 1/3 → 2/3: checked stays false.
        await tester.pumpWidget(host((_) => () {}));
        await tester.tap(find.byType(CheckPop));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        // A refresh or a web edit completes it.
        setChecked(() => checked = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(played, isEmpty);
        final scale = tester
            .widget<ScaleTransition>(find.descendant(
                of: find.byType(CheckPop),
                matching: find.byType(ScaleTransition)))
            .scale
            .value;
        expect(scale, 1.0, reason: 'no pop');
        await tester.pumpAndSettle();
      });
    });
  });

  group('AnimatedFraction', () {
    testWidgets('a new target keeps the speed it had; the value never leaves '
        '[0, 1]', (tester) async {
      final f = AnimatedFraction(vsync: tester, target: 0);
      addTearDown(f.dispose);
      f.retarget(1, reduced: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final speed = f.velocity;
      expect(speed, greaterThan(0));
      f.retarget(0.4, reduced: false);
      expect(f.velocity, closeTo(speed, speed * 0.05),
          reason: 'retargeting carries the velocity');
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(f.value, inInclusiveRange(0.0, 1.0));
      }
      expect(f.value, closeTo(0.4, 0.01));
    });

    testWidgets('reduced: the target at once', (tester) async {
      final f = AnimatedFraction(vsync: tester, target: 0.2);
      addTearDown(f.dispose);
      f.retarget(0.9, reduced: true);
      expect(f.value, 0.9);
    });
  });

  group('rings and bars', () {
    testWidgets('reduced motion: a new value is drawn in one frame',
        (tester) async {
      Widget build(double v) => app(
            Column(children: [
              ProgressRing(value: v, color: Colors.green),
              PacedProgressBar(value: v, color: Colors.green),
            ]),
            reduced: true,
          );
      await tester.pumpWidget(build(0.2));
      await tester.pumpWidget(build(0.7));
      final ring = tester.state<ProgressRingState>(find.byType(ProgressRing));
      expect(ring.paintedValue, 0.7);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the ring says its percentage', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          app(const ProgressRing(value: 0.62, color: Colors.green)));
      expect(
        tester.getSemantics(find.byType(ProgressRing)),
        matchesSemantics(value: '%62'),
      );
      handle.dispose();
    });

    testWidgets('a centre showing the percentage is not read twice',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Center(
        child: ProgressRing(
          value: 0.62,
          color: Colors.green,
          center: Text('%62'),
        ),
      )));
      expect(
        tester.getSemantics(find.byType(ProgressRing)),
        matchesSemantics(value: '%62'),
      );
      expect(find.bySemanticsLabel('%62'), findsNothing);
      handle.dispose();
    });

    testWidgets('at 2× text the centre stays inside the stroke',
        (tester) async {
      await tester.pumpWidget(app(
        Center(
          child: Builder(
            builder: (context) => ProgressRing(
              value: 0.62,
              color: Colors.green,
              center: Text(
                '%62',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
        ),
        scaler: const TextScaler.linear(2),
      ));
      final ring = tester.getRect(find.byType(ProgressRing));
      final label = tester.getRect(find.text('%62'));
      final inner = ring.deflate(6);
      // The label's box (scaled down by the FittedBox) is within the hole.
      final box = tester.renderObject<RenderBox>(find.text('%62'));
      final shown = MatrixUtils.transformRect(
          box.getTransformTo(null), Offset.zero & box.size);
      expect(shown.left, greaterThanOrEqualTo(inner.left));
      expect(shown.right, lessThanOrEqualTo(inner.right));
      expect(label.width, greaterThan(0));
    });

    testWidgets('a bar narrower than it is tall paints without throwing',
        (tester) async {
      for (final width in [4.0, 1.0, 0.0]) {
        await tester.pumpWidget(app(Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const PacedProgressBar(
              value: 0.5,
              color: Colors.green,
              paceTick: 0.4,
              height: 6,
            ),
          ),
        )));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: '$width dp');
      }
    });
  });

  group('EntranceGate', () {
    testWidgets('items on the first frame rise in; one mounted later starts '
        'finished', (tester) async {
      var late = false;
      late StateSetter set;
      await tester.pumpWidget(app(EntranceHost(
        child: StatefulBuilder(builder: (context, setState) {
          set = setState;
          EntranceGate.maybeOf(context)!.openForFirstFrame(context);
          return Column(children: [
            for (var i = 0; i < 3; i++)
              Entrance.staggered(
                  play: true, index: i, child: Text('first $i')),
            if (late) const Entrance(play: true, child: Text('late')),
          ]);
        }),
      )));
      double opacity(String text) => tester
          .widget<FadeTransition>(find
              .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
              .first)
          .opacity
          .value;
      await tester.pump(const Duration(milliseconds: 16));
      expect(opacity('first 0'), lessThan(1));
      set(() => late = true);
      await tester.pump();
      expect(opacity('late'), 1.0);
      await tester.pumpAndSettle();
      expect(opacity('first 2'), 1.0);
    });

    testWidgets('reduced motion: nothing plays', (tester) async {
      await tester.pumpWidget(app(
        EntranceHost(
          child: Builder(builder: (context) {
            EntranceGate.maybeOf(context)!.openForFirstFrame(context);
            return const Entrance(play: true, child: Text('a'));
          }),
        ),
        reduced: true,
      ));
      final fade = tester.widget<FadeTransition>(find
          .ancestor(of: find.text('a'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, 1.0);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('LoadPhaseSwitcher', () {
    Widget switcher(LoadPhase phase, {bool reduced = false}) => app(
          SizedBox(
            height: 200,
            child: LoadPhaseSwitcher(
              phase: phase,
              skeleton: (_) => const Text('skeleton'),
              content: (_) => const Text('content'),
              error: (_) => const Text('error'),
            ),
          ),
          reduced: reduced,
        );

    testWidgets('data in 300 ms: the skeleton never shows', (tester) async {
      await tester.pumpWidget(switcher(LoadPhase.waiting));
      for (var t = 0; t < 300; t += 50) {
        expect(find.text('skeleton'), findsNothing);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(switcher(LoadPhase.content));
      expect(find.text('content'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('skeleton'), findsNothing);
    });

    for (final reduced in [false, true]) {
      testWidgets('data in 600 ms: the skeleton shows from 400 ms for at '
          'least 400 ms${reduced ? ' (reduced motion: same delays)' : ''}',
          (tester) async {
        await tester.pumpWidget(switcher(LoadPhase.waiting, reduced: reduced));
        await tester.pump(const Duration(milliseconds: 399));
        expect(find.text('skeleton'), findsNothing);
        await tester.pump(const Duration(milliseconds: 2));
        expect(find.text('skeleton'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 199)); // 600 ms
        await tester.pumpWidget(switcher(LoadPhase.content, reduced: reduced));
        // 400 ms of skeleton have not passed: it stays.
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('skeleton'), findsOneWidget);
        expect(find.text('content'), findsNothing);
        await tester.pump(const Duration(milliseconds: 60)); // 810 ms
        expect(find.text('content'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('skeleton'), findsNothing);
      });
    }

    testWidgets('content once shown never goes back to a skeleton',
        (tester) async {
      await tester.pumpWidget(switcher(LoadPhase.content));
      await tester.pumpWidget(switcher(LoadPhase.waiting));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);
    });
  });

  group('SyncHint', () {
    for (final reduced in [false, true]) {
      testWidgets('waits a full second${reduced ? ' (reduced motion too), '
          'then a still line' : ''}', (tester) async {
        Widget hint(bool active) =>
            app(SyncHint(active: active), reduced: reduced);
        await tester.pumpWidget(hint(false));
        await tester.pumpWidget(hint(true));
        await tester.pump(const Duration(milliseconds: 990));
        expect(find.byType(AnimatedOpacity), findsNothing);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(AnimatedOpacity), findsOneWidget);
        expect(find.byType(LinearProgressIndicator),
            reduced ? findsNothing : findsOneWidget);
        await tester.pumpWidget(hint(false));
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (reduced) expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }
  });

  group('CelebrationLayer', () {
    Future<CelebrationController> host(WidgetTester tester,
        {bool reduced = false}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      late CelebrationController controller;
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: app(
          CelebrationLayer(
            child: Builder(builder: (context) {
              controller = CelebrationLayer.maybeOf(context)!;
              return const SizedBox(height: 400);
            }),
          ),
          reduced: reduced,
        ),
      ));
      return controller;
    }

    testWidgets('the day is celebrated once: confetti and the pill',
        (tester) async {
      final layer = await host(tester);
      final day = DateTime(2026, 10, 4);
      expect(layer.allDone(origin: const Offset(100, 200), day: day), isTrue);
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hepsi tamam'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(find.text('Hepsi tamam'), findsNothing);
      // Unchecked and checked again: not again, and nothing claimed for
      // the caller to give back.
      expect(layer.allDone(origin: const Offset(100, 200), day: day), isFalse);
      await tester.pump(); // the layer's microtask
      await tester.pump(); // its frame
      expect(find.byType(ConfettiBurst), findsNothing);
    });

    testWidgets('another account signing in on this phone gets its own '
        'celebration of the day', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      late CelebrationController layer;
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sessionProvider.overrideWith(_SwitchableSession.new),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: app(CelebrationLayer(
          child: Builder(builder: (context) {
            layer = CelebrationLayer.maybeOf(context)!;
            return const SizedBox(height: 400);
          }),
        )),
      ));
      final day = DateTime(2026, 10, 4);
      expect(layer.allDone(origin: Offset.zero, day: day), isTrue);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();

      // Signed out (the device's keys go with the account), then another
      // account signs in and finishes its day.
      final session =
          container.read(sessionProvider.notifier) as _SwitchableSession;
      session.set(const SessionLoggedOut());
      await prefs.clear();
      await tester.pump();
      session.set(const SessionLoggedIn());
      await tester.pump();
      expect(layer.allDone(origin: Offset.zero, day: day), isTrue);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
    });

    testWidgets('a refused write gives the day back: the real finish still '
        'celebrates', (tester) async {
      final layer = await host(tester);
      final day = DateTime(2026, 10, 4);
      layer.allDone(origin: const Offset(100, 200), day: day);
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
      // The server refused the tap that finished the day.
      layer.forget(day);
      layer.allDone(origin: const Offset(100, 200), day: day);
      await tester.pump(); // the layer's microtask
      await tester.pump(); // its frame
      expect(find.byType(ConfettiBurst), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
    });

    testWidgets('forgotten in the same event: nothing plays', (tester) async {
      final layer = await host(tester);
      final day = DateTime(2026, 10, 4);
      layer.allDone(origin: Offset.zero, day: day);
      layer.forget(day);
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(find.text('Hepsi tamam'), findsNothing);
    });

    testWidgets('one gesture plays its highest tier only', (tester) async {
      final layer = await host(tester);
      layer.allDone(origin: Offset.zero, day: DateTime(2026, 10, 4));
      layer.milestone(key: 'habit.3.30', text: '30 gün · Koşu');
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(find.text('30 gün · Koşu'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
      expect(find.text('30 gün · Koşu'), findsNothing);
    });

    /// A CheckPop whose tap asks the layer for [celebrate].
    Future<List<String?>> tapToFinish(
      WidgetTester tester,
      void Function(CelebrationController layer) celebrate,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var checked = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: app(
          CelebrationLayer(
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) => CheckPop(
                  checked: checked,
                  color: Colors.green,
                  onToggle: () {
                    setState(() => checked = !checked);
                    celebrate(CelebrationLayer.maybeOf(context)!);
                  },
                ),
              ),
            ),
          ),
        ),
      ));
      final played = recordHaptics();
      await tester.tap(find.byType(CheckPop));
      await tester.pump();
      return played;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(Motion.milestoneHold);
      await tester.pumpAndSettle();
    }

    testWidgets('the tap that finishes the day plays confirm only (§5.8)',
        (tester) async {
      final played = await tapToFinish(
        tester,
        (layer) =>
            layer.allDone(origin: Offset.zero, day: DateTime(2026, 10, 4)),
      );
      expect(played, ['HapticFeedbackType.successNotification']);
      await settle(tester);
      expect(played, hasLength(1));
    });

    testWidgets('a milestone tap: one confirm, nothing else', (tester) async {
      final played = await tapToFinish(tester, (layer) {
        layer.allDone(origin: Offset.zero, day: DateTime(2026, 10, 4));
        layer.milestone(key: 'habit.3.7', text: '7 gün · Koşu');
      });
      expect(played, ['HapticFeedbackType.successNotification']);
      await settle(tester);
      expect(played, hasLength(1));
    });

    testWidgets('a day already celebrated: the check haptic alone',
        (tester) async {
      final day = DateTime(2026, 10, 4);
      SharedPreferences.setMockInitialValues({celebratedDayKey(day): true});
      final prefs = await SharedPreferences.getInstance();
      var checked = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: app(CelebrationLayer(
          child: Center(
            child: StatefulBuilder(
              builder: (context, setState) => CheckPop(
                checked: checked,
                color: Colors.green,
                onToggle: () {
                  setState(() => checked = !checked);
                  CelebrationLayer.maybeOf(context)!
                      .allDone(origin: Offset.zero, day: day);
                },
              ),
            ),
          ),
        )),
      ));
      final played = recordHaptics();
      await tester.tap(find.byType(CheckPop));
      await tester.pump();
      expect(played, ['HapticFeedbackType.lightImpact']);
      expect(find.byType(ConfettiBurst), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('reduced motion: no particles; the pill without motion',
        (tester) async {
      final layer = await host(tester, reduced: true);
      layer.allDone(origin: const Offset(100, 200), day: DateTime(2026, 10, 5));
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsNothing);
      await tester.pump();
      expect(find.text('Hepsi tamam'), findsOneWidget);
      final fade = tester.widget<FadeTransition>(find
          .ancestor(
              of: find.text('Hepsi tamam'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, 1.0);
      await tester.pump(Motion.milestoneHold);
      await tester.pump();
      expect(find.text('Hepsi tamam'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('large text (§8.3)', () {
    const scalers = {
      'linear 2.0': TextScaler.linear(2),
      'Android 14+ 200 %': _Android200(),
    };

    Event event(int id, {bool allDay = false}) => Event.fromJson({
          'id': id,
          'title': 'Etkinlik $id',
          'all_day': allDay,
          'start_at': allDay
              ? '2026-10-04'
              : DateTime(2026, 10, 4, 10).toIso8601String(),
          'duration_minutes': allDay ? null : 75,
          'color': '#6B8FA0',
        });

    /// Whether [finder]'s text is shown whole, not cut by its box.
    void expectWhole(WidgetTester tester, Finder finder, String reason) {
      final p = tester.renderObject<RenderParagraph>(finder);
      expect(p.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(p.size.width + 0.01),
          reason: reason);
    }

    for (final MapEntry(key: name, value: scaler) in scalers.entries) {
      testWidgets('an event\'s time slot is never cut ($name)',
          (tester) async {
        await tester.pumpWidget(app(
          Column(children: [
            EventRow(event: event(1, allDay: true)),
            EventRow(event: event(2)),
          ]),
          scaler: scaler,
        ));
        for (final text in ['Tüm gün', '10:00', '11:15']) {
          expectWhole(tester, find.text(text), '"$text" at $name');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('six-month labels fit their band and never collide '
          '($name)', (tester) async {
        const labels = ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'];
        await tester.pumpWidget(app(
          const SixMonthBars(
            labels: labels,
            incomeCents: [52, 52, 54, 54, 57, 57],
            expenseCents: [31, 36, 29, 38, 33, 12],
            currency: 'TRY',
            subunitToUnit: 100,
            height: 150,
          ),
          width: 320,
          scaler: scaler,
        ));
        await tester.pumpAndSettle();
        final chart = tester.getRect(find.byType(SixMonthBars));
        final shown = [
          for (final l in labels)
            if (find.text(l).evaluate().isNotEmpty) tester.getRect(find.text(l)),
        ]..sort((a, b) => a.left.compareTo(b.left));
        expect(find.text('Eki'), findsOneWidget,
            reason: 'the current month is always labelled');
        for (final r in shown) {
          expect(r.bottom, lessThanOrEqualTo(chart.bottom + 0.5));
        }
        for (var i = 1; i < shown.length; i++) {
          expect(shown[i].left, greaterThanOrEqualTo(shown[i - 1].right),
              reason: 'labels overlap');
        }
      });

      testWidgets('pace day labels fit their band ($name)', (tester) async {
        await tester.pumpWidget(app(
          PaceLine(
            spent: const [100, 220, 300],
            reference: const [90, 200, 310, 400],
            daysInMonth: 31,
            month: DateTime(2026, 10),
            currency: 'TRY',
            subunitToUnit: 100,
          ),
          scaler: scaler,
        ));
        await tester.pumpAndSettle();
        final chart = tester.getRect(find.byType(PaceLine));
        for (final day in ['1', '15', '31']) {
          final r = tester.getRect(find.text(day));
          expect(r.bottom, lessThanOrEqualTo(chart.bottom + 0.5));
          expect(r.height,
              greaterThanOrEqualTo(scaler.scale(11) * 14 / 11 - 0.5));
        }
      });
    }

    testWidgets('at 1× every month is labelled', (tester) async {
      const labels = ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'];
      await tester.pumpWidget(app(
        const SixMonthBars(
          labels: labels,
          incomeCents: [52, 52, 54, 54, 57, 57],
          expenseCents: [31, 36, 29, 38, 33, 12],
          currency: 'TRY',
          subunitToUnit: 100,
        ),
        width: 320,
      ));
      await tester.pumpAndSettle();
      for (final l in labels) {
        expect(find.text(l), findsOneWidget);
      }
    });
  });

  group('row motion (§4.29)', () {
    const scope = DataScope.transactions;

    Future<ProviderContainer> list(WidgetTester tester, List<int> ids) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: app(_Rows(ids)),
      ));
      return container;
    }

    Future<void> show(WidgetTester tester, ProviderContainer container,
        List<int> ids) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: app(_Rows(ids)),
      ));
    }

    testWidgets('a refetch adds and drops rows without motion',
        (tester) async {
      final container = await list(tester, [1, 2, 3]);
      await show(tester, container, [1, 3, 4]);
      expect(find.text('Satır 2'), findsNothing, reason: 'no ghost');
      expect(find.byType(RowExit), findsNothing);
      final enter = tester.widget<RowEnter>(find.descendant(
          of: find.byKey(const ValueKey('row-4')),
          matching: find.byType(RowEnter)));
      expect(enter.play, isFalse);
      final wash = tester.widget<HighlightWash>(find.descendant(
          of: find.byKey(const ValueKey('row-4')),
          matching: find.byType(HighlightWash)));
      expect(wash.play, isFalse);
      // At full height on the first frame: nothing grows in.
      expect(tester.getSize(find.byKey(const ValueKey('row-4'))).height, 40);
    });

    testWidgets('a row the user deleted leaves a collapsing ghost',
        (tester) async {
      final container = await list(tester, [1, 2, 3]);
      container
          .read(recentChangesProvider.notifier)
          .record(scope, 2, ChangeKind.removed);
      await show(tester, container, [1, 3]);
      expect(find.byType(RowExit), findsOneWidget);
      expect(find.text('Satır 2'), findsOneWidget);
      await tester.pump(Motion.collapse ~/ 2);
      final size = tester.getSize(find.byType(RowExit)).height;
      expect(size, greaterThan(0));
      expect(size, lessThan(40));
      await tester.pumpAndSettle();
      expect(find.text('Satır 2'), findsNothing);
      expect(find.byType(RowExit), findsNothing);
    });

    testWidgets('a row created here grows in and is washed; reduced motion '
        'shows it at once', (tester) async {
      for (final reduced in [false, true]) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(recentChangesProvider.notifier)
            .record(scope, 9, ChangeKind.inserted);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: app(const _Rows([9]), reduced: reduced),
        ));
        final enter = tester.widget<RowEnter>(find.byType(RowEnter));
        expect(enter.play, isTrue);
        final row = tester.getSize(find.byKey(const ValueKey('row-9')));
        if (reduced) {
          expect(row.height, 40, reason: 'reduced: at full height at once');
          expect(tester.binding.transientCallbackCount, 0,
              reason: 'reduced: nothing ticking');
        } else {
          expect(row.height, lessThan(40));
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byKey(const ValueKey('row-9'))).height,
              40);
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('the app\'s own "Reduce motion" switch (§8.5)', () {
    /// A CounterPill one step from its target under [wrap]: the step to the
    /// target lands in one frame — the new count, no roll, no swell, the
    /// complete shape — and nothing is left to animate.
    Future<void> expectCounterPillStill(
      WidgetTester tester,
      Widget Function(Widget child) wrap,
    ) async {
      var count = 2;
      const tone = (
        fill: Colors.green,
        text: Colors.lightGreen,
        tint: Color(0x3300FF00),
        onFill: Colors.white,
      );
      await tester.pumpWidget(wrap(Center(
        child: StatefulBuilder(
          builder: (context, setState) => CounterPill(
            count: count,
            target: 3,
            tone: tone,
            onDelta: (delta, _) => setState(() => count += delta),
          ),
        ),
      )));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(count, 3);
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('2/3'), findsNothing, reason: 'no digit roll');
      final scale = tester.widget<ScaleTransition>(find
          .descendant(
              of: find.byType(CounterPill),
              matching: find.byType(ScaleTransition))
          .first);
      expect(scale.scale.value, 1.0, reason: 'no swell');
      final shape = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('counter-pill-shape')));
      expect((shape.decoration as ShapeDecoration).color, tone.tint);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(scale.scale.value, 1.0);
    }

    testWidgets('CounterPill under disableAnimations: the step and the '
        'target land in one frame', (tester) async {
      await expectCounterPillStill(
          tester, (child) => app(child, reduced: true));
    });

    testWidgets('folds into disableAnimations: a number and a check show '
        'their end state in one frame', (tester) async {
      SharedPreferences.setMockInitialValues(
          {PrefKeys.reduceMotion: 'true'});
      final prefs = await SharedPreferences.getInstance();
      var value = '₺10,00';
      var checked = false;
      late StateSetter set;
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: app(Consumer(
          builder: (context, ref, _) => MotionPreference(
            reduce: ref.watch(reduceMotionProvider),
            child: StatefulBuilder(builder: (context, setState) {
              set = setState;
              expect(Motion.reduced(context), isTrue);
              return Column(children: [
                RollingNumber(
                    text: value, style: hero, cause: NumberCause.user),
                CheckPop(
                  checked: checked,
                  color: Colors.green,
                  onToggle: () => setState(() => checked = !checked),
                ),
              ]);
            }),
          ),
        )),
      ));
      set(() => value = '₺99,00');
      await tester.pump();
      expect(find.text('₺99,00'), findsOneWidget);
      expect(find.text('₺10,00'), findsNothing);
      await tester.tap(find.byType(CheckPop));
      await tester.pump();
      final scale = tester
          .widget<ScaleTransition>(find.descendant(
              of: find.byType(CheckPop), matching: find.byType(ScaleTransition)))
          .scale
          .value;
      expect(scale, 1.0);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    // The reduced-motion checks of the groups above once more, reached
    // through the app's switch (`reduceMotionProvider`, folded in by
    // `MotionPreference` as `MeridianApp` does) instead of the system flag.
    group('the same group, with the switch on', () {
      late SharedPreferences prefs;

      setUp(() async {
        SharedPreferences.setMockInitialValues(
            {PrefKeys.reduceMotion: 'true'});
        prefs = await SharedPreferences.getInstance();
      });

      /// [child] under the switch; [container] when the test needs its own.
      Widget viaSwitch(Widget child, {ProviderContainer? container}) {
        final tree = app(Consumer(
          builder: (context, ref, _) => MotionPreference(
            reduce: ref.watch(reduceMotionProvider),
            child: Builder(builder: (context) {
              expect(Motion.reduced(context), isTrue);
              return child;
            }),
          ),
        ));
        return container != null
            ? UncontrolledProviderScope(container: container, child: tree)
            : ProviderScope(
                overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
                child: tree,
              );
      }

      testWidgets('RollingNumber: the final value in one frame, every cause',
          (tester) async {
        for (final cause in NumberCause.values) {
          await tester.pumpWidget(viaSwitch(
              RollingNumber(text: '₺10,00', style: hero, cause: cause)));
          await tester.pumpWidget(viaSwitch(
              RollingNumber(text: '₺99,00', style: hero, cause: cause)));
          expect(find.text('₺99,00'), findsOneWidget, reason: '$cause');
          expect(find.text('₺10,00'), findsNothing, reason: '$cause');
          await tester.pumpAndSettle();
          expect(tester.binding.hasScheduledFrame, isFalse, reason: '$cause');
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('CounterPill: the step and the target in one frame',
          (tester) async {
        await expectCounterPillStill(tester, viaSwitch);
      });

      testWidgets('CheckPop: filled at once, no scale', (tester) async {
        var checked = false;
        await tester.pumpWidget(viaSwitch(Center(
          child: StatefulBuilder(
            builder: (context, setState) => CheckPop(
              checked: checked,
              color: Colors.green,
              onToggle: () => setState(() => checked = !checked),
            ),
          ),
        )));
        await tester.tap(find.byType(CheckPop));
        await tester.pump();
        expect(checked, isTrue);
        final scale = tester.widget<ScaleTransition>(find.descendant(
            of: find.byType(CheckPop),
            matching: find.byType(ScaleTransition)));
        expect(scale.scale.value, 1.0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('ProgressRing and PacedProgressBar: a new value in one '
          'frame', (tester) async {
        Widget build(double v) => viaSwitch(Column(children: [
              ProgressRing(value: v, color: Colors.green),
              PacedProgressBar(value: v, color: Colors.green),
            ]));
        await tester.pumpWidget(build(0.2));
        await tester.pumpWidget(build(0.7));
        expect(
          tester.state<ProgressRingState>(find.byType(ProgressRing))
              .paintedValue,
          0.7,
        );
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('Entrance: nothing plays', (tester) async {
        await tester.pumpWidget(viaSwitch(EntranceHost(
          child: Builder(builder: (context) {
            EntranceGate.maybeOf(context)!.openForFirstFrame(context);
            return const Entrance(play: true, child: Text('a'));
          }),
        )));
        final fade = tester.widget<FadeTransition>(find
            .ancestor(of: find.text('a'), matching: find.byType(FadeTransition))
            .first);
        expect(fade.opacity.value, 1.0);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('LoadPhaseSwitcher: the skeleton keeps its 400 ms delay',
          (tester) async {
        Widget switcher(LoadPhase phase) => viaSwitch(SizedBox(
              height: 200,
              child: LoadPhaseSwitcher(
                phase: phase,
                skeleton: (_) => const Text('skeleton'),
                content: (_) => const Text('content'),
                error: (_) => const Text('error'),
              ),
            ));
        await tester.pumpWidget(switcher(LoadPhase.waiting));
        await tester.pump(const Duration(milliseconds: 399));
        expect(find.text('skeleton'), findsNothing);
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();
        expect(find.text('skeleton'), findsOneWidget);
        await tester.pumpWidget(switcher(LoadPhase.content));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('content'), findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('SyncHint: a full second, then a still line',
          (tester) async {
        await tester.pumpWidget(viaSwitch(const SyncHint(active: false)));
        await tester.pumpWidget(viaSwitch(const SyncHint(active: true)));
        await tester.pump(const Duration(milliseconds: 990));
        expect(find.byType(AnimatedOpacity), findsNothing);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(AnimatedOpacity), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpWidget(viaSwitch(const SyncHint(active: false)));
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('CelebrationLayer: no particles; the pill without motion',
          (tester) async {
        late CelebrationController layer;
        await tester.pumpWidget(viaSwitch(CelebrationLayer(
          child: Builder(builder: (context) {
            layer = CelebrationLayer.maybeOf(context)!;
            return const SizedBox(height: 400);
          }),
        )));
        layer.allDone(
            origin: const Offset(100, 200), day: DateTime(2026, 10, 5));
        await tester.pump();
        expect(find.byType(ConfettiBurst), findsNothing);
        await tester.pump();
        final fade = tester.widget<FadeTransition>(find
            .ancestor(
                of: find.text('Hepsi tamam'),
                matching: find.byType(FadeTransition))
            .first);
        expect(fade.opacity.value, 1.0);
        await tester.pump(Motion.milestoneHold);
        await tester.pump();
        expect(find.text('Hepsi tamam'), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });

      testWidgets('a row created here is at full height at once',
          (tester) async {
        final container = ProviderContainer(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);
        container
            .read(recentChangesProvider.notifier)
            .record(DataScope.transactions, 9, ChangeKind.inserted);
        await tester.pumpWidget(
            viaSwitch(const _Rows([9]), container: container));
        expect(tester.getSize(find.byKey(const ValueKey('row-9'))).height, 40);
        expect(tester.binding.transientCallbackCount, 0);
      });
    });
  });

  group('LingeringTodos', () {
    Todo todo(int id) => Todo.fromJson({
          'id': id,
          'title': 'Görev $id',
          'status': 'pending',
          'priority': 'medium',
        });

    test('a lingering todo is put back where it was, done; reopening takes '
        'it out at once', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(lingeringTodosProvider, (_, _) {});
      addTearDown(sub.close);
      final lingering = container.read(lingeringTodosProvider.notifier);
      lingering.add(todo(1), 0);
      expect(
        mergeInto([todo(2)], container.read(lingeringTodosProvider))
            .map((t) => (t.id, t.isDone)),
        [(1, true), (2, false)],
      );
      lingering.remove(1);
      expect(container.read(lingeringTodosProvider).isEmpty, isTrue);
    });

    testWidgets('a checked todo lingers 4 s after the last check, then '
        'collapses with the rest', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(lingeringTodosProvider, (_, _) {});
      addTearDown(sub.close);
      LingeringState state() => container.read(lingeringTodosProvider);
      final lingering = container.read(lingeringTodosProvider.notifier);

      lingering.add(todo(1), 0);
      await tester.pump(const Duration(seconds: 3));
      // A second check restarts the one timer.
      lingering.add(todo(2), 1);
      await tester.pump(const Duration(seconds: 3));
      expect(state().collapsing, isFalse,
          reason: '4 s after the last check, not the first');
      expect(state().todos.keys, unorderedEquals([1, 2]));

      await tester.pump(const Duration(seconds: 1));
      expect(state().collapsing, isTrue);
      expect(state().todos.keys, unorderedEquals([1, 2]));

      await tester.pump(Motion.collapse);
      expect(state().isEmpty, isTrue);
      expect(state().finished, 2);
    });

    test('nothing lingers when no screen shows it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(lingeringTodosProvider.notifier).add(todo(1), 0);
      expect(container.read(lingeringTodosProvider).isEmpty, isTrue);
    });
  });
}

/// Android 14+'s nonlinear text scaling at 200 % (AOSP
/// `FontScaleConverterFactory`, 2.0×): small text doubles, large text
/// grows less — 13 sp → 25 dp, but 56 sp → 61 dp.
class _Android200 extends TextScaler {
  const _Android200();

  static const _sp = [8.0, 10, 12, 14, 18, 20, 24, 30, 100];
  static const _dp = [16.0, 20, 24, 26, 30, 34, 36, 38, 100];

  @override
  double scale(double fontSize) {
    if (fontSize <= _sp.first) return fontSize * 2;
    for (var i = 1; i < _sp.length; i++) {
      if (fontSize <= _sp[i]) {
        final t = (fontSize - _sp[i - 1]) / (_sp[i] - _sp[i - 1]);
        return _dp[i - 1] + (_dp[i] - _dp[i - 1]) * t;
      }
    }
    return fontSize;
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 2;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) =>
      this;
}

/// Rows 40 dp tall, each in [RowMotion], under a [RemovalAwareList].
class _Rows extends StatelessWidget {
  const _Rows(this.ids);

  final List<int> ids;

  @override
  Widget build(BuildContext context) => RemovalAwareList<int>(
        items: ids,
        recordOf: (id) => (scope: DataScope.transactions, id: id),
        itemBuilder: (context, id) => RowMotion(
          key: ValueKey('row-$id'),
          record: (scope: DataScope.transactions, id: id),
          child: SizedBox(height: 40, child: Text('Satır $id')),
        ),
      );
}

/// A session a test signs in and out.
class _SwitchableSession extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();

  void set(SessionState next) => state = next;
}
