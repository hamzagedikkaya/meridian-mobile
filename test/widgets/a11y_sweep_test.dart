/// The accessibility sweep (design-analysis §8.1, §8.2; WP-17): every tab
/// root, every page the tabs push, and the sheets and forms, in the dark and
/// the light theme, against Flutter's three guidelines:
///
/// * `androidTapTargetGuideline` — every tappable thing at least 48×48 dp;
/// * `labeledTapTargetGuideline` — every tappable thing has a label (an
///   icon-only control a tooltip or a semantic label);
/// * `textContrastGuideline` — every text at least 4.5:1 (3:1 when large)
///   against what is drawn under it;
/// * [_ParagraphContrast] — the same bar for every visible paragraph. The
///   stock guideline only reaches a text whose semantics node carries it
///   alone; rows, tiles, cards and calendar cells merge or replace their
///   text's semantics, so most of the text on a screen is checked here.
///
/// The app runs as it does on a phone: `MeridianApp` signed in, the real
/// fonts, a 360×780 dp screen, the fake API's default data behind the real
/// repository. "Hareketi azalt" is on so every entrance, sweep and fade is
/// at its end state on the frame the guideline measures — contrast is
/// measured on what stays on screen, not on a frame of a fade.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meridian_mobile/core/session.dart';
import 'package:meridian_mobile/main.dart';
import 'package:meridian_mobile/models/account.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/models/transaction.dart';
import 'package:meridian_mobile/router/app_router.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/ui/flows/flows.dart' as flows;
import 'package:meridian_mobile/ui/screens/agenda/event_sheet.dart';
import 'package:meridian_mobile/ui/screens/agenda/todo_lists_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/account_form.dart';
import 'package:meridian_mobile/ui/screens/finance/budget_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/category_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/reconcile_sheet.dart';
import 'package:meridian_mobile/ui/screens/finance/subscription_form.dart';
import 'package:meridian_mobile/ui/screens/finance/subscriptions_screen.dart';
import 'package:meridian_mobile/ui/screens/finance/tx_detail_sheet.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_value_sheet.dart';
import 'package:meridian_mobile/ui/screens/habits/habit_form.dart';
import 'package:meridian_mobile/ui/screens/journal/journal_editor.dart';
import 'package:meridian_mobile/ui/screens/profile/profile_editors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import '../support/fake_api.dart';
import '../support/fake_stores.dart';

/// A session that is signed in from the start.
class _SignedIn extends SessionController {
  @override
  SessionState build() => const SessionLoggedIn();
}

/// Lets the fake API answer and the screens settle (some show progress
/// that never ends while loading, so `pumpAndSettle` cannot be used).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app on a 360×780 dp phone in [theme], signed in, at [location].
Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  required String theme,
  String location = '/today',
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    PrefKeys.locale: 'tr',
    PrefKeys.themeMode: theme,
    PrefKeys.reduceMotion: 'true',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWith(_SignedIn.new),
      dioProvider.overrideWithValue(FakeApi().dio),
      draftStoreProvider.overrideWithValue(MemoryDraftStore()),
    ],
    retry: (_, _) => null,
    child: const MeridianApp(),
  ));
  await _settle(tester);
  final router = tester.container().read(routerProvider);
  if (location != '/today') {
    router.go(location);
    await _settle(tester);
  }
  return router;
}

/// A context inside the shell's navigator, to open sheets and forms from.
BuildContext _shellContext(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).last);

Habit _habit() => Habit.fromJson(habitJson());

/// The surfaces the sweep visits: a location, or something opened over
/// Today.
final _pages = <String, String>{
  'Bugün': '/today',
  'Ajanda': '/agenda',
  'Finans': '/finance',
  'Alışkanlıklar': '/habits',
  'Günlük': '/journal',
  'Hedefler': '/goals',
  'Profil': '/profile',
  // The pages the tabs push.
  'Görev listeleri': '/agenda/lists',
  'İşlemler': '/finance/transactions',
  'Hesaplar': '/finance/accounts',
  'Hesap detayı': '/finance/account/1',
  'Kategoriler': '/finance/categories',
  'Abonelikler': '/finance/subscriptions',
  'Arşivlenmiş alışkanlıklar': '/habits/archived',
  'Hedef detayı': '/goals/3',
  'Günlük kaydı': '/journal/20',
  'Sunucu': '/profile/server',
};

