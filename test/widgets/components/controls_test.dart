/// WP-2 controls: PrimaryButton, CollapsingFab, CaptureBar, NokChip,
/// ChoiceWrap, SegmentedPill, ColorSwatchRow, AmountKeypad
/// (design-analysis §4.8–4.14).
library;

import 'dart:async' show unawaited;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/choice_wrap.dart';
import 'package:meridian_mobile/ui/widgets/collapsing_fab.dart';
import 'package:meridian_mobile/ui/widgets/color_swatches.dart';
import 'package:meridian_mobile/ui/widgets/nok_chip.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';
import 'package:meridian_mobile/ui/widgets/segmented_pill.dart';

import 'component_harness.dart';

bool _selected(String label) =>
    semanticsOf(label).flagsCollection.isSelected == Tristate.isTrue;

/// The fill a [NokChip] labelled [label] is drawn with on this frame.
Color _pillColor(WidgetTester tester, String label) {
  final box = tester.renderObject<RenderDecoratedBox>(
    find
        .descendant(
          of: find.widgetWithText(NokChip, label),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as ShapeDecoration).color!;
}

void main() {
  setUpComponentFonts();

  group('PrimaryButton', () {
    Widget host(bool loading, {VoidCallback? onPressed}) => centred(
      PrimaryButton(
        label: 'Kaydet',
        loading: loading,
        onPressed: onPressed ?? () {},
      ),
    );

    testWidgets('52 dp, full width, gold', (tester) async {
      await pumpComponent(tester, host(false));
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, 52);
      expect(size.width, 320);
    });

    testWidgets('a save under 150 ms never shows the spinner; the button '
        'keeps its colour and height', (tester) async {
      await pumpComponent(tester, host(false));
      final before = tester.getSize(find.byType(FilledButton));
      await pumpComponent(tester, host(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Done at 120 ms: back to the label, the spinner never seen.
      await pumpComponent(tester, host(false));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(find.byType(FilledButton)), before);
      // Loading is not disabled: the gold stays.
      await pumpComponent(tester, host(true));
      final ctx = tester.element(find.byType(FilledButton));
      final style = Theme.of(ctx).filledButtonTheme.style!;
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
      expect(style.backgroundColor!.resolve({}), ctx.nok.gold);
    });

    testWidgets('a longer save shows the spinner after 150 ms, at the same '
        'height, and ignores taps', (tester) async {
      var taps = 0;
      await pumpComponent(tester, host(false, onPressed: () => taps++));
      final before = tester.getSize(find.byType(FilledButton));
      await pumpComponent(tester, host(true, onPressed: () => taps++));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(milliseconds: 200));
      final spinner = find.byType(CircularProgressIndicator);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: spinner,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      expect(tester.getSize(find.byType(FilledButton)), before);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('loading reads as a disabled button with its label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, host(true));
      final data = semanticsOf('Kaydet');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('an error grows in under the button', (tester) async {
      await pumpComponent(
        tester,
        centred(const PrimaryButton(label: 'Kaydet', errorText: 'Olmadı')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Olmadı'), findsOneWidget);
    });

    testWidgets('reduced motion: an error takes its place in one frame', (
      tester,
    ) async {
      Widget button(String? error) =>
          centred(PrimaryButton(label: 'Kaydet', errorText: error));
      await pumpComponent(tester, button(null), reduceMotion: true);
      final before = tester.getSize(find.byType(PrimaryButton)).height;
      await pumpComponent(tester, button('Olmadı'), reduceMotion: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Olmadı'), findsOneWidget);
      expect(
        tester.getSize(find.byType(PrimaryButton)).height,
        greaterThan(before),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    double labelOpacity(WidgetTester tester) => tester
        .renderObject<RenderAnimatedOpacity>(
          find
              .ancestor(
                of: find.text('Kaydet'),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity
        .value;

    testWidgets('loading on and off keeps the same button and screen-reader '
        'node; the label fades back in 150 ms', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, host(false));
      final state = tester.state(find.byType(FilledButton));
      final node = tester.getSemantics(find.bySemanticsLabel('Kaydet')).id;

      await pumpComponent(tester, host(true));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.state(find.byType(FilledButton)), same(state));
      expect(tester.getSemantics(find.bySemanticsLabel('Kaydet')).id, node);
      expect(semanticsOf('Kaydet').flagsCollection.isEnabled, Tristate.isFalse);
      expect(labelOpacity(tester), 0);

      // The save failed: the label fades back, the spinner out.
      await pumpComponent(tester, host(false));
      await tester.pump(const Duration(milliseconds: 75));
      expect(labelOpacity(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.pumpAndSettle();
      expect(labelOpacity(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.state(find.byType(FilledButton)), same(state));
      expect(tester.getSemantics(find.bySemanticsLabel('Kaydet')).id, node);
      expect(semanticsOf('Kaydet').flagsCollection.isEnabled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('reduced motion: the spinner and the label swap in one '
        'frame', (tester) async {
      await pumpComponent(tester, host(false), reduceMotion: true);
      await pumpComponent(tester, host(true), reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      expect(labelOpacity(tester), 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pumpComponent(tester, host(false), reduceMotion: true);
      await tester.pump();
      expect(labelOpacity(tester), 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('CollapsingFab', () {
    Widget screen({bool hidden = false}) => CollapsingFabScope(
      child: Scaffold(
        body: ListView.builder(
          itemCount: 60,
          itemBuilder: (_, i) => SizedBox(height: 56, child: Text('$i')),
        ),
        floatingActionButton: CollapsingFab(
          icon: Icons.add_rounded,
          label: 'İşlem',
          onPressed: () {},
          hidden: hidden,
        ),
      ),
    );

    Size fabSize(WidgetTester tester) =>
        tester.getSize(find.byType(FloatingActionButton));

    testWidgets('folds to a 56 dp icon after 24 dp down, opens after 24 dp '
        'up', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, screen(), bare: true);
      final open = fabSize(tester);
      expect(open.height, 56);
      expect(open.width, greaterThan(100));

      await tester.drag(find.byType(ListView), const Offset(0, -20));
      await tester.pumpAndSettle();
      expect(fabSize(tester), open, reason: 'under the threshold');

      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(fabSize(tester), const Size(56, 56));
      // The label is still its name for a screen reader.
      expect(find.semantics.byLabel('İşlem'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(fabSize(tester), open);
      handle.dispose();
    });

    testWidgets('a scroll the app makes does not fold it', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpComponent(
        tester,
        CollapsingFabScope(
          child: Scaffold(
            body: ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 56, child: Text('$i')),
            ),
            floatingActionButton: CollapsingFab(
              icon: Icons.add_rounded,
              label: 'İşlem',
              onPressed: () {},
            ),
          ),
        ),
        bare: true,
      );
      final open = fabSize(tester);
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      unawaited(
        controller.animateTo(
          900,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();
      expect(fabSize(tester), open);
      // The user's own drag still does.
      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(fabSize(tester), const Size(56, 56));
    });

    testWidgets('reduced motion: the fold lands in one frame', (tester) async {
      await pumpComponent(tester, screen(), bare: true, reduceMotion: true);
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pump();
      await tester.pump();
      expect(fabSize(tester), const Size(56, 56));
    });

    testWidgets('hidden: fades and ignores taps', (tester) async {
      await pumpComponent(tester, screen(hidden: true), bare: true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(FloatingActionButton),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
    });

    testWidgets('clearance leaves the last row clear of the FAB', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        Builder(
          builder: (context) {
            expect(CollapsingFab.clearance(context), 88);
            return const SizedBox();
          },
        ),
      );
    });
  });

  group('CaptureBar', () {
    testWidgets('a 52 dp labelled bar: "Hızlı ekle" opens, the secondary '
        'icon is its own 48 dp button', (tester) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      var secondary = 0;
      await pumpComponent(
        tester,
        CaptureBarLayout(
          body: const SizedBox.expand(),
          bar: CaptureBar(
            onOpen: () => opened++,
            label: 'Ekle: görev, harcama, etkinlik…',
            secondaryIcon: Icons.payments_outlined,
            secondaryTooltip: 'İşlem ekle',
            onSecondary: () => secondary++,
          ),
        ),
      );
      final bar = find
          .descendant(
            of: find.byType(CaptureBar),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(bar).height, greaterThanOrEqualTo(52));
      expect(semanticsOf('Hızlı ekle').flagsCollection.isButton, isTrue);
      await tester.tap(find.text('Ekle: görev, harcama, etkinlik…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('İşlem ekle'));
      await tester.pumpAndSettle();
      expect((opened, secondary), (1, 1));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      final ctx = tester.element(find.byType(CaptureBar));
      expect(CaptureBarScope.maybeOf(ctx), isNotNull);
      handle.dispose();
    });

    testWidgets('the main part presses to 0.98; the secondary icon does not '
        'press the bar', (tester) async {
      await pumpComponent(
        tester,
        CaptureBarLayout(
          body: const SizedBox.expand(),
          bar: CaptureBar(
            onOpen: () {},
            label: 'Ekle: görev, harcama, etkinlik…',
            secondaryIcon: Icons.payments_outlined,
            secondaryTooltip: 'İşlem ekle',
            onSecondary: () {},
          ),
        ),
      );
      double scale() => tester
          .widget<ScaleTransition>(
            find.descendant(
              of: find.byType(CaptureBar),
              matching: find.byType(ScaleTransition),
            ),
          )
          .scale
          .value;

      final icon = await tester.startGesture(
        tester.getCenter(find.byTooltip('İşlem ekle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(), 1);
      await icon.up();
      await tester.pumpAndSettle();

      final main = await tester.startGesture(
        tester.getCenter(find.text('Ekle: görev, harcama, etkinlik…')),
      );
      // The press starts on the next frame and takes 80 ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(), closeTo(0.98, 0.001));
      await main.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });
  });

  group('NokChip', () {
    for (final brightness in Brightness.values) {
      testWidgets('36 dp drawn, 48 dp target; selected is told by tick and '
          'edge; contrast and targets pass (${brightness.name})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        var value = 'Aylık';
        await pumpComponent(
          tester,
          StatefulBuilder(
            builder: (context, setState) => centred(
              Wrap(
                spacing: 8,
                children: [
                  for (final label in ['Haftalık', 'Aylık', 'Yıllık'])
                    NokChip(
                      label: label,
                      selected: value == label,
                      exclusive: true,
                      onTap: () => setState(() => value = label),
                    ),
                ],
              ),
            ),
          ),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        final pill = find.descendant(
          of: find.widgetWithText(NokChip, 'Aylık'),
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(pill).height, 36);
        expect(
          tester.getSize(find.widgetWithText(NokChip, 'Aylık')).height,
          48,
        );
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        final ctx = tester.element(pill);
        final decoration =
            tester.widget<AnimatedContainer>(pill).decoration
                as ShapeDecoration;
        expect((decoration.shape as StadiumBorder).side.color, ctx.nok.goldDim);
        expect(_selected('Aylık'), isTrue);
        expect(
          semanticsOf('Aylık').flagsCollection.isInMutuallyExclusiveGroup,
          isTrue,
        );

        await tester.tap(find.text('Yıllık'));
        await tester.pumpAndSettle();
        expect(_selected('Yıllık'), isTrue);
        expect(_selected('Aylık'), isFalse);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('a dropdown chip has its arrow; a disabled one ignores taps', (
      tester,
    ) async {
      var taps = 0;
      await pumpComponent(
        tester,
        centred(
          Column(
            children: [
              NokChip(label: 'Cüzdan', dropdown: true, onTap: () => taps++),
              NokChip(label: 'TRY', enabled: false, onTap: () => taps++),
            ],
          ),
        ),
      );
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      await tester.tap(find.text('TRY'));
      await tester.tap(find.text('Cüzdan'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('reduced motion: the selection lands in one frame', (
      tester,
    ) async {
      Widget chip(bool selected) => centred(
        NokChip(label: 'Aylık', selected: selected, onTap: () {}),
      );
      await pumpComponent(tester, chip(false), reduceMotion: true);
      await pumpComponent(tester, chip(true), reduceMotion: true);
      final ctx = tester.element(find.byType(NokChip));
      expect(_pillColor(tester, 'Aylık'), ctx.nok.goldContainer);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await pumpComponent(tester, chip(false), reduceMotion: true);
      expect(_pillColor(tester, 'Aylık'), ctx.nok.surface2);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('ChoiceWrap', () {
    testWidgets('a single-choice group of NokChips; the chosen one has '
        'nothing to do', (tester) async {
      final handle = tester.ensureSemantics();
      final picked = <String>[];
      await pumpComponent(
        tester,
        centred(
          ChoiceWrap<String>(
            choices: const [Choice('cash', 'Nakit'), Choice('bank', 'Banka')],
            selected: 'cash',
            onChanged: picked.add,
          ),
        ),
      );
      expect(find.byType(NokChip), findsNWidgets(2));
      expect(semanticsOf('Nakit').hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.text('Banka'));
      expect(picked, ['bank']);
      handle.dispose();
    });

    testWidgets('a choice fades to gold in 200 ms and its press eases back, '
        'though the chosen chip stops taking taps', (tester) async {
      var choice = 'cash';
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, setState) => centred(
            ChoiceWrap<String>(
              choices: const [Choice('cash', 'Nakit'), Choice('bank', 'Banka')],
              selected: choice,
              onChanged: (v) => setState(() => choice = v),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(ChoiceWrap<String>));
      final from = ctx.nok.surface2;
      final to = ctx.nok.goldContainer;
      double scale() => tester
          .widget<ScaleTransition>(
            find.descendant(
              of: find.widgetWithText(NokChip, 'Banka'),
              matching: find.byType(ScaleTransition),
            ),
          )
          .scale
          .value;

      await tester.tap(find.text('Banka'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = _pillColor(tester, 'Banka');
      expect(mid, isNot(from));
      expect(mid, isNot(to), reason: 'still fading at 60 ms');
      expect(scale(), lessThan(1), reason: 'the press eases back');
      await tester.pumpAndSettle();
      expect(_pillColor(tester, 'Banka'), to);
      expect(scale(), 1);
    });
  });

  group('SegmentedPill', () {
    Widget pill(String selected, ValueChanged<String> onChanged) => centred(
      SegmentedPill<String>(
        options: const [
          ('expense', 'Gider'),
          ('income', 'Gelir'),
          ('transfer', 'Transfer'),
        ],
        selected: selected,
        onChanged: onChanged,
      ),
    );

    for (final brightness in Brightness.values) {
      testWidgets('40 dp rail in a 48 dp target, equal segments, a 32 dp '
          'thumb with an edge; guidelines pass (${brightness.name})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        var value = 'expense';
        await pumpComponent(
          tester,
          StatefulBuilder(
            builder: (context, setState) =>
                pill(value, (v) => setState(() => value = v)),
          ),
          brightness: brightness,
        );
        expect(tester.getSize(find.byType(SegmentedPill<String>)).height, 48);
        final rail = find.descendant(
          of: find.byType(SegmentedPill<String>),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is ShapeDecoration,
          ),
        );
        expect(tester.getSize(rail.first).height, 40);
        final thumb = find.descendant(
          of: find.byType(AnimatedPositioned),
          matching: find.byType(DecoratedBox),
        );
        expect(tester.getSize(thumb).height, 32);
        final ctx = tester.element(thumb);
        final shape =
            (tester.widget<DecoratedBox>(thumb).decoration as ShapeDecoration)
                    .shape
                as StadiumBorder;
        expect(shape.side.color, ctx.nok.goldDim);

        final gider = tester.getSize(find.bySemanticsLabel('Gider'));
        final transfer = tester.getSize(find.bySemanticsLabel('Transfer'));
        expect(gider.width, transfer.width);
        expect(gider.height, 48);
        expect(_selected('Gider'), isTrue);
        expect(
          semanticsOf('Gider').flagsCollection.isInMutuallyExclusiveGroup,
          isTrue,
        );

        // The label lies inside its own target.
        expect(find.text('Transfer').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        expect(value, 'transfer');
        expect(_selected('Transfer'), isTrue);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('the thumb slides in 250 ms; under reduced motion it is '
        'there in one frame', (tester) async {
      await pumpComponent(tester, pill('expense', (_) {}));
      final start = tester.getTopLeft(find.byType(AnimatedPositioned)).dx;
      await pumpComponent(tester, pill('transfer', (_) {}));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getTopLeft(find.byType(AnimatedPositioned)).dx;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.byType(AnimatedPositioned)).dx;
      expect(mid, allOf(greaterThan(start), lessThan(end)));

      await pumpComponent(tester, pill('expense', (_) {}), reduceMotion: true);
      await pumpComponent(tester, pill('transfer', (_) {}), reduceMotion: true);
      await tester.pump();
      expect(tester.getTopLeft(find.byType(AnimatedPositioned)).dx, end);
    });

    testWidgets('a drag along the rail picks where it is let go', (
      tester,
    ) async {
      final picked = <String>[];
      await pumpComponent(tester, pill('expense', picked.add));
      await tester.dragFrom(
        tester.getCenter(find.text('Gider')),
        tester.getCenter(find.text('Transfer')) -
            tester.getCenter(find.text('Gider')),
      );
      await tester.pumpAndSettle();
      expect(picked, ['transfer']);
    });

    testWidgets('no overflow at 200 % text', (tester) async {
      await pumpComponent(tester, pill('expense', (_) {}), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('ColorSwatchRow', () {
    testWidgets('36 dp swatches in 48 dp targets, named by colour; the '
        'chosen one has a ring and a tick', (tester) async {
      final handle = tester.ensureSemantics();
      var hex = '#D4A853';
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, setState) => centred(
            ColorSwatchRow(
              selected: hex,
              onChanged: (v) => setState(() => hex = v),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('Adaçayı')),
        const Size(48, 48),
      );
      expect(_selected('Altın'), isTrue);
      await tester.tap(find.bySemanticsLabel('Adaçayı'));
      await tester.pump();
      expect(hex, '#6B8E5A');
      expect(_selected('Adaçayı'), isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    test('the next colour follows the last one picked', () {
      expect(nextSwatch(null), recordSwatches.first);
      expect(nextSwatch('#D4A853'), '#6B8E5A');
      expect(nextSwatch('#8B5A00'), '#D4A853');
    });
  });

  group('AmountKeypad', () {
    testWidgets('keys are 56 dp on a 780 dp screen and 64 dp on a taller '
        'one; digits in Fraunces', (tester) async {
      Widget keypad() =>
          AmountKeypad(onDigit: (_) {}, onDot: () {}, onBackspace: () {});
      await pumpComponent(tester, keypad());
      expect(tester.getSize(find.bySemanticsLabel('1')).height, 56);
      await pumpComponent(tester, keypad(), size: const Size(360, 900));
      expect(tester.getSize(find.bySemanticsLabel('1')).height, 64);
      expect(tester.widget<Text>(find.text('1')).style!.fontFamily, 'Fraunces');
    });

    testWidgets('a refused digit shakes the amount, then it settles; not '
        'under reduced motion', (tester) async {
      Widget shake(int n, {bool reduce = false}) =>
          RejectShake(trigger: n, child: const Text('₺21.474.836,47'));
      await pumpComponent(tester, centred(shake(0)));
      final rest = tester.getTopLeft(find.text('₺21.474.836,47'));
      await pumpComponent(tester, centred(shake(1)));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getTopLeft(find.text('₺21.474.836,47')), isNot(rest));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('₺21.474.836,47')).dx,
        closeTo(rest.dx, 0.01),
      );

      await pumpComponent(tester, centred(shake(2)), reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getTopLeft(find.text('₺21.474.836,47')), rest);
    });
  });
}
