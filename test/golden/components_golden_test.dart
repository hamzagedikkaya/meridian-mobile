@Tags(['golden'])
/// The WP-2 component gallery (design-analysis §9 WP-2): every surface and
/// control component in its states, dark and light, at 1.0× and 2.0× text.
///
/// Shot with `golden_harness.dart`'s clock, fonts and host; the pages are
/// taller than a phone so a whole gallery fits one image. Owned by WP-2.
///
///     flutter test test/golden/components_golden_test.dart --run-skipped
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/widgets/amount_field.dart';
import 'package:meridian_mobile/ui/widgets/amount_keypad.dart';
import 'package:meridian_mobile/ui/widgets/app_snackbar.dart';
import 'package:meridian_mobile/ui/widgets/capture_bar.dart';
import 'package:meridian_mobile/ui/widgets/choice_wrap.dart';
import 'package:meridian_mobile/ui/widgets/collapsing_fab.dart';
import 'package:meridian_mobile/ui/widgets/color_swatches.dart';
import 'package:meridian_mobile/ui/widgets/empty_state.dart';
import 'package:meridian_mobile/ui/widgets/form_scaffold.dart';
import 'package:meridian_mobile/ui/widgets/hero_stat.dart';
import 'package:meridian_mobile/ui/widgets/money_glance.dart';
import 'package:meridian_mobile/ui/widgets/money_text.dart';
import 'package:meridian_mobile/ui/widgets/nok_chip.dart';
import 'package:meridian_mobile/ui/widgets/nok_sheet.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_card.dart';
import 'package:meridian_mobile/ui/widgets/nokturn_row.dart';
import 'package:meridian_mobile/ui/widgets/offline_banner.dart';
import 'package:meridian_mobile/ui/widgets/picker_sheet.dart';
import 'package:meridian_mobile/ui/widgets/primary_button.dart';
import 'package:meridian_mobile/ui/widgets/section_header.dart';
import 'package:meridian_mobile/ui/widgets/segmented_pill.dart';
import 'package:meridian_mobile/ui/widgets/settings_row.dart';
import 'package:meridian_mobile/ui/widgets/stat_tile.dart';
import 'package:meridian_mobile/ui/widgets/status_bar_scrim.dart';
import 'package:meridian_mobile/ui/widgets/streak_flame.dart';
import 'package:meridian_mobile/ui/widgets/swipe_action.dart';

import 'golden_harness.dart';

/// Dark and light, at 1.0× and 2.0× text (Turkish).
const _variants = [
  GoldenVariant.trDark,
  GoldenVariant.trLight,
  GoldenVariant.trDarkLarge,
  GoldenVariant('tr', Brightness.light, 2.0),
];

