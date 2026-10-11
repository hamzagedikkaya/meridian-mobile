import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/deadline_badge.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_card.dart';
import 'package:meridian_mobile/ui/screens/goals/goal_form.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';
import 'package:meridian_mobile/ui/widgets/progress_ring.dart';

/// One goal as the /goals endpoint delivers it. Fields default to the shapes
/// seen in api-samples so callers only override what a case needs.
Map<String, dynamic> goalJson({
  required int id,
  required String name,
  String description = '',
  String targetType = 'custom',
  String status = 'active',
  String color = '#6B8E5A',
  String unit = 'gün',
  String? deadline = '2026-09-02',
  int daysRemaining = 53,
  Map<String, dynamic>? deadlineBadge = const {'state': 'far', 'days': 53},
  num targetValue = 100,
  num currentValue = 42,
  num progressPercent = 42,
  Map<String, dynamic>? related,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'target_type': targetType,
  'status': status,
  'color': color,
  'unit': unit,
  'deadline': deadline,
  'days_remaining': daysRemaining,
  'deadline_badge': deadlineBadge,
  'target_value': targetValue,
  'current_value': currentValue,
  'progress_percent': progressPercent,
  'related': related,
};

/// Active list covers every deadline_badge state, a target_value:0 goal
/// (ring/percent division-by-zero guard) and a financial goal with related:null.
final _populated = {
  'active': [
    goalJson(id: 18, name: 'Read for 100 days', targetType: 'habit'),
    // target_value 0 → progress_percent 0; must not divide-by-zero / NaN.
    goalJson(
      id: 20,
      name: 'Learn German — A2',
      targetType: 'custom',
      color: '#6B8FA0',
      unit: 'level',
      deadline: null,
      deadlineBadge: null,
      daysRemaining: 0,
      targetValue: 0,
      currentValue: 0,
      progressPercent: 0,
    ),
    goalJson(
      id: 21,
      name: 'Ship the release',
      color: '#B85450',
      deadline: '2026-07-14',
      deadlineBadge: const {'state': 'soon', 'days': 5},
      daysRemaining: 5,
    ),
    goalJson(
      id: 22,
      name: 'Submit the tax form today',
      color: '#8B5A00',
      deadline: '2026-07-11',
      deadlineBadge: const {'state': 'today', 'days': 0},
      daysRemaining: 0,
    ),
    // Financial, related:null → must fall back to `unit` as currency (TRY).
    goalJson(
      id: 23,
      name: 'Ödemeyi geciktirme',
      targetType: 'financial',
      color: '#B8860B',
      unit: 'TRY',
      deadline: '2026-06-01',
      deadlineBadge: const {'state': 'overdue', 'days': 3},
      daysRemaining: -3,
      targetValue: 50000,
      currentValue: 12000,
      progressPercent: 24,
    ),
  ],
  'achieved': [
    goalJson(
      id: 17,
      name: 'Save 50K in 3 months',
      targetType: 'financial',
      status: 'achieved',
      color: '#B8860B',
      unit: 'TRY',
      targetValue: 50000,
      currentValue: 659760.19,
      progressPercent: 100,
    ),
  ],
  'abandoned': [
    goalJson(
      id: 16,
      name: 'Abandoned goal',
      status: 'abandoned',
      unit: 'kg',
      targetValue: 10,
      currentValue: 2,
      progressPercent: 20,
    ),
  ],
};

const _empty = {'active': [], 'achieved': [], 'abandoned': []};

// achieved-only: active empty but a single financial goal in Başarılanlar.
final _achievedOnly = {
  'active': const [],
  'achieved': [
    goalJson(
      id: 17,
      name: 'Save 50K in 3 months',
      targetType: 'financial',
      status: 'achieved',
      color: '#B8860B',
      unit: 'TRY',
      targetValue: 50000,
      currentValue: 659760.19,
      progressPercent: 100,
    ),
  ],
  'abandoned': const [],
};

Widget _app(GoalsBundle bundle, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      goalsProvider.overrideWith(
        (ref) async => Fetched(bundle, DateTime(2026, 7, 11)),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const GoalsScreen(),
    ),
  );
}