final _sheets = <String, void Function(BuildContext context)>{
  'hızlı ekle': (context) => flows.openQuickAdd(context),
  'işlem formu': (context) => flows.openTransactionForm(context),
  'görev sheet\'i': (context) => flows.openTodoSheet(context),
  'etkinlik formu': (context) => flows.openEventForm(context),
  'alışkanlık detayı': (context) => flows.openHabitDetail(context, _habit()),
  'alışkanlık kaydı': (context) => flows.openHabitLog(context, habitId: 7),
  'alışkanlık formu': (context) => openHabitForm(context),
  'hedef formu': (context) => flows.openGoalForm(context, type: 'custom'),
  'günlük editörü': (context) => openJournalEditor(context),
  'hesap formu': (context) => openAccountForm(context),
  'bütçe sheet\'i': (context) => showBudgetSheet(context),
  'etkinlik sheet\'i': (context) =>
      showEventSheet(context, Event.fromJson(eventJson(full: true))),
  'liste sheet\'i': (context) => openTodoListSheet(context),
  'kategori sheet\'i': (context) =>
      showCategorySheet(context, kind: 'expense'),
  'işlem sheet\'i': (context) => showTransactionSheet(
        context,
        _ref(context),
        Transaction.fromJson(transactionJson()),
      ),
  'abonelik sheet\'i': (context) =>
      showSubscriptionSheet(context, id: 6, name: 'Netflix'),
  'abonelik formu': (context) => openSubscriptionForm(context),
  'bakiye eşitleme': (context) => showReconcileSheet(
        context,
        _ref(context),
        Account.fromJson(accountJson()),
      ),
  'hedef değeri': (context) => showGoalValueSheet(
        context,
        title: 'Kitap',
        kind: const GoalValueKind.count('kitap'),
        initial: 40,
      ),
  'şifre değiştir': (context) => showPasswordEditor(context),
  'çıkış sheet\'i': (context) => showSignOutSheet(context),
};

/// A [WidgetRef] for the sheets that take one: the shell's own.
WidgetRef _ref(BuildContext context) {
  WidgetRef? found;
  context.visitAncestorElements((element) {
    if (element is WidgetRef) {
      found = element as WidgetRef;
      return false;
    }
    return true;
  });
  return found!;
}

/// The mood names under the five mood faces (labelSmall, 11 sp). The
/// guideline captures the screen at 1 px per dp, where an 11 sp stroke is
/// mostly anti-aliased edge: the most frequent "dark" pixel of the name is
/// an edge shade, not the ink (it read inkMid at 27 % — 3.6:1 — for a name
/// drawn in inkMid at 6.9:1). Their colours are checked here instead
/// ([_expectMoodNamesInk]); the pairs themselves are pinned by
/// `test/theme/contrast_test.dart`.
const _moodNames = {'Harika', 'İyi', 'Normal', 'Kötü', 'Berbat'};

/// [textContrastGuideline] without the mood names (see [_moodNames]).
class _TextContrast extends MinimumTextContrastGuideline {
  const _TextContrast();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || _moodNames.contains(data.label);
}

/// Every paragraph that can be hit on screen — merged into a row's
/// semantics or not — against the most frequent pixel around it: the
/// colour its style draws (with the opacity of what wraps it) must reach
/// 4.5:1, or 3:1 when large (≥ 18 sp, or bold ≥ 14 sp).
///
/// Skipped: icons (non-text, §8.1 asks 3:1 of them and contrast_test pins
/// the pairs), disabled controls (WCAG 1.4.3 exempts them) and the mood
/// names (see [_moodNames]).
class _ParagraphContrast extends AccessibilityGuideline {
  const _ParagraphContrast();

  @override
  String get description =>
      'Every visible paragraph at least 4.5:1 (3:1 when large)';

  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    var width = 0;
    var height = 0;
    final bytes = await tester.binding.runAsync<ByteData?>(() async {
      final image = await layer.toImage(
        renderView.paintBounds,
        pixelRatio: 1 / renderView.flutterView.devicePixelRatio,
      );
      width = image.width;
      height = image.height;
      final data = await image.toByteData();
      image.dispose();
      return data;
    });

