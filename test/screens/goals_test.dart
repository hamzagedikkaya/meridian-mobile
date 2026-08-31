import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/goal.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/goals/goals_screen.dart';

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
}) =>
    {
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

Widget _app(GoalsBundle bundle) {
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
      home: const GoalsScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders the populated goals grid without exceptions',
      (tester) async {
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

  testWidgets('renders an achieved-only list (empty active) safely',
      (tester) async {
    await tester.pumpWidget(_app(GoalsBundle.fromJson(_achievedOnly)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No active grid header, but the collapsed achieved section is present.
    expect(find.text('Aktif'), findsNothing);
    expect(find.text('Başarılanlar (1)'), findsOneWidget);
  });
}
