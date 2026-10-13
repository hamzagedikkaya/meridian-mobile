/// WP-2 feedback and figures: EmptyState, OfflineBanner(+Slot), StatTile,
/// HeroStat, MoneyGlance, StreakFlame, SwipeAction, StatusBarScrim
/// (design-analysis §4.20, §4.25, §4.27, §4.28, §3.10).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/widgets/empty_state.dart';
import 'package:meridian_mobile/ui/widgets/hero_stat.dart';
import 'package:meridian_mobile/ui/widgets/money_glance.dart';
import 'package:meridian_mobile/ui/widgets/nok_chip.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_row.dart';
import 'package:meridian_mobile/ui/widgets/offline_banner.dart';
import 'package:meridian_mobile/ui/widgets/stat_tile.dart';
import 'package:meridian_mobile/ui/widgets/status_bar_scrim.dart';
import 'package:meridian_mobile/ui/widgets/streak_flame.dart';
import 'package:meridian_mobile/ui/widgets/swipe_action.dart';

import '../../support/semantics.dart';
import 'component_harness.dart';

void main() {
  setUpComponentFonts();

  group('EmptyState', () {
    testWidgets('page: circle, title, body, a filled primary, a text '
        'secondary and starter chips — within 280 dp', (tester) async {
      var created = 0;
      await pumpComponent(
        tester,
        EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'İlk alışkanlığını ekle',
          subtitle: 'Küçük başla: günde bir kez yeter.',
          actionLabel: 'Alışkanlık ekle',
          onAction: () => created++,
          secondaryLabel: 'Arşivi gör',
          onSecondary: () {},
          chips: const [
            NokChip(label: 'Su iç'),
            NokChip(label: 'Oku'),
          ],
        ),
      );
      expect(
        find.widgetWithText(FilledButton, 'Alışkanlık ekle'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Arşivi gör'), findsOneWidget);
      expect(find.byType(NokChip), findsNWidgets(2));
      expect(
        tester.getSize(find.byType(Column).first).width,
        lessThanOrEqualTo(280),
      );
      await tester.tap(find.text('Alışkanlık ekle'));
      expect(created, 1);
    });

    testWidgets('inline, all done and error read their own words', (
      tester,
    ) async {
      var retried = 0;
      await pumpComponent(
        tester,
        Column(
          children: [
            const EmptyState.inline(
              icon: Icons.event_available_outlined,
              message: 'Bugün etkinlik yok',
            ),
            const EmptyState.allDone(),
            Expanded(child: EmptyState.error(onRetry: () => retried++)),
          ],
        ),
      );
      expect(find.text('Bugün etkinlik yok'), findsOneWidget);
      expect(find.text('Hepsi tamam'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.text('Sunucuya ulaşılamıyor'), findsOneWidget);
      expect(
        find.text('Wi-Fi veya Tailscale bağlantını kontrol et'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tekrar dene'));
      expect(retried, 1);
    });

    testWidgets('no overflow at 200 % text', (tester) async {
      await pumpComponent(
        tester,
        SingleChildScrollView(
          child: EmptyState(
            title: 'Henüz işlem yok',
            subtitle: 'İlk harcamanı ya da gelirini ekle.',
            actionLabel: 'İşlem ekle',
            onAction: () {},
          ),
        ),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('OfflineBanner', () {
    testWidgets('44 dp at least, a live region, a 48 dp retry', (tester) async {
      final handle = tester.ensureSemantics();
      var retried = 0;
      await pumpComponent(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: OfflineBanner(
            lastUpdated: DateTime(2026, 10, 4, 12, 40),
            onRetry: () => retried++,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(OfflineBanner)).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      final retry = find.ancestor(
        of: find.text('Tekrar dene'),
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      final live = tester.getSemantics(find.byType(OfflineBanner));
      expect(live.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      await tester.tap(retry);
      expect(retried, 1);
      handle.dispose();
    });

    for (final (locale, scale) in [
      (const Locale('tr'), 1.5),
      (const Locale('tr'), 2.0),
      (const Locale('en'), 2.0),
    ]) {
      testWidgets('at ${scale}x text (${locale.languageCode}) the whole '
          'message shows — the time included — with the retry under it', (
        tester,
      ) async {
        await pumpComponent(
          tester,
          Align(
            alignment: Alignment.topCenter,
            child: OfflineBanner(
              lastUpdated: DateTime(2026, 10, 4, 12, 40),
              onRetry: () {},
            ),
          ),
          textScale: scale,
          locale: locale,
        );
        final message = find.textContaining('12:40');
        expect(message, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
          isFalse,
        );
        final retry = find.byType(TextButton);
        expect(
          tester.getTopLeft(retry).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(message).dy),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the slot grows it in; reduced motion: in one frame', (
      tester,
    ) async {
      Widget slot(bool shown) => Align(
        alignment: Alignment.topCenter,
        child: OfflineBannerSlot(
          banner: shown
              ? OfflineBanner(lastUpdated: DateTime(2026), onRetry: () {})
              : null,
        ),
      );
      await pumpComponent(tester, slot(false));
      await pumpComponent(tester, slot(true));
      await tester.pump(const Duration(milliseconds: 100));
      final growing = tester.getSize(find.byType(OfflineBannerSlot)).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(find.byType(OfflineBannerSlot)).height;
      expect(growing, lessThan(full));

      await pumpComponent(tester, slot(false), reduceMotion: true);
      await tester.pump();
      await pumpComponent(tester, slot(true), reduceMotion: true);
      await tester.pump();
      expect(tester.getSize(find.byType(OfflineBannerSlot)).height, full);
    });
  });

  group('StatTile', () {
    testWidgets('64 dp at least; three across, two above 1.3x text', (
      tester,
    ) async {
      Widget row() => const Padding(
        padding: EdgeInsets.all(20),
        child: StatTileRow(
          tiles: [
            StatTile(value: '21', label: 'En uzun seri'),
            StatTile(value: '%86', label: 'Bu ay'),
            StatTile(value: '142', label: 'Toplam'),
          ],
        ),
      );
      await pumpComponent(tester, row());
      final first = tester.getRect(find.byType(StatTile).at(0));
      final third = tester.getRect(find.byType(StatTile).at(2));
      expect(first.height, greaterThanOrEqualTo(64));
      expect(third.top, first.top, reason: 'one row of three');

      await pumpComponent(tester, row(), textScale: 2.0);
      final a = tester.getRect(find.byType(StatTile).at(0));
      final c = tester.getRect(find.byType(StatTile).at(2));
      expect(c.top, greaterThan(a.top), reason: 'two columns');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the tiles of a line share one height', (tester) async {
      await pumpComponent(
        tester,
        const Padding(
          padding: EdgeInsets.all(20),
          child: StatTileRow(
            tiles: [
              StatTile(value: '26 Kas', label: 'Bitiş'),
              StatTile(value: '₺1.200', label: 'Hedefe kalan, bu hızla'),
              StatTile(value: '%40', label: 'İlerleme'),
            ],
          ),
        ),
      );
      final heights = [
        for (var i = 0; i < 3; i++)
          tester.getSize(find.byType(StatTile).at(i)).height,
      ];
      expect(heights.toSet(), hasLength(1), reason: '$heights');
      expect(heights.first, greaterThanOrEqualTo(64));
    });
  });

  group('HeroStat', () {
    testWidgets('overline, value, support, footnote and insight in order', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: HeroStat(
            overline: 'BU AY NET',
            value: Text('+₺24.600'),
            support: HeroStatSupport(
              parts: [('Gelir', Text('+₺57.800')), ('Gider', Text('−₺33.200'))],
            ),
            footnote: 'Bu yıl +₺21.200',
            insight: 'Geçen aydan ₺3.100 daha az harcadın.',
          ),
        ),
      );
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('BU AY NET'), lessThan(top('+₺24.600')));
      expect(top('+₺24.600'), lessThan(top('Gelir')));
      expect(top('Gelir'), lessThan(top('Bu yıl +₺21.200')));
      expect(
        top('Bu yıl +₺21.200'),
        lessThan(top('Geçen aydan ₺3.100 daha az harcadın.')),
      );
    });
  });

  group('MoneyGlance', () {
    testWidgets('36 dp drawn, 48 dp target, one button that reads the net', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      await pumpComponent(
        tester,
        centred(
          MoneyGlance(
            netCents: 4275000,
            currency: 'TRY',
            subunitToUnit: 100,
            onTap: () => opened++,
          ),
        ),
      );
      expect(tester.getSize(find.byType(MoneyGlance)).height, 48);
      final pill = find.descendant(
        of: find.byType(MoneyGlance),
        matching: find.byType(Container),
      );
      expect(tester.getSize(pill.first).height, 36);
      final node = find.semantics.byPredicate(
        (n) => n.label.startsWith('Bu ay net'),
      );
      expect(
        node.evaluate().single.getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      final ctx = tester.element(find.byType(MoneyGlance));
      final amount = tester.widget<Text>(find.textContaining('42.750'));
      expect(amount.style!.color, ctx.nok.income);
      expect(find.textContaining(',00'), findsNothing,
          reason: 'a chip drops ",00" by default (§3.7)');
      await tester.tap(find.byType(MoneyGlance));
      await tester.pumpAndSettle();
      expect(opened, 1);
      handle.dispose();
    });

    testWidgets('zero is plain inkMid; no account offers the cash account', (
      tester,
    ) async {
      var started = 0;
      await pumpComponent(
        tester,
        centred(
          Column(
            children: [
              MoneyGlance(
                netCents: 0,
                currency: 'TRY',
                subunitToUnit: 100,
                onTap: () {},
              ),
              MoneyGlance(
                netCents: null,
                currency: 'TRY',
                subunitToUnit: 100,
                onTap: () {},
                onStart: () => started++,
              ),
            ],
          ),
        ),
      );
      final ctx = tester.element(find.byType(MoneyGlance).first);
      // An exact zero is written '₺0' (§3.7: unsigned, no decimals).
      final zero = tester.widget<Text>(find.textContaining('₺0'));
      expect(zero.style!.color, ctx.nok.inkMid);
      await tester.tap(find.text('Nakit hesabıyla başla'));
      await tester.pumpAndSettle();
      expect(started, 1);
    });
  });

  group('StreakFlame', () {
    testWidgets('a flame and the count, read as "12 günlük seri"; a broken '
        'streak shows the record, never a zero', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(
        tester,
        const Column(
          children: [
            StreakFlame(days: 12),
            StreakFlame(days: 0, record: 21),
            StreakFlame(days: 0),
          ],
        ),
      );
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(find.semantics.byLabel('12 günlük seri'), findsOneWidget);
      expect(find.text('Yeni seri · Rekor 21'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      handle.dispose();
    });
  });

  group('SwipeAction', () {
    // The app's own row as the child: it merges its semantics into one
    // node, as every swiped row does.
    Widget list(List<String> rows, Future<bool> Function(String) onDelete) =>
        Builder(
          builder: (context) => ListView(
            children: [
              for (final row in rows)
                SwipeAction(
                  key: ValueKey(row),
                  endToStart: SwipeSpec.delete(
                    context.nok,
                    label: 'Sil',
                    onSwipe: () => onDelete(row),
                  ),
                  child: NokturnRow(title: row, meta: 'Cüzdan', onTap: () {}),
                ),
            ],
          ),
        );

    test('the label reads at 3:1 or better all the way to the threshold, '
        'in both themes', () {
      for (final c in [NokturnColors.dark, NokturnColors.light]) {
        Future<bool> no() async => false;
        final specs = [
          SwipeSpec.complete(c, label: 'Tamamla', onSwipe: no),
          SwipeSpec.postpone(c, label: 'Yarın', onSwipe: no),
          SwipeSpec.delete(c, label: 'Sil', onSwipe: no),
        ];
        for (final spec in specs) {
          for (var i = 0; i <= 100; i++) {
            final t = i / 100;
            final background = spec.backgroundAt(t);
            final mark = spec.markOn(background, ink: c.inkHi);
            // As drawn: the mark at its opacity over the background.
            final drawn = Color.alphaBlend(
              mark.withValues(alpha: SwipeAction.markOpacity(t)),
              background,
            );
            expect(
              SwipeSpec.contrastRatio(drawn, background),
              greaterThanOrEqualTo(3.0),
              reason: '${spec.label} at t=$t',
            );
          }
        }
      }
    });

    testWidgets('exactly one tick when the threshold is crossed, none on the '
        'way back; the label shows all the way; false slides the row back', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var asked = 0;
      await pumpComponent(
        tester,
        list(['Market'], (_) async {
          asked++;
          return false;
        }),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Market')),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(find.text('Sil'), findsOneWidget);
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.text('Market'), findsOneWidget, reason: 'slid back');
      final ticks = calls.where(
        (c) =>
            c.method == 'HapticFeedback.vibrate' &&
            c.arguments == 'HapticFeedbackType.selectionClick',
      );
      expect(ticks.length, 1);
    });

    testWidgets('true takes the row out', (tester) async {
      final rows = ['Market', 'Kira'];
      await pumpComponent(
        tester,
        StatefulBuilder(
          builder: (context, setState) => list(rows, (row) async {
            setState(() => rows.remove(row));
            return true;
          }),
        ),
      );
      await tester.drag(find.text('Market'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Market'), findsNothing);
      expect(find.text('Kira'), findsOneWidget);
    });

    testWidgets('every swipe is a screen-reader action on the row\'s own '
        'node — the one TalkBack focuses', (tester) async {
      final handle = tester.ensureSemantics();
      var deleted = 0;
      await pumpComponent(
        tester,
        list(['Market'], (_) async {
          deleted++;
          return false;
        }),
      );
      // The node TalkBack focuses: the one the row's texts are merged into.
      var node = find.semantics.byLabel(RegExp('Market')).evaluate().single;
      while (node.isMergedIntoParent) {
        node = node.parent!;
      }
      final data = node.getSemanticsData();
      expect(data.label, allOf(contains('Market'), contains('Cüzdan')));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(customActionLabels(node), ['Sil']);
      performCustomAction(node, 'Sil');
      await tester.pumpAndSettle();
      expect(deleted, 1);
      handle.dispose();
    });
  });

  group('StatusBarScrim', () {
    testWidgets('bg under the status bar, then a 24 dp fade; taps pass '
        'through', (tester) async {
      var taps = 0;
      await pumpComponent(
        tester,
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: StatusBarScrim.over(
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(StatusBarScrim)).height, 48);
      await tester.tapAt(const Offset(180, 30));
      expect(taps, 1);
    });
  });
}
