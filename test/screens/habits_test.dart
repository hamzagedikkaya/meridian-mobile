import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:meridian_mobile/data/providers.dart';
import 'package:meridian_mobile/models/habit.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';
import 'package:meridian_mobile/ui/screens/habits/habits_screen.dart';

/// A rich /habits payload, shaped exactly like scratchpad/api-samples.json,
/// exercising the edge cases the screen must survive:
///   - habit 50: daily, target_count 5  → CounterPill
///   - habit 46: weekly, target_count 3 → period pill (no daily chain)
///   - habit 49: weekly, target_count 1 → HabitCheck + period pill
///   - habit 44: daily, 14-day chain all "missed"
///   - habit 45: daily, single-element chain
///   - perfect_day: 30-day chain with mixed statuses
const String _populatedJson = r'''
{
  "habits": [
    {
      "id": 50, "name": "5ee", "description": "ee", "frequency": "daily",
      "target_count": 5, "color": "#b8860b", "goal_id": null,
      "current_streak": 0, "longest_streak": 1, "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 2 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ]
    },
    {
      "id": 46, "name": "Günde 2L su iç ve bol bol yürü", "description": "",
      "frequency": "weekly", "target_count": 3, "color": "#6b8e5a",
      "goal_id": null, "current_streak": 0, "longest_streak": 14,
      "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ],
      "period": {
        "range_start": "2026-07-06", "range_end": "2026-07-12",
        "completed_count": 2, "complete": false
      }
    },
    {
      "id": 49, "name": "Gym session", "description": "Three times per week.",
      "frequency": "weekly", "target_count": 1, "color": "#B85450",
      "goal_id": null, "current_streak": 0, "longest_streak": 7,
      "completion_rate_30d": 1.0,
      "today": { "date": "2026-07-11", "completed": true, "count": 1 },
      "chain": [ { "date": "2026-07-11", "status": "today_pending" } ],
      "period": {
        "range_start": "2026-07-06", "range_end": "2026-07-12",
        "completed_count": 1, "complete": true
      }
    },
    {
      "id": 44, "name": "Morning workout", "description": "Stretch + yoga.",
      "frequency": "daily", "target_count": 1, "color": "#D4A574",
      "goal_id": null, "current_streak": 0, "longest_streak": 7,
      "completion_rate_30d": 0.0,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [
        { "date": "2026-06-28", "status": "missed" },
        { "date": "2026-06-29", "status": "missed" },
        { "date": "2026-06-30", "status": "missed" },
        { "date": "2026-07-01", "status": "missed" },
        { "date": "2026-07-02", "status": "missed" },
        { "date": "2026-07-03", "status": "missed" },
        { "date": "2026-07-04", "status": "missed" },
        { "date": "2026-07-05", "status": "missed" },
        { "date": "2026-07-06", "status": "missed" },
        { "date": "2026-07-07", "status": "missed" },
        { "date": "2026-07-08", "status": "missed" },
        { "date": "2026-07-09", "status": "missed" },
        { "date": "2026-07-10", "status": "missed" },
        { "date": "2026-07-11", "status": "missed" }
      ]
    },
    {
      "id": 45, "name": "Read 30 pages", "description": "Fiction.",
      "frequency": "daily", "target_count": 1, "color": "#6B8FA0",
      "goal_id": null, "current_streak": 3, "longest_streak": 7,
      "completion_rate_30d": 0.42,
      "today": { "date": "2026-07-11", "completed": false, "count": 0 },
      "chain": [ { "date": "2026-07-11", "status": "completed" } ]
    }
  ],
  "meta": {
    "completed_today": 1,
    "total_active": 5,
    "perfect_day": {
      "chain": [
        { "date": "2026-06-12", "status": "perfect" },
        { "date": "2026-06-13", "status": "partial" },
        { "date": "2026-06-14", "status": "missed" },
        { "date": "2026-06-15", "status": "completed" },
        { "date": "2026-06-16", "status": "no_habits" },
        { "date": "2026-06-17", "status": "today_pending" }
      ],
      "current_streak": 2,
      "longest_streak": 9
    }
  }
}
''';

/// Empty case: no habits, zero counters, empty perfect-day chain.
const String _emptyJson = r'''
{
  "habits": [],
  "meta": {
    "completed_today": 0,
    "total_active": 0,
    "perfect_day": { "chain": [], "current_streak": 0, "longest_streak": 0 }
  }
}
''';

/// All-complete case (X == Y): every habit done, single-element perfect chain.
/// Exercises the "Hepsi tamam" badge + pct==1.0 progress bar on first build,
/// and the confetti guard (must NOT fire on build, only on transition).
const String _allDoneJson = r'''
{
  "habits": [
    {
      "id": 60, "name": "Sabah esnemesi", "description": "",
      "frequency": "daily", "target_count": 1, "color": "#D4A853",
      "goal_id": null, "current_streak": 5, "longest_streak": 5,
      "completion_rate_30d": 1.0,
      "today": { "date": "2026-07-11", "completed": true, "count": 1 },
      "chain": [ { "date": "2026-07-11", "status": "completed" } ]
    }
  ],
  "meta": {
    "completed_today": 1,
    "total_active": 1,
    "perfect_day": {
      "chain": [ { "date": "2026-07-11", "status": "perfect" } ],
      "current_streak": 1,
      "longest_streak": 1
    }
  }
}
''';

HabitsBundle _bundle(String json) =>
    HabitsBundle.fromJson(jsonDecode(json) as Map<String, dynamic>);

Widget _app(HabitsBundle bundle) {
  return ProviderScope(
    overrides: [
      habitsProvider.overrideWith(
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
      home: const HabitsScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets('renders populated habits with all edge-case shapes', (t) async {
    await t.pumpWidget(_app(_bundle(_populatedJson)));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);

    // App bar + today-card header ("1 / 5 tamamlandı").
    expect(find.text('Alışkanlıklar'), findsOneWidget);
    expect(find.text('1 / 5 tamamlandı'), findsOneWidget);

    // Perfect-day chain caption with the real streak/record numbers.
    expect(find.text('Mükemmel gün zinciri'), findsOneWidget);
    expect(
      find.text('Mükemmel seri: 🔥 2 · Rekor: 9'),
      findsOneWidget,
    );

    // A long Turkish habit name renders (ellipsis-clamped, no overflow throw).
    expect(find.text('Günde 2L su iç ve bol bol yürü'), findsOneWidget);

    // Weekly habit period pills ("Bu hafta n/target").
    expect(find.text('Bu hafta 2/3'), findsOneWidget);
    expect(find.text('Bu hafta 1/1'), findsOneWidget);

    // CounterPill for the target_count>1 daily habit.
    expect(find.text('2/5'), findsOneWidget);
  });

  testWidgets('renders empty state without exception', (t) async {
    await t.pumpWidget(_app(_bundle(_emptyJson)));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('İlk alışkanlığını oluştur'), findsOneWidget);
    expect(find.text('Alışkanlık ekle'), findsOneWidget);
  });

  testWidgets('renders all-complete (X==Y) without confetti crash', (t) async {
    await t.pumpWidget(_app(_bundle(_allDoneJson)));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // pct==1.0 progress bar + "Hepsi tamam" badge.
    expect(find.text('1 / 1 tamamlandı'), findsOneWidget);
    expect(find.text('✦ Hepsi tamam'), findsOneWidget);
  });
}
