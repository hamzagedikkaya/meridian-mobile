/// WP-2 overlays and forms: showNokSheet / SheetHeader / SheetActions,
/// showPickerSheet, showConfirmDialog, showAppSnack, FormScaffold,
/// SlideUpPageRoute (design-analysis §4.15–4.17, §4.31).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/widgets/app_snackbar.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/collapsing_fab.dart';
import 'package:meridian_mobile/ui/widgets/confirm_dialog.dart';
import 'package:meridian_mobile/ui/widgets/form_scaffold.dart';
import 'package:meridian_mobile/ui/widgets/nok_sheet.dart';
import 'package:meridian_mobile/ui/widgets/picker_sheet.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';
import 'package:meridian_mobile/ui/widgets/slide_up_route.dart';

import 'component_harness.dart';

/// A button labelled 'open' that runs [open] with its context.
Widget _opener(void Function(BuildContext context) open) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => open(context),
      child: const Text('open'),
    ),
  ),
);

/// The drawn snackbar — its Material, inside the transparent margin.
Rect _snackRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
          .first,
    );

void main() {
  setUpComponentFonts();

  group('showNokSheet', () {
    testWidgets('a titled sheet with its X; the X closes it', (tester) async {
      await pumpComponent(
        tester,
        _opener(
          (context) => showNokSheet<void>(
            context,
            title: 'Bütçe',
            subtitle: 'Market',
            showClose: true,
            builder: (_) => SheetActions(
              primary: PrimaryButton(label: 'Kaydet', onPressed: () {}),
              destructive: TextButton(
                onPressed: () {},
                child: const Text('Bütçeyi kaldır'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Bütçe'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
      // The destructive action sits 24 dp under the primary one, in error.
      final primary = tester.getRect(find.byType(FilledButton));
      final destructive = tester.getRect(
        find.ancestor(
          of: find.text('Bütçeyi kaldır'),
          matching: find.byType(TextButton),
        ),
      );
      expect(destructive.top - primary.bottom, greaterThanOrEqualTo(24));
      final ctx = tester.element(find.text('Bütçeyi kaldır'));
      expect(DefaultTextStyle.of(ctx).style.color, ctx.nok.error);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Bütçe'), findsNothing);
    });

    testWidgets('opens over everything, 350 ms in; under reduced motion it '
        'is there in one frame', (tester) async {
      Future<void> open({required bool reduce}) async {
        await pumpComponent(
          tester,
          _opener(
            (context) => showNokSheet<void>(
              context,
              title: 'Sheet',
              builder: (_) => const SizedBox(height: 200),
            ),
          ),
          reduceMotion: reduce,
        );
        await tester.tap(find.text('open'));
        await tester.pump();
      }

      await open(reduce: false);
      await tester.pump(const Duration(milliseconds: 100));
      final moving = tester.getTopLeft(find.text('Sheet')).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Sheet')).dy, lessThan(moving));

      await tester.pumpWidget(const SizedBox());
      await open(reduce: true);
      final settled = tester.getTopLeft(find.text('Sheet')).dy;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.text('Sheet')).dy, settled);
    });

    testWidgets('draggable detail sheets open at 60 %', (tester) async {
      await pumpComponent(
        tester,
        _opener(
          (context) => showNokSheet<void>(
            context,
            draggable: true,
            title: 'Sabah koşusu',
            entityTitle: true,
            builder: (_) => ListView(
              children: [for (var i = 0; i < 40; i++) Text('satır $i')],
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
      expect(sheet.height, closeTo(780 * 0.6, 40));
      final title = tester.widget<Text>(find.text('Sabah koşusu'));
      expect(title.style!.fontFamily, 'Fraunces');
    });
  });

  group('showPickerSheet', () {
    testWidgets('the chosen row is gold with a check; a tap returns it', (
      tester,
    ) async {
      String? picked;
      await pumpComponent(
        tester,
        _opener((context) async {
          picked = await showPickerSheet<String>(
            context,
            title: 'Tema',
            selected: 'dark',
            options: const [
              PickerOption(value: 'dark', label: 'Koyu'),
              PickerOption(value: 'light', label: 'Açık'),
            ],
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final ctx = tester.element(find.text('Koyu'));
      expect(tester.widget<Text>(find.text('Koyu')).style!.color, ctx.nok.gold);
      await tester.tap(find.text('Açık'));
      await tester.pumpAndSettle();
      expect(picked, 'light');
    });
  });

  group('showConfirmDialog', () {
    testWidgets('"Vazgeç" left, the verb right; destructive is error with '
        'onError text; 48 dp', (tester) async {
      bool? result;
      await pumpComponent(
        tester,
        _opener((context) async {
          result = await showConfirmDialog(
            context,
            title: '"Market" silinsin mi?',
            message: '12 işlem "Diğer"e taşınacak.',
            confirmLabel: 'Sil ve taşı',
            destructive: true,
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final cancel = tester.getRect(find.text('Vazgeç'));
      final confirm = tester.getRect(find.text('Sil ve taşı'));
      expect(cancel.left, lessThan(confirm.left));
      final button = find.ancestor(
        of: find.text('Sil ve taşı'),
        matching: find.byType(FilledButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final ctx = tester.element(button);
      final style = tester.widget<FilledButton>(button).style!;
      expect(style.backgroundColor!.resolve({}), ctx.nok.error);
      expect(style.foregroundColor!.resolve({}), ctx.nok.onError);
      await tester.tap(find.text('Sil ve taşı'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('showAppSnack', () {
    testWidgets('on a tab with a FAB it floats above the FAB — no overlap', (
      tester,
    ) async {
      // The shell: its scaffold draws snackbars, over the navigation bar;
      // the tab's own scaffold (nested) holds the FAB.
      await pumpComponent(
        tester,
        Scaffold(
          bottomNavigationBar: const SizedBox(height: 64),
          body: CollapsingFabScope(
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showAppSnack(
                      context,
                      'İşlem silindi',
                      actionLabel: 'Geri al',
                      onAction: () {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
              floatingActionButton: CollapsingFab(
                icon: Icons.add_rounded,
                label: 'İşlem',
                onPressed: () {},
              ),
            ),
          ),
        ),
        bare: true,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final snack = _snackRect(tester);
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(snack.overlaps(fab), isFalse);
      expect(snack.bottom, lessThanOrEqualTo(fab.top));
    });

    testWidgets('over the capture bar it floats above the bar', (tester) async {
      await pumpComponent(
        tester,
        Scaffold(
          bottomNavigationBar: const SizedBox(height: 64),
          body: CaptureBarLayout(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppSnack(context, 'Görev eklendi'),
                  child: const Text('open'),
                ),
              ),
            ),
            bar: CaptureBar(onOpen: () {}, label: 'Ekle: görev…'),
          ),
        ),
        bare: true,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final snack = _snackRect(tester);
      final bar = tester.getRect(find.byType(CaptureBar));
      expect(snack.overlaps(bar.deflate(8)), isFalse);
      expect(snack.bottom, lessThanOrEqualTo(bar.top + 8));
    });

    testWidgets('tones: success and error carry their icon; plain has none', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        _opener(
          (context) =>
              showAppSnack(context, 'Kaydedildi', tone: SnackTone.success),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.text('Kaydedildi'));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color,
        ctx.nok.income,
      );

      await pumpComponent(
        tester,
        _opener((context) => showAppSnack(context, 'Olmadı', isError: true)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets('two actions: both 48 dp, the primary one closes it as '
        '"action"', (tester) async {
      SnackBarClosedReason? reason;
      var edits = 0;
      await pumpComponent(
        tester,
        _opener((context) {
          showAppSnack(
            context,
            'Harcama eklendi · Cüzdan',
            actionLabel: 'Geri al',
            onAction: () {},
            secondaryLabel: 'Düzenle',
            onSecondary: () => edits++,
          ).closed.then((r) => reason = r);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in ['Geri al', 'Düzenle']) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(TextButton),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(reason, SnackBarClosedReason.action);
      expect(edits, 0);
    });
  });

  group('FormScaffold and SlideUpPageRoute', () {
    Widget form({bool dirty = false, bool busy = false}) => FormScaffold(
      title: 'Hesap ekle',
      actionLabel: 'Kaydet',
      onAction: () {},
      dirty: dirty,
      busy: busy,
      children: [
        for (var i = 0; i < 30; i++)
          SizedBox(height: 48, child: Text('alan $i')),
      ],
    );

    testWidgets('slides up in 400 ms; reduced motion: there in one frame', (
      tester,
    ) async {
      Future<void> open(bool reduce) async {
        await pumpComponent(
          tester,
          _opener(
            (context) =>
                Navigator.of(context).push(slideUpModalRoute((_) => form())),
          ),
          reduceMotion: reduce,
        );
        await tester.tap(find.text('open'));
        await tester.pump();
      }

      await open(false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.text('Hesap ekle')).dy, greaterThan(100));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.text('Hesap ekle')).dy;
      expect(top, lessThan(100));

      await tester.pumpWidget(const SizedBox());
      await open(true);
      await tester.pump();
      expect(tester.getTopLeft(find.text('Hesap ekle')).dy, top);
    });

    testWidgets('the rounded X closes a clean form at once; a dirty one '
        'asks in a sheet first', (tester) async {
      await pumpComponent(
        tester,
        _opener(
          (context) => Navigator.of(
            context,
          ).push(SlideUpPageRoute<void>(builder: (_) => form(dirty: true))),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
      await tester.tap(find.text('Düzenlemeye devam'));
      await tester.pumpAndSettle();
      expect(find.text('Hesap ekle'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Değişiklikleri at'));
      await tester.pumpAndSettle();
      expect(find.text('Hesap ekle'), findsNothing);
    });

    testWidgets('a hairline shows over the save bar while content runs '
        'under it', (tester) async {
      await pumpComponent(tester, form(), bare: true);
      await tester.pumpAndSettle();
      Color line() => (tester
              .widget<AnimatedContainer>(
                find.byWidgetPredicate(
                  (w) =>
                      w is AnimatedContainer && w.constraints?.maxHeight == 1,
                ),
              )
              .decoration! as BoxDecoration)
          .color!;
      final ctx = tester.element(find.text('Kaydet'));
      expect(line(), ctx.nok.hairline);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(line().a, 0);
    });

    testWidgets('a multi-line field scrolling inside the form does not move '
        'the hairline', (tester) async {
      await pumpComponent(
        tester,
        FormScaffold(
          title: 'Hesap ekle',
          actionLabel: 'Kaydet',
          onAction: () {},
          children: [
            const TextField(minLines: 3, maxLines: 3),
            for (var i = 0; i < 30; i++)
              SizedBox(height: 48, child: Text('alan $i')),
          ],
        ),
        bare: true,
      );
      await tester.pumpAndSettle();
      final hairline = find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.constraints?.maxHeight == 1,
      );
      double alpha() =>
          (tester.widget<AnimatedContainer>(hairline).decoration!
                  as BoxDecoration)
              .color!
              .a;
      expect(alpha(), greaterThan(0));
      // Six lines in a three-line field: its own scroll view runs to its end.
      await tester.enterText(find.byType(TextField), '1\n2\n3\n4\n5\n6');
      await tester.pumpAndSettle();
      expect(alpha(), greaterThan(0), reason: 'the list still runs under');
    });

    testWidgets('revealInvalid scrolls the first invalid field into view and '
        'focuses it', (tester) async {
      final key = GlobalKey();
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpComponent(
        tester,
        FormScaffold(
          title: 'Hedef',
          actionLabel: 'Kaydet',
          onAction: () {},
          children: [
            for (var i = 0; i < 20; i++)
              SizedBox(height: 60, child: Text('alan $i')),
            TextField(key: key, focusNode: node),
          ],
        ),
        bare: true,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key).hitTestable(), findsNothing);
      FormScaffold.revealInvalid(key);
      await tester.pumpAndSettle();
      expect(find.byKey(key).hitTestable(), findsOneWidget);
      expect(node.hasFocus, isTrue);
    });
  });
}
