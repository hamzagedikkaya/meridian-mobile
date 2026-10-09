/// WP-2 surfaces: NokturnCard, GhostCard, PressableScale, SectionHeader,
/// NokturnRow, LeadingCircle, SettingsRow (design-analysis §4.1–4.4, §4.7).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_card.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_row.dart';
import 'package:meridian_mobile/ui/widgets/pressable_scale.dart';
import 'package:meridian_mobile/ui/widgets/section_header.dart';
import 'package:meridian_mobile/ui/widgets/settings_row.dart';

import '../../support/semantics.dart';
import 'component_harness.dart';

double _scaleOf(WidgetTester tester, Finder finder) {
  final transition = tester.widget<ScaleTransition>(
    find.descendant(of: finder, matching: find.byType(ScaleTransition)),
  );
  return transition.scale.value;
}

void main() {
  setUpComponentFonts();

  group('NokturnCard', () {
    testWidgets('every InkWell inside paints on a Material under the card '
        'colour — the card itself', (tester) async {
      await pumpComponent(
        tester,
        centred(
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                NokturnRow(title: 'Kira', onTap: () {}),
                NokturnRow(title: 'Market', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      final card = find.byType(NokturnCard);
      final cardMaterial = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(cardMaterial.color, isNotNull);
      for (final ink in tester.widgetList(
        find.descendant(of: card, matching: find.byType(InkWell)),
      )) {
        final element = tester.element(find.byWidget(ink));
        final material = element.findAncestorWidgetOfExactType<Material>();
        expect(material, isNotNull);
        // The nearest Material is inside the card (the card's own), not the
        // Scaffold's behind it.
        expect(
          find.descendant(of: card, matching: find.byWidget(material!)),
          findsOneWidget,
        );
      }
    });

    testWidgets('variants pad 20 / 20 / 16 / 4 dp', (tester) async {
      expect(
        NokturnCard.paddingOf(NokCardVariant.standard),
        const EdgeInsets.all(20),
      );
      expect(
        NokturnCard.paddingOf(NokCardVariant.hero),
        const EdgeInsets.all(20),
      );
      expect(
        NokturnCard.paddingOf(NokCardVariant.grid),
        const EdgeInsets.all(16),
      );
      expect(
        NokturnCard.paddingOf(NokCardVariant.list),
        const EdgeInsets.symmetric(vertical: 4),
      );
    });

    testWidgets('a tappable card is one button; tap and long press reach it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      var longs = 0;
      await pumpComponent(
        tester,
        centred(
          NokturnCard(
            onTap: () => taps++,
            onLongPress: () => longs++,
            child: const Text('Tatil fonu'),
          ),
        ),
      );
      final data = semanticsOf('Tatil fonu');
      expect(data.flagsCollection.isButton, isTrue);
      await tester.tap(find.text('Tatil fonu'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Tatil fonu'));
      await tester.pumpAndSettle();
      expect((taps, longs), (1, 1));
      handle.dispose();
    });
  });

  group('GhostCard', () {
    testWidgets('dashed card with its action; "Gizle" hides it', (
      tester,
    ) async {
      var acted = 0;
      await pumpComponent(
        tester,
        centred(
          GhostCard(
            icon: Icons.account_balance_wallet_outlined,
            message: 'İlk hesabını ekle',
            actionLabel: 'Ekle',
            onAction: () => acted++,
            dismissKey: 'test',
          ),
        ),
      );
      await tester.tap(find.text('Ekle'));
      expect(acted, 1);
      final hide = tester.getSize(
        find.ancestor(
          of: find.text('Gizle'),
          matching: find.byType(TextButton),
        ),
      );
      expect(hide.width, greaterThanOrEqualTo(48));
      expect(hide.height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Gizle'));
      await tester.pump();
      expect(find.text('İlk hesabını ekle'), findsNothing);
    });
  });

  group('PressableScale', () {
    Future<void> pump(WidgetTester tester, {bool reduce = false}) =>
        pumpComponent(
          tester,
          centred(
            PressableScale(
              onTap: () {},
              child: const SizedBox(
                width: 200,
                height: 80,
                child: Text('kart'),
              ),
            ),
          ),
          reduceMotion: reduce,
        );

    testWidgets('scales the moment the finger lands, without the tap '
        'timeout', (tester) async {
      await pump(tester);
      final target = find.byType(PressableScale);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(); // the next frame starts the press
      await tester.pump(const Duration(milliseconds: 40));
      expect(_scaleOf(tester, target), lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scaleOf(tester, target), closeTo(0.98, 0.0001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, target), 1.0);
    });

    testWidgets('a 20 ms tap still shows the whole press before releasing', (
      tester,
    ) async {
      await pump(tester);
      final target = find.byType(PressableScale);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      // Finishes pressing in (80 ms) …
      await tester.pump(const Duration(milliseconds: 60));
      expect(_scaleOf(tester, target), closeTo(0.98, 0.0001));
      // … then comes back in 150 ms (from the frame after).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 75));
      expect(_scaleOf(tester, target), allOf(greaterThan(0.98), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_scaleOf(tester, target), 1.0);
    });

    testWidgets('sliding past the touch slop cancels the press', (
      tester,
    ) async {
      await pump(tester);
      final target = find.byType(PressableScale);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scaleOf(tester, target), closeTo(0.98, 0.0001));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scaleOf(tester, target), 1.0);
      await gesture.up();
    });

    testWidgets('reduced motion: never scales', (tester) async {
      await pump(tester, reduce: true);
      final target = find.byType(PressableScale);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      expect(_scaleOf(tester, target), 1.0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gesture.up();
    });

    testWidgets('small controls scale to 0.95', (tester) async {
      expect(const PressableScale.small(child: SizedBox()).pressedScale, 0.95);
    });
  });

  group('SectionHeader', () {
    testWidgets('48 dp with or without actions; the title is a header; '
        '"Tümü ›" and "+" are 48 dp targets', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(
        tester,
        Column(
          children: [
            const SectionHeader('Bütçeler'),
            SectionHeader(
              'Alışkanlıklar',
              count: '2/5',
              progress: 0.4,
              onAdd: () {},
              addTooltip: 'Alışkanlık ekle',
              onSeeAll: () {},
            ),
          ],
        ),
      );
      final plain = find.widgetWithText(SectionHeader, 'Bütçeler');
      final full = find.widgetWithText(SectionHeader, 'Alışkanlıklar');
      expect(tester.getSize(plain).height, 48 + 4);
      expect(tester.getSize(full).height, 48 + 4);
      expect(semanticsOf('Bütçeler').flagsCollection.isHeader, isTrue);
      expect(find.text('Tümü'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      final seeAll = find.ancestor(
        of: find.text('Tümü'),
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(seeAll).height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('Alışkanlık ekle'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('NokturnRow', () {
    testWidgets('at least 64 dp; picker choice gold with a check; disabled '
        'ignores taps', (tester) async {
      var taps = 0;
      await pumpComponent(
        tester,
        Column(
          children: [
            NokturnRow(
              leading: const LeadingCircle.transfer(),
              title: 'Cüzdan → Birikim',
              meta: 'Transfer',
              onTap: () => taps++,
            ),
            NokturnRow(title: 'Market', selected: true, onTap: () => taps++),
            NokturnRow(title: 'Kira', enabled: false, onTap: () => taps++),
          ],
        ),
      );
      for (final row in tester.widgetList(find.byType(NokturnRow))) {
        expect(
          tester.getSize(find.byWidget(row)).height,
          greaterThanOrEqualTo(64),
        );
      }
      final ctx = tester.element(find.text('Market'));
      expect(
        tester.widget<Text>(find.text('Market')).style!.color,
        ctx.nok.gold,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Kira')).style!.color,
        ctx.nok.inkDisabled,
      );
      await tester.tap(find.text('Kira'));
      await tester.tap(find.text('Market'));
      expect(taps, 1);
    });

    testWidgets('one stop that offers its gesture-only actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var postponed = 0;
      await pumpComponent(
        tester,
        NokturnRow(
          title: 'Vergi beyannamesi',
          meta: 'dün · gecikmiş',
          onTap: () {},
          semanticActions: {
            const CustomSemanticsAction(label: 'Yarın'): () => postponed++,
          },
        ),
      );
      final node = find.semantics.byLabel('Vergi beyannamesi\ndün · gecikmiş');
      final data = node.evaluate().single.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      performCustomAction(node.evaluate().single, 'Yarın');
      expect(postponed, 1);
      handle.dispose();
    });

    testWidgets('the title takes a second line only above 1.3x text', (
      tester,
    ) async {
      const long = 'Çok uzun bir başlık ki bir satıra sığmaz, kesinlikle';
      await pumpComponent(tester, const NokturnRow(title: long));
      expect(tester.widget<Text>(find.text(long)).maxLines, 1);
      await pumpComponent(
        tester,
        const NokturnRow(title: long),
        textScale: 2.0,
      );
      expect(tester.widget<Text>(find.text(long)).maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('above 1.3x text a trailing amount goes under the texts, so '
        'the title keeps the width and breaks between words', (tester) async {
      Widget row() => const NokturnRow(
        leading: LeadingCircle.uncategorized(),
        title: 'Market',
        meta: 'Cüzdan · 12:40',
        trailing: Text('−1.234,56 ₺'),
      );
      await pumpComponent(tester, row());
      expect(
        tester.getCenter(find.text('−1.234,56 ₺')).dy,
        lessThan(tester.getBottomLeft(find.text('Cüzdan · 12:40')).dy),
        reason: 'beside the texts at 1.0x',
      );
      await pumpComponent(tester, row(), textScale: 2.0);
      expect(
        tester.getTopLeft(find.text('−1.234,56 ₺')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Cüzdan · 12:40')).dy),
      );
      final title = tester.renderObject<RenderParagraph>(find.text('Market'));
      final boxes = title.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(
        boxes.map((b) => b.top).toSet(),
        hasLength(1),
        reason: '"Market" on one line',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LeadingCircle draws an entity in its tone, a transfer and '
        'no category on plain surfaces', (tester) async {
      await pumpComponent(
        tester,
        const Row(
          children: [
            LeadingCircle(color: Color(0xFF6B8E5A), icon: Icons.eco_outlined),
            LeadingCircle.transfer(),
            LeadingCircle.uncategorized(),
          ],
        ),
      );
      expect(
        tester.getSize(find.byType(LeadingCircle).first),
        const Size(40, 40),
      );
      final ctx = tester.element(find.byType(LeadingCircle).first);
      final transfer = tester.widget<Icon>(
        find.byIcon(Icons.swap_horiz_rounded),
      );
      expect(transfer.color, ctx.nok.inkMid);
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
    });
  });

  group('SettingsRow', () {
    testWidgets('a short value sits at the end; a long one goes under the '
        'title and is never cut', (tester) async {
      await pumpComponent(
        tester,
        Column(
          children: [
            SettingsRow(
              icon: Icons.palette_outlined,
              title: 'Tema',
              value: 'Koyu',
              onTap: () {},
            ),
            SettingsRow(
              icon: Icons.mail_outline,
              title: 'E-posta',
              value: 'hamza.gedikkaya.uzun.adres@example.com',
              onTap: () {},
            ),
          ],
        ),
      );
      final title = tester.getTopLeft(find.text('Tema'));
      final value = tester.getTopLeft(find.text('Koyu'));
      expect(value.dx, greaterThan(title.dx + 100), reason: 'trailing');
      final mailTitle = tester.getBottomLeft(find.text('E-posta'));
      final mail = tester.getTopLeft(
        find.text('hamza.gedikkaya.uzun.adres@example.com'),
      );
      expect(
        mail.dy,
        greaterThanOrEqualTo(mailTitle.dy - 0.5),
        reason: 'below',
      );
      expect(
        tester.getSize(find.byType(SettingsRow).first).height,
        greaterThanOrEqualTo(56),
      );
      expect(
        tester.getSize(find.byType(SettingsRow).last).height,
        greaterThanOrEqualTo(64),
      );
    });

    testWidgets('above 1.3x text every value goes below', (tester) async {
      await pumpComponent(
        tester,
        SettingsRow(
          icon: Icons.palette_outlined,
          title: 'Tema',
          value: 'Koyu',
          onTap: () {},
        ),
        textScale: 1.6,
      );
      expect(
        tester.getTopLeft(find.text('Koyu')).dy,
        greaterThan(tester.getTopLeft(find.text('Tema')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('one button that reads the title with its value', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(
        tester,
        SettingsRow(
          icon: Icons.translate,
          title: 'Dil',
          value: 'Türkçe',
          onTap: () {},
        ),
      );
      final data = semanticsOf('Dil\nTürkçe');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });
}