/// Shoots [page] once per variant on a 360 dp wide, [height] dp tall view
/// (twice as tall at 2.0×). [act] runs before the shot — opens a sheet,
/// holds a swipe — and hands back what to undo after it.
void _gallery(
  String page,
  double height,
  Widget Function() build, {
  bool settle = true,
  Future<Future<void> Function()?> Function(WidgetTester tester)? act,
}) {
  for (final variant in _variants) {
    testWidgets('components_$page ${variant.name}', (tester) async {
      goldenVariant = variant;
      final tall = height * (variant.textScale > 1 ? 2 : 1);
      tester.view.physicalSize = Size(1080, tall * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        goldenHost(Scaffold(body: SafeArea(child: build())), [
          sharedPrefsProvider.overrideWithValue(goldenPrefs),
        ]),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // Something keeps animating (a spinner): let timers fire, then stop.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }
      final undo = await act?.call(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('images/${variant.name}/components_$page.png'),
      );
      await undo?.call();
    });
  }
}

/// A gallery label.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

Widget _column(List<Widget> children) => ListView(
  physics: const NeverScrollableScrollPhysics(),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  children: children,
);

void main() {
  setUpGoldens();

  _gallery('surfaces', 1500, () {
    return Builder(
      builder: (context) {
        final c = context.nok;
        return _column([
          const _Label('NOKTURNCARD · STANDARD / TAPPABLE'),
          NokturnCard(child: Text('Standart kart', style: _title(context))),
          const SizedBox(height: 12),
          NokturnCard(
            onTap: () {},
            child: Text('Dokunulabilir kart', style: _title(context)),
          ),
          const SizedBox(height: 24),
          SectionHeader('Son işlemler', onSeeAll: () {}),
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                NokturnRow(
                  leading: LeadingCircle.tone(
                    entityTone('#6B8E5A', c),
                    initial: 'M',
                  ),
                  title: 'Market',
                  meta: 'Cüzdan · bugün',
                  trailing: const MoneyText(
                    -24550,
                    currency: 'TRY',
                    subunitToUnit: 100,
                  ),
                  onTap: () {},
                ),
                NokturnRow.divider(),
                NokturnRow(
                  leading: const LeadingCircle.transfer(),
                  title: 'Cüzdan → Birikim',
                  meta: 'Transfer',
                  chevron: true,
                  onTap: () {},
                ),
                NokturnRow.divider(),
                NokturnRow(
                  leading: const LeadingCircle.uncategorized(),
                  title: 'Seçili satır',
                  selected: true,
                  onTap: () {},
                ),
                NokturnRow.divider(),
                const NokturnRow(
                  leading: LeadingCircle.uncategorized(),
                  title: 'Devre dışı satır',
                  meta: 'Kullanılamıyor',
                  enabled: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            'Alışkanlıklar',
            count: '2/5',
            progress: 0.4,
            onAdd: () {},
            addTooltip: 'Alışkanlık ekle',
          ),
          const SizedBox(height: 12),
          const _Label('GHOSTCARD'),
          GhostCard(
            icon: Icons.account_balance_wallet_outlined,
            message: 'İlk hesabını ekle, bakiyeler burada görünsün.',
            actionLabel: 'Ekle',
            onAction: () {},
            dismissKey: 'gallery',
          ),
          const _Label('SETTINGSROW'),
          NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                SettingsRow(
                  icon: Icons.palette_outlined,
                  title: 'Tema',
                  value: 'Koyu',
                  onTap: () {},
                ),
                SettingsRow.divider(),
                SettingsRow(
                  icon: Icons.dns_outlined,
                  title: 'Sunucu',
                  value: '192.168.1.24:3000 · Bağlı · 38 ms',
                  valuePlacement: ValuePlacement.below,
                  onTap: () {},
                ),
                SettingsRow.divider(),
                SettingsRow(
                  icon: Icons.motion_photos_off_outlined,
                  title: 'Hareketi azalt',
                  trailing: Switch(value: true, onChanged: (_) {}),
                ),
                SettingsRow.divider(),
                SettingsRow(
                  icon: Icons.logout_rounded,
                  iconColor: c.error,
                  titleColor: c.error,
                  title: 'Çıkış yap',
                  chevron: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
          const _Label('STATTILE · STREAKFLAME'),
          StatTileRow(
            tiles: [
              StatTile(
                value: '21',
                label: 'En uzun seri',
                leading: Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: c.goldBright,
                ),
              ),
              StatTile(value: '%86', label: 'Bu ay tamamlanan'),
              StatTile(value: '142', label: 'Toplam gün'),
            ],
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              StreakFlame(days: 12),
              StreakFlame(days: 12, size: StreakFlameSize.stat),
              StreakFlame(days: 12, size: StreakFlameSize.detail),
              StreakFlame(days: 0, record: 21),
            ],
          ),
        ]);
      },
    );
  });

  _gallery('controls', 2000, settle: false, () {
    return StatefulBuilder(
      builder: (context, setState) {
        return _column([
          const _Label(
            'PRIMARYBUTTON · NORMAL / LOADING / DISABLED / DESTRUCTIVE',
          ),
          PrimaryButton(label: 'Kaydet', onPressed: () {}),
          const SizedBox(height: 8),
          PrimaryButton(label: 'Kaydet', loading: true, onPressed: () {}),
          const SizedBox(height: 8),
          const PrimaryButton(label: 'Kaydet'),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Sil ve taşı',
            destructive: true,
            onPressed: () {},
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: () {}, child: const Text('İptal')),
              TextButton(onPressed: () {}, child: const Text('Tümünü gör')),
            ],
          ),
          const _Label('NOKCHIP · CHOICEWRAP'),
          Wrap(
            spacing: 8,
            children: [
              NokChip(label: 'Tümü', selected: true, onTap: () {}),
              NokChip(label: 'Gelir', onTap: () {}),
              NokChip(label: 'Cüzdan', dropdown: true, onTap: () {}),
              NokChip(
                label: 'Market',
                dot: const Color(0xFF6B8E5A),
                selected: true,
                onTap: () {},
              ),
              const NokChip(label: 'Kilitli', enabled: false),
            ],
          ),
          ChoiceWrap<String>(
            choices: const [
              Choice('cash', 'Nakit'),
              Choice('bank', 'Banka'),
              Choice('card', 'Kredi kartı'),
            ],
            selected: 'bank',
            onChanged: (_) {},
          ),
          const _Label('SEGMENTEDPILL'),
          SegmentedPill<String>(
            options: const [
              ('expense', 'Gider'),
              ('income', 'Gelir'),
              ('transfer', 'Transfer'),
            ],
            selected: 'income',
            onChanged: (_) {},
          ),
          const SizedBox(height: 8),
          SegmentedPill<String>(
            expand: true,
            options: const [('add', 'Ekle'), ('set', 'Ayarla')],
            selected: 'add',
            onChanged: (_) {},
          ),
          const _Label('COLORSWATCHROW'),
          ColorSwatchRow(selected: '#6B8FA0', onChanged: (_) {}),
          const _Label('FORM FIELDS'),
          const TextField(
            decoration: InputDecoration(labelText: 'Ad', hintText: 'Market'),
          ),
          const SizedBox(height: 12),
          FormPickerRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Hesap',
            value: 'Cüzdan',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          FormPickerRow(
            icon: Icons.category_outlined,
            label: 'Kategori',
            onTap: () {},
            errorText: 'Bir kategori seç',
          ),
          const SizedBox(height: 12),
          AmountField(
            label: 'Tutar',
            minorUnits: 123456,
            currency: 'TRY',
            subunitToUnit: 100,
            onChanged: (_) {},
          ),
          const _Label('AMOUNTKEYPAD'),
          AmountKeypad(
            onDigit: (_) {},
            onDot: () {},
            onBackspace: () {},
            onClear: () {},
          ),
          const _Label('MONEYGLANCE'),
          Wrap(
            spacing: 8,
            children: [
              MoneyGlance(
                netCents: 4275000,
                currency: 'TRY',
                subunitToUnit: 100,
                onTap: () {},
              ),
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
                onStart: () {},
              ),
            ],
          ),
          const _Label('CAPTUREBAR · FAB OPEN / FOLDED'),
          CaptureBar(
            onOpen: () {},
            label: 'Ekle: görev, harcama, etkinlik…',
            secondaryIcon: Icons.payments_outlined,
            secondaryTooltip: 'İşlem ekle',
            onSecondary: () {},
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              CollapsingFab(
                icon: Icons.add_rounded,
                label: 'İşlem',
                onPressed: () {},
              ),
              const _FoldedFab(),
            ],
          ),
        ]);
      },
    );
  });

  _gallery('feedback', 1800, () {
    return Builder(
      builder: (context) {
        final c = context.nok;
        return _column([
          const _Label('OFFLINEBANNER · IN ITS SLOT'),
          OfflineBannerSlot(
            banner: OfflineBanner(
              lastUpdated: DateTime(2026, 10, 4, 9, 12),
              onRetry: () {},
            ),
          ),
          const _Label('HEROSTAT'),
          const HeroStat(
            overline: 'BU AY NET',
            value: MoneyText(
              2460000,
              currency: 'TRY',
              subunitToUnit: 100,
              variant: MoneyVariant.title,
              signed: true,
              positiveGreen: true,
            ),
            support: HeroStatSupport(
              parts: [
                (
                  'Gelir',
                  MoneyText(
                    5780000,
                    currency: 'TRY',
                    subunitToUnit: 100,
                    signed: true,
                    positiveGreen: true,
                  ),
                ),
                (
                  'Gider',
                  MoneyText(-3320000, currency: 'TRY', subunitToUnit: 100),
                ),
              ],
            ),
            footnote: 'Bu yıl +₺21.200',
            insight: 'Geçen aya göre ₺3.100 daha az harcadın.',
          ),
          const _Label('EMPTYSTATE · INLINE / ALL DONE'),
          EmptyState.inline(
            icon: Icons.event_available_outlined,
            message: 'Bugün etkinlik yok',
            actionLabel: 'Ekle',
            onAction: () {},
          ),
          const SizedBox(height: 12),
          const EmptyState.allDone(),
          const _Label('EMPTYSTATE · ERROR'),
          EmptyState.error(onRetry: () {}, onServerSettings: () {}),
          const _Label('EMPTYSTATE · PAGE'),
          EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'İlk alışkanlığını ekle',
            subtitle: 'Küçük başla: günde bir kez yeter.',
            actionLabel: 'Alışkanlık ekle',
            onAction: () {},
            chips: [
              NokChip(label: 'Su iç', icon: Icons.add_rounded, onTap: () {}),
              NokChip(
                label: 'Kitap oku',
                icon: Icons.add_rounded,
                onTap: () {},
              ),
            ],
          ),
          const _Label('SHEET · HEADER AND ACTIONS'),
          Material(
            color: c.surface3,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const SheetHeader(
                  title: 'Bütçe',
                  subtitle: 'Market · Ekim',
                  showClose: true,
                ),
                SheetActions(
                  primary: PrimaryButton(label: 'Kaydet', onPressed: () {}),
                  destructive: TextButton(
                    onPressed: () {},
                    child: const Text('Bütçeyi kaldır'),
                  ),
                ),
              ],
            ),
          ),
          const _Label('DIALOG'),
          AlertDialog(
            title: const Text('"Market" silinsin mi?'),
            content: const Text('12 işlem "Diğer" kategorisine taşınacak.'),
            actions: [
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(foregroundColor: c.inkHi),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: c.error,
                  foregroundColor: c.onError,
                ),
                child: const Text('Sil ve taşı'),
              ),
            ],
          ),
        ]);
      },
    );
  });

  // Rows held mid-swipe: halfway to the threshold (where the mark's colour
  // changes over), a quarter, and past it.
  _gallery(
    'swipe',
    700,
    () => Builder(
      builder: (context) {
        final c = context.nok;
        Future<bool> no() async => false;
        SwipeAction row(String title, {SwipeSpec? start, SwipeSpec? end}) =>
            SwipeAction(
              key: ValueKey(title),
              startToEnd: start,
              endToStart: end,
              child: ColoredBox(
                color: c.surface1,
                child: NokturnRow(
                  leading: const LeadingCircle.uncategorized(),
                  title: title,
                  meta: 'Bugün',
                  onTap: () {},
                ),
              ),
            );
        return _column([
          const _Label('SWIPEACTION · → 50 % / ← 25 % / ← 50 % / ← PAST 40 %'),
          row(
            'Faturayı öde',
            start: SwipeSpec.complete(c, label: 'Tamamla', onSwipe: no),
            end: SwipeSpec.postpone(c, label: 'Yarın', onSwipe: no),
          ),
          const SizedBox(height: 8),
          row(
            'Raporu gönder',
            end: SwipeSpec.postpone(c, label: 'Yarın', onSwipe: no),
          ),
          const SizedBox(height: 8),
          row('Market', end: SwipeSpec.delete(c, label: 'Sil', onSwipe: no)),
          const SizedBox(height: 8),
          row('Kahve', end: SwipeSpec.delete(c, label: 'Sil', onSwipe: no)),
          const _Label('STATUSBARSCRIM · OVER SCROLLED CONTENT'),
          SizedBox(
            height: 140,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: 24)),
              child: StatusBarScrim.over(
                child: ColoredBox(
                  color: c.goldContainer,
                  child: ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Text(
                          'Altından kayan içerik $i',
                          style: TextStyle(color: c.onGoldContainer),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    ),
    act: (tester) async {
      final gestures = <TestGesture>[];
      for (final (title, share) in [
        ('Faturayı öde', 0.5),
        ('Raporu gönder', -0.25),
        ('Market', -0.5),
        ('Kahve', -1.25),
      ]) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(NokturnRow),
        );
        final rest = tester.getTopLeft(row).dx;
        final target =
            tester.getSize(row).width * SwipeAction.threshold * share;
        final gesture = await tester.startGesture(tester.getCenter(row));
        gestures.add(gesture);
        // Step until the row has moved [target]: the touch slop is spent
        // first.
        while ((tester.getTopLeft(row).dx - rest).abs() < target.abs()) {
          await gesture.moveBy(Offset(target.sign * 2, 0));
          await tester.pump();
        }
      }
      return () async {
        for (final gesture in gestures) {
          await gesture.cancel();
        }
        await tester.pumpAndSettle();
      };
    },
  );

  _gallery(
    'picker_sheet',
    780,
    () => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showPickerSheet<String>(
            context,
            title: 'Hesap',
            note: 'İşlem bu hesaptan düşülecek.',
            selected: 'wallet',
            options: const [
              PickerOption(
                value: 'wallet',
                label: 'Cüzdan',
                icon: Icons.account_balance_wallet_outlined,
                trailing: '₺1.240',
              ),
              PickerOption(
                value: 'bank',
                label: 'Banka',
                icon: Icons.account_balance_outlined,
                trailing: '₺18.400',
              ),
              PickerOption(
                value: 'card',
                label: 'Kredi kartı',
                icon: Icons.credit_card_outlined,
                subtitle: 'Hesap kesimi 12 Ekim',
              ),
            ],
          ),
          child: const Text('Aç'),
        ),
      ),
    ),
    act: (tester) async {
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      return null;
    },
  );

  _gallery(
    'snackbar',
    780,
    () => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showAppSnack(
            context,
            '"Market ₺245" eklendi',
            tone: SnackTone.success,
            actionLabel: 'Geri al',
            onAction: () {},
            secondaryLabel: 'Düzenle',
            onSecondary: () {},
            persist: true,
          ),
          child: const Text('Aç'),
        ),
      ),
    ),
    act: (tester) async {
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      return null;
    },
  );
}

TextStyle _title(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium!;

/// A FAB as it looks folded: under a scope that is told of a user's
/// scroll down (only a user's scroll folds it).
class _FoldedFab extends StatefulWidget {
  const _FoldedFab();

  @override
  State<_FoldedFab> createState() => _FoldedFabState();
}

class _FoldedFabState extends State<_FoldedFab> {
  final _controller = ScrollController();
  final _inside = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _inside.currentContext;
      if (!_controller.hasClients || context == null) return;
      _controller.jumpTo(100);
      // What a finger dragging the list up reports.
      final metrics = _controller.position.copyWith();
      UserScrollNotification(
        metrics: metrics,
        context: context,
        direction: ScrollDirection.reverse,
      ).dispatch(context);
      ScrollUpdateNotification(
        metrics: metrics,
        context: context,
        scrollDelta: 100,
      ).dispatch(context);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 56,
      child: CollapsingFabScope(
        child: Stack(
          key: _inside,
          children: [
            ListView(
              controller: _controller,
              children: const [SizedBox(height: 1000)],
            ),
            Positioned(
              left: 0,
              top: 0,
              child: CollapsingFab(
                icon: Icons.edit_outlined,
                label: 'Yaz',
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