/// A phone: 360×780 dp.
void _phone(WidgetTester tester, {double height = 780}) {
  tester.view.physicalSize = Size(1080, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Two goals side by side that differ in everything that used to push the
/// ring around: a one-line and a two-line name, a badge and none, a short
/// and a long type overline.
final _mismatched = {
  'active': [
    goalJson(id: 1, name: 'Koşu', targetType: 'habit'),
    goalJson(
      id: 2,
      name: 'Avrupa turu için birikim yap ve planla',
      targetType: 'custom',
      deadline: null,
      deadlineBadge: null,
    ),
  ],
  'achieved': const [],
  'abandoned': const [],
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders the populated goals grid without exceptions', (
    tester,
  ) async {
    // Tall surface so the full list (grid + collapsed sections) lays out —
    // CustomScrollView only builds slivers within the viewport.
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(GoalsBundle.fromJson(_populated)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hedefler'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    // Section for achieved goals + its target label rendered as money.
    expect(find.text('Başarılanlar (1)'), findsOneWidget);
    // target_value 0 goal renders a 0% ring rather than NaN/crash.
    expect(find.text('%0'), findsWidgets);
    // Deadline badge states render their Turkish labels.
    expect(find.text('bugün'), findsOneWidget);
    expect(find.text('5g kaldı'), findsOneWidget);
    expect(find.text('3g gecikti'), findsOneWidget);
  });

  testWidgets('renders the empty state with no goals', (tester) async {
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_empty)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('İlk hedefini koy'), findsOneWidget);
  });

  testWidgets('a refresh that shifts the grid moves each ring on from where it '
      'was, rather than replaying its sweep from zero', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = goalJson(id: 18, name: 'Kitap', progressPercent: 40);
    final second = goalJson(id: 21, name: 'Koşu', progressPercent: 60);
    final third = goalJson(id: 22, name: 'Dil', progressPercent: 80);
    var payload = <String, dynamic>{
      'active': [first, second, third],
      'achieved': const [],
      'abandoned': const [],
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalsProvider.overrideWith(
            (ref) async =>
                Fetched(GoalsBundle.fromJson(payload), DateTime(2026, 7, 11)),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const GoalsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first goal was achieved on the web: the other two move up a slot.
    payload = {
      'active': [second, third],
      'achieved': [
        {...first, 'status': 'achieved', 'progress_percent': 100},
      ],
      'abandoned': const [],
    };
    tester.container().invalidate(goalsProvider);
    await tester.pump();
    await tester.pump();
    expect(find.text('Kitap'), findsNothing);

    final rings = tester.stateList<ProgressRingState>(
      find.byType(ProgressRing),
    );
    expect(rings, hasLength(2));
    for (final ring in rings) {
      // Each ring moves on from a value it already showed (0.4–0.8), never
      // from zero.
      expect(
        ring.paintedValue,
        greaterThan(0.3),
        reason: 'restarted from zero',
      );
    }
    await tester.pumpAndSettle();
    final settled = tester
        .stateList<ProgressRingState>(find.byType(ProgressRing))
        .map((r) => r.paintedValue);
    expect(settled, [closeTo(0.6, 0.001), closeTo(0.8, 0.001)]);
  });

  testWidgets('renders an achieved-only list (empty active) safely', (
    tester,
  ) async {
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_achievedOnly)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No active grid header, but the collapsed achieved section is present.
    expect(find.text('Aktif'), findsNothing);
    expect(find.text('Başarılanlar (1)'), findsOneWidget);
  });

  testWidgets('a row of two cards lines up: overline, ring and badge slot '
      'within 1 dp, whatever the names and badges', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_mismatched)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final cards = find.byType(GoalCard);
    expect(cards, findsNWidgets(2));
    Rect inCard(int i, Finder f) =>
        tester.getRect(find.descendant(of: cards.at(i), matching: f).first);

    final overline = [
      inCard(0, find.text('ALIŞKANLIK')),
      inCard(1, find.text('ÖZEL')),
    ];
    expect((overline[0].top - overline[1].top).abs(), lessThanOrEqualTo(1));

    final names = [
      inCard(0, find.text('Koşu')),
      inCard(1, find.textContaining('Avrupa')),
    ];
    expect((names[0].top - names[1].top).abs(), lessThanOrEqualTo(1));

    final rings = [
      inCard(0, find.byType(ProgressRing)),
      inCard(1, find.byType(ProgressRing)),
    ];
    expect((rings[0].top - rings[1].top).abs(), lessThanOrEqualTo(1));
    expect(rings[0].width, 72);

    // The slot lines up whether or not it holds a pill (the second goal
    // has no deadline, so no pill at all).
    final slots = [
      inCard(0, find.byKey(GoalCard.badgeSlotKey)),
      inCard(1, find.byKey(GoalCard.badgeSlotKey)),
    ];
    expect((slots[0].top - slots[1].top).abs(), lessThanOrEqualTo(1));
    expect(slots[0].height, 24);
    expect(
      find.descendant(
        of: cards.at(1),
        matching: find.byType(DeadlineBadgeChip),
      ),
      findsNothing,
    );
    final badge = inCard(0, find.byType(DeadlineBadgeChip));
    expect((badge.center.dy - slots[0].center.dy).abs(), lessThanOrEqualTo(1));
    // The badge never shares the overline's line.
    expect(badge.top, greaterThan(rings[0].bottom));
  });

  // A value line too wide for its column shrinks — and must not shorten
  // its slot, or that card's ring and value sit lower than its
  // neighbour's. Money with kuruş under 100.000 next to a short count, at
  // 1.0× and at 1.3× (still two columns).
  for (final scale in [1.0, 1.3]) {
    testWidgets('a long value line beside a short one keeps the ring, value '
        'and badge slot level at ${scale}x text', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(
          GoalsBundle.fromJson({
            'active': [
              goalJson(
                id: 1,
                name: 'Tatil',
                targetType: 'financial',
                unit: 'TRY',
                targetValue: 75000.5,
                currentValue: 12345.67,
                progressPercent: 16,
              ),
              goalJson(
                id: 2,
                name: 'Kitap',
                targetType: 'habit',
                unit: 'kitap',
                targetValue: 50,
                currentValue: 24,
                progressPercent: 48,
              ),
            ],
            'achieved': const [],
            'abandoned': const [],
          }),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final cards = find.byType(GoalCard);
      expect(cards, findsNWidgets(2));
      Rect inCard(int i, Finder f) =>
          tester.getRect(find.descendant(of: cards.at(i), matching: f).first);
      // Side by side, not stacked.
      expect(
        (tester.getRect(cards.at(0)).top - tester.getRect(cards.at(1)).top)
            .abs(),
        lessThanOrEqualTo(1),
      );

      for (final part in [
        find.byType(ProgressRing),
        find.byKey(GoalCard.valueSlotKey),
        find.byKey(GoalCard.badgeSlotKey),
      ]) {
        final a = inCard(0, part);
        final b = inCard(1, part);
        expect((a.top - b.top).abs(), lessThanOrEqualTo(1), reason: '$part');
        expect((a.height - b.height).abs(), lessThanOrEqualTo(1));
      }
      // The long value really was shrunk to fit (so this is the case that
      // used to drop its ring).
      final value = tester.getRect(
        find.descendant(
          of: cards.at(0),
          matching: find.textContaining('₺12.345,67'),
        ),
      );
      expect(
        value.width,
        lessThanOrEqualTo(inCard(0, find.byKey(GoalCard.valueSlotKey)).width),
      );
    });
  }

  testWidgets('no value ends in "…": large money goes compact, the line '
      'shrinks rather than cuts', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        GoalsBundle.fromJson({
          'active': [
            goalJson(
              id: 1,
              name: 'Ev',
              targetType: 'financial',
              unit: 'TRY',
              targetValue: 2500000,
              currentValue: 1234567.89,
              progressPercent: 49,
            ),
            goalJson(
              id: 2,
              name: 'Araba',
              targetType: 'financial',
              unit: 'TRY',
              targetValue: 50000,
              currentValue: 47500,
              progressPercent: 95,
            ),
            goalJson(
              id: 3,
              name: 'Kitap',
              unit: 'sayfa sayfa sayfa sayfa',
              targetValue: 123456,
              currentValue: 98765,
              progressPercent: 80,
            ),
          ],
          'achieved': const [],
          'abandoned': const [],
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('₺1,2Mn / ₺2,5Mn'), findsOneWidget);
    expect(find.text('₺47.500 / ₺50.000'), findsOneWidget);

    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byType(GoalCard),
        matching: find.byType(RichText),
      ),
    )) {
      final text = paragraph.text.toPlainText();
      if (!text.contains('/')) continue;
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      expect(text.endsWith('…'), isFalse, reason: text);
    }
  });

  // From 1.6× (where "ALIŞKANLIK" no longer fits a half-width card) the
  // grid is one column.
  for (final scale in [1.6, 2.0]) {
    testWidgets('at ${scale}x text the grid is one column, without overflow, '
        'its badge slot grown with the text', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _app(GoalsBundle.fromJson(_mismatched), textScale: scale),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getRect(find.byType(GoalCard).at(0));
      final second = tester.getRect(find.byType(GoalCard).at(1));
      expect(second.top, greaterThan(first.bottom), reason: 'stacked');
      expect(first.width, greaterThan(300));
      final slot = tester.getRect(
        find
            .descendant(
              of: find.byType(GoalCard).at(0),
              matching: find.byKey(GoalCard.badgeSlotKey),
            )
            .first,
      );
      final pill = tester.getRect(
        find
            .descendant(
              of: find.byType(GoalCard).at(0),
              matching: find.byType(DeadlineBadgeChip),
            )
            .first,
      );
      expect(slot.height, closeTo(14 * scale + 8, 0.01));
      // The pill is drawn at its full size, not shrunk into a 24 dp slot.
      expect(pill.height, closeTo(slot.height, 1));
    });
  }

  testWidgets('with no goal, each of the three kinds opens the form with it '
      'chosen; "Yeni" opens it too', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_empty)));
    await tester.pumpAndSettle();
    expect(find.text('Birikim hedefi'), findsOneWidget);
    expect(find.text('Alışkanlık hedefi'), findsOneWidget);
    expect(find.text('Özel hedef'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Birikim hedefi'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalFormScreen), findsOneWidget);
    final chosen = tester.widget<GoalFormScreen>(find.byType(GoalFormScreen));
    expect(chosen.initialType, 'financial');
    // Money, so no unit field.
    expect(find.widgetWithText(TextField, 'Birim'), findsNothing);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yeni'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalFormScreen), findsOneWidget);
    expect(find.text('Yeni hedef'), findsOneWidget);
  });

  testWidgets('a long press on a card offers its quick actions', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_mismatched)));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(GoalCard).at(1));
    await tester.pumpAndSettle();
    expect(find.text('İlerleme ekle'), findsOneWidget);
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Bırak'), findsOneWidget);
  });

  testWidgets('the long press\'s actions are screen-reader actions too, on '
      'the cards and on the folded rows (§6.4)', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_populated)));
    await tester.pumpAndSettle();

    List<String?> actions(Finder f) => [
      for (final id
          in tester
                  .getSemantics(f)
                  .getSemanticsData()
                  .customSemanticsActionIds ??
              const <int>[])
        CustomSemanticsAction.getAction(id)?.label,
    ];

    // "Learn German — A2": active and logged by hand.
    expect(actions(find.byType(GoalCard).at(1)), [
      'İlerleme ekle',
      'Düzenle',
      'Bırak',
    ]);

    await tester.tap(find.text('Başarılanlar (1)'));
    await tester.pumpAndSettle();
    expect(actions(find.text('Save 50K in 3 months')), ['Düzenle']);
    await tester.longPress(find.text('Save 50K in 3 months'));
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Bırak'), findsNothing);
    handle.dispose();
  });
}