    var result = const Evaluation.pass();
    final seen = <RenderObject>{};
    for (final element in find.byType(RichText).hitTestable().evaluate()) {
      final box = element.renderObject;
      if (box is! RenderParagraph || !seen.add(box)) continue;
      if (_skipped(element)) continue;
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        box.paintBounds.inflate(4),
      ).intersect(Offset.zero & Size(width.toDouble(), height.toDouble()));
      if (rect.width <= 0 || rect.height <= 0) continue;
      final histogram = _histogram(bytes!, width, rect);
      final opacity = _opacityAbove(box);
      if (opacity == 0) continue;
      _visitSpans(box.text, null, (text, style) {
        final ink = style.color;
        if (ink == null || ink.a == 0 || text.trim().isEmpty) return;
        if (_moodNames.contains(text)) return;
        final background = _background(histogram, ink);
        if (background == null) return;
        final drawn = Color.alphaBlend(
          ink.withValues(alpha: ink.a * opacity),
          background,
        );
        final ratio = _contrast(drawn, background);
        final size = style.fontSize ?? 14;
        final bold = (style.fontWeight ?? FontWeight.w400).value >= 700;
        final target = size >= 18 || (bold && size >= 14) ? 3.0 : 4.5;
        if (ratio + 0.01 < target) {
          result += Evaluation.fail(
            '"$text" at ${rect.center}: ${ratio.toStringAsFixed(2)}:1, '
            'needs $target:1 (ink $ink at $opacity on $background, '
            '${size}sp${bold ? ' bold' : ''}).\n',
          );
        }
      });
    }
    return result;
  }

  /// An icon's glyph, or text in a disabled control.
  static bool _skipped(Element element) {
    var skip = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Icon ||
          (widget is ButtonStyleButton && !widget.enabled) ||
          (widget is ListTile && !widget.enabled) ||
          (widget is Semantics && widget.properties.enabled == false)) {
        skip = true;
        return false;
      }
      return true;
    });
    return skip;
  }

  /// The opacity the render tree applies above [box].
  static double _opacityAbove(RenderObject box) {
    var opacity = 1.0;
    for (RenderObject? node = box.parent; node != null; node = node.parent) {
      if (node is RenderOpacity) opacity *= node.opacity;
      if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
      if (node is RenderSliverOpacity) opacity *= node.opacity;
      if (node is RenderSliverAnimatedOpacity) opacity *= node.opacity.value;
    }
    return opacity;
  }

  /// Each text run of [span] with its effective style.
  static void _visitSpans(
    InlineSpan span,
    TextStyle? inherited,
    void Function(String text, TextStyle style) visit,
  ) {
    if (span is! TextSpan) return;
    final style = inherited?.merge(span.style) ?? span.style ?? const TextStyle();
    if (span.text != null) visit(span.text!, style);
    for (final child in span.children ?? const <InlineSpan>[]) {
      _visitSpans(child, style, visit);
    }
  }

  static Map<int, int> _histogram(ByteData bytes, int width, Rect rect) {
    final histogram = <int, int>{};
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final rgba = bytes.getUint32((y * width + x) * 4);
        histogram[rgba] = (histogram[rgba] ?? 0) + 1;
      }
    }
    return histogram;
  }

  /// The most frequent pixel that is not the ink itself (a large glyph can
  /// cover more of its box than the background does).
  static Color? _background(Map<int, int> histogram, Color ink) {
    final ranked = histogram.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ranked) {
      final rgba = entry.key;
      final color = Color.fromARGB(
        0xFF,
        (rgba >> 24) & 0xFF,
        (rgba >> 16) & 0xFF,
        (rgba >> 8) & 0xFF,
      );
      if (_contrast(color, ink.withValues(alpha: 1)) > 1.05) return color;
    }
    return null;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }
}

/// Every mood name on screen is drawn in an ink the contrast test pins at
/// 4.5:1 or more on these surfaces: inkMid under the faces (gold when
/// chosen), inkHi where an entry names its mood.
void _expectMoodNamesInk(WidgetTester tester) {
  for (final name in _moodNames) {
    for (final element in find.text(name).evaluate()) {
      final c = element.nok;
      final color = (element.widget as Text).style?.color;
      expect(color, anyOf(c.inkMid, c.gold, c.inkHi), reason: name);
    }
  }
}

Future<void> _expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(const _TextContrast()));
  await expectLater(tester, meetsGuideline(const _ParagraphContrast()));
  _expectMoodNamesInk(tester);
}

/// The main list of what is on top: the vertical scrollable of the current
/// route that scrolls furthest.
ScrollableState? _mainScrollable(WidgetTester tester) {
  ScrollableState? best;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.axisDirection != AxisDirection.down) continue;
    // Under a sheet or a form, the page below is not what is checked.
    if (ModalRoute.of(element)?.isCurrent == false) continue;
    if (!state.position.hasContentDimensions) continue;
    if (best == null ||
        state.position.maxScrollExtent > best.position.maxScrollExtent) {
      best = state;
    }
  }
  return best;
}

/// The guidelines on every screenful of the page, top to bottom (at most
/// six): what is below the fold is checked too.
Future<void> _expectGuidelinesWhileScrolling(WidgetTester tester) async {
  await _expectGuidelines(tester);
  for (var page = 1; page < 6; page++) {
    final scrollable = _mainScrollable(tester);
    if (scrollable == null) return;
    final position = scrollable.position;
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo(
      (position.pixels + position.viewportDimension * 0.8)
          .clamp(0, position.maxScrollExtent),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await _expectGuidelines(tester);
  }
}

/// The app's root navigator: a sheet or a form is a route on it.
NavigatorState _root(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await loadAppFonts();
  });

  for (final theme in ['dark', 'light']) {
    group('$theme theme', () {
      for (final MapEntry(key: name, value: location) in _pages.entries) {
        testWidgets('$name: tap targets, labels, text contrast',
            (tester) async {
          final handle = tester.ensureSemantics();
          await _pumpApp(tester, theme: theme, location: location);
          expect(tester.takeException(), isNull);
          await _expectGuidelinesWhileScrolling(tester);
          handle.dispose();
        });
      }

      for (final MapEntry(key: name, value: open) in _sheets.entries) {
        testWidgets('$name: tap targets, labels, text contrast',
            (tester) async {
          final handle = tester.ensureSemantics();
          await _pumpApp(tester, theme: theme);
          expect(_root(tester).canPop(), isFalse);
          open(_shellContext(tester));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(_root(tester).canPop(), isTrue, reason: 'it opened');
          await _expectGuidelinesWhileScrolling(tester);
          handle.dispose();
        });
      }
    });
  }
}
