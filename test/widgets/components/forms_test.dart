/// WP-2 form parts: AmountField and its keypad sheet, FormFieldBox,
/// FormInlineError and SheetStepSwitcher (design-analysis §4.11, §4.15).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/widgets/amount_field.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/form_scaffold.dart';
import 'package:meridian_mobile/ui/widgets/nok_sheet.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';

import 'component_harness.dart';

const _label = 'Açılış bakiyesi';
const _cents = 123456789;

/// The share of its natural size the field's amount is drawn at.
double _amountScale(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.descendant(
      of: find.byType(AmountField),
      matching: find.byType(FittedBox),
    ),
  );
  final text = tester.renderObject<RenderBox>(
    find.descendant(
      of: find.byType(AmountField),
      matching: find.byType(Text),
    ).last,
  );
  return box.size.height / text.size.height;
}

/// The border colour of the [FormFieldBox] under [of].
Color _edge(WidgetTester tester, Finder of) {
  final material = tester.widget<Material>(
    find.descendant(of: of, matching: find.byType(Material)).first,
  );
  return (material.shape! as RoundedRectangleBorder).side.color;
}

void main() {
  setUpComponentFonts();

  group('AmountField', () {
    Widget field({String? error, String? helper, ValueChanged<int>? onChanged}) =>
        Padding(
          padding: const EdgeInsets.all(20),
          child: AmountField(
            label: _label,
            minorUnits: _cents,
            currency: 'TRY',
            subunitToUnit: 100,
            onChanged: onChanged ?? (_) {},
            errorText: error,
            helperText: helper,
          ),
        );

    testWidgets('52 dp at least; label and amount on one line; one button '
        'that reads both', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, field());
      final shown = formatMoney(_cents, 'TRY', 100);
      expect(
        tester.getSize(find.byType(FormFieldBox)).height,
        greaterThanOrEqualTo(52),
      );
      expect(
        tester.getCenter(find.text(_label)).dy,
        closeTo(tester.getCenter(find.text(shown)).dy, 1),
      );
      expect(_amountScale(tester), closeTo(1, 0.001));
      final data = semanticsOf('$_label, $shown');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('at 200 % text the label goes above and the amount keeps '
        'its size', (tester) async {
      await pumpComponent(tester, field(), textScale: 2);
      final shown = formatMoney(_cents, 'TRY', 100);
      expect(
        tester.getTopLeft(find.text(shown)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text(_label)).dy),
      );
      expect(_amountScale(tester), greaterThan(0.95));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a helper reads under the field; an error turns the edge '
        'red and is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, field(helper: 'Bugünkü bakiye'));
      final ctx = tester.element(find.byType(AmountField));
      expect(find.text('Bugünkü bakiye'), findsOneWidget);
      expect(_edge(tester, find.byType(FormFieldBox)), ctx.nok.inkDisabled);
      expect(
        semanticsOf('Bugünkü bakiye').flagsCollection.isLiveRegion,
        isFalse,
      );

      await pumpComponent(tester, field(error: 'Bir tutar gir'));
      expect(_edge(tester, find.byType(FormFieldBox)), ctx.nok.error);
      expect(semanticsOf('Bir tutar gir').flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('a tap opens the keypad sheet; "Tamam" hands the amount '
        'back', (tester) async {
      int? changed;
      await pumpComponent(tester, field(onChanged: (v) => changed = v));
      await tester.tap(find.byType(FormFieldBox));
      await tester.pumpAndSettle();
      expect(find.byType(AmountKeypad), findsOneWidget);
      // "Tamam" is the sheet's 52 dp primary button.
      final done = find.widgetWithText(PrimaryButton, 'Tamam');
      expect(
        tester.getSize(find.descendant(of: done, matching: find.byType(FilledButton))).height,
        52,
      );
      await tester.tap(find.bySemanticsLabel('Son rakamı sil'));
      await tester.tap(find.bySemanticsLabel('5'));
      await tester.pump();
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(changed, 123456785);
    });
  });

  group('showAmountSheet', () {
    Future<void> open(WidgetTester tester, {double textScale = 1}) async {
      await pumpComponent(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAmountSheet(
                context,
                title: _label,
                // ₺21.474.836,00: one more digit passes the limit.
                initial: 2147483600,
                currency: 'TRY',
                subunitToUnit: 100,
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
        textScale: textScale,
        size: const Size(360, 900),
      );
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('at ${scale}x text the limit note shows without moving the '
          'keypad, and the amount is a live region', (tester) async {
        final handle = tester.ensureSemantics();
        await open(tester, textScale: scale);
        final key = find.bySemanticsLabel('1');
        final before = tester.getTopLeft(key);
        final max = formatMoney(AmountDraft.maxMinorUnits, 'TRY', 100);
        expect(find.textContaining(max), findsNothing);

        await tester.tap(find.bySemanticsLabel('5'));
        await tester.pumpAndSettle();
        expect(find.text('En fazla $max girilebilir'), findsOneWidget);
        expect(tester.getTopLeft(key), before);
        expect(tester.takeException(), isNull);

        final amount = find.ancestor(
          of: find.byType(RejectShake),
          matching: find.byType(Semantics),
        );
        expect(
          tester
              .getSemantics(amount.first)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        handle.dispose();
      });
    }
  });

  group('FormFieldBox', () {
    testWidgets('52 dp at least, an inkDisabled edge — error when it has '
        'one — and taps reach it', (tester) async {
      var taps = 0;
      Widget box({bool error = false}) => centred(
        FormFieldBox(
          onTap: () => taps++,
          hasError: error,
          child: const Text('Kategori'),
        ),
      );
      await pumpComponent(tester, box());
      final ctx = tester.element(find.byType(FormFieldBox));
      expect(
        tester.getSize(find.byType(FormFieldBox)).height,
        greaterThanOrEqualTo(52),
      );
      expect(_edge(tester, find.byType(FormFieldBox)), ctx.nok.inkDisabled);
      await tester.tap(find.text('Kategori'));
      expect(taps, 1);

      await pumpComponent(tester, box(error: true));
      expect(_edge(tester, find.byType(FormFieldBox)), ctx.nok.error);

      // Larger text makes it taller, never clipped.
      await pumpComponent(tester, box(), textScale: 2);
      expect(
        tester.getSize(find.byType(FormFieldBox)).height,
        greaterThan(52),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FormPickerRow', () {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('at $scale× text on a 360 dp phone the value keeps a '
          'readable width', (tester) async {
        await pumpComponent(
          tester,
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              FormPickerRow(
                icon: Icons.repeat_rounded,
                label: 'Bağlı alışkanlık',
                value: 'Sabah koşusu',
                onTap: () {},
              ),
              FormPickerRow(
                icon: Icons.event_rounded,
                label: 'Sonraki ödeme',
                value: '15 Ekim 2026',
                onTap: () {},
              ),
            ],
          ),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        for (final value in ['Sabah koşusu', '15 Ekim 2026']) {
          final size = tester.getSize(find.text(value));
          // Never a letter-wide column: at least a third of the row, and
          // no taller than two lines of it.
          expect(size.width, greaterThan(320 / 3), reason: value);
          expect(size.height, lessThan(3 * 20 * scale), reason: value);
        }
      });
    }
  });

  group('FormInlineError', () {
    Widget host(String? error) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [const SizedBox(height: 52), FormInlineError(error)],
    );

    testWidgets('grows into place in 150 ms and is a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, host(null));
      expect(tester.getSize(find.byType(FormInlineError)).height, 0);

      await pumpComponent(tester, host('Bir ad gir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final growing = tester.getSize(find.byType(FormInlineError)).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(find.byType(FormInlineError)).height;
      expect(growing, allOf(greaterThan(0), lessThan(full)));
      final ctx = tester.element(find.text('Bir ad gir'));
      expect(
        tester.widget<Text>(find.text('Bir ad gir')).style!.color,
        ctx.nok.error,
      );
      expect(semanticsOf('Bir ad gir').flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('reduced motion: there in one frame', (tester) async {
      await pumpComponent(tester, host(null), reduceMotion: true);
      await pumpComponent(tester, host('Bir ad gir'), reduceMotion: true);
      await tester.pump();
      final height = tester.getSize(find.byType(FormInlineError)).height;
      expect(height, greaterThan(0));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(FormInlineError)).height, height);
    });
  });

  group('SheetStepSwitcher', () {
    Widget step(int n, {bool reverse = false}) => SheetStepSwitcher(
      reverse: reverse,
      child: SizedBox(
        key: ValueKey(n),
        height: 200,
        child: Text('Adım $n'),
      ),
    );

    testWidgets('the next step slides in over 300 ms; the old one is gone '
        'after', (tester) async {
      await pumpComponent(tester, step(1));
      await pumpComponent(tester, step(2));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Adım 1'), findsOneWidget);
      expect(find.text('Adım 2'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Adım 1'), findsNothing);
      expect(find.text('Adım 2'), findsOneWidget);
    });

    testWidgets('reduced motion: the step changes in one frame', (
      tester,
    ) async {
      await pumpComponent(tester, step(1), reduceMotion: true);
      await pumpComponent(tester, step(2, reverse: true), reduceMotion: true);
      await tester.pump();
      expect(find.text('Adım 1'), findsNothing);
      expect(find.text('Adım 2'), findsOneWidget);
    });
  });
}
