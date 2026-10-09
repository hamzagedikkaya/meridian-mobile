@Tags(['golden'])
/// The number, progress, check, chart, skeleton and agenda-row components
/// (design-analysis §4.6, §4.19–4.26), dark and light.
///
/// Shot by `golden_harness.dart` (clock, fonts, matrix); see it for how to
/// run and refresh. Owned by WP-3.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/core/formats.dart';
import 'package:meridian_mobile/models/event.dart';
import 'package:meridian_mobile/models/todo.dart';
import 'package:meridian_mobile/theme/app_colors.dart';
import 'package:meridian_mobile/theme/entity_color.dart';
import 'package:meridian_mobile/ui/widgets/agenda_rows.dart';
import 'package:meridian_mobile/ui/widgets/category_bars.dart';
import 'package:meridian_mobile/ui/widgets/charts.dart';
import 'package:meridian_mobile/ui/widgets/check_pop.dart';
import 'package:meridian_mobile/ui/widgets/day_header.dart';
import 'package:meridian_mobile/ui/widgets/money_text.dart';
import 'package:meridian_mobile/ui/widgets/paced_progress_bar.dart';
import 'package:meridian_mobile/ui/widgets/pace_line.dart';
import 'package:meridian_mobile/ui/widgets/progress_ring.dart';
import 'package:meridian_mobile/ui/widgets/skeletons.dart';

import 'golden_harness.dart';

const _variants = [
  GoldenVariant.trDark,
  GoldenVariant.enDark,
  GoldenVariant.trLight,
  GoldenVariant.trDarkLarge,
];

/// A labelled section of the gallery.
class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelMedium!.copyWith(color: c.inkLow),
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

Widget _page(List<Widget> sections) => Builder(
  builder: (context) => Scaffold(
    backgroundColor: context.nok.bg,
    body: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: sections,
        ),
      ),
    ),
  ),
);

Widget _pad(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
  child: child,
);

void main() {
  setUpGoldens();

  goldenScreen('motion_numbers', variants: _variants, (tester, v) async {
    await tester.pumpWidget(
      goldenHost(
        _page([
          _Section('HERO · DISPLAY · TITLE', [
            _pad(
              const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 280,
                  child: MoneyText(
                    123456789,
                    currency: 'TRY',
                    subunitToUnit: 100,
                    variant: MoneyVariant.hero,
                    signed: true,
                  ),
                ),
              ),
            ),
            _pad(
              const MoneyText(
                -25000,
                currency: 'TRY',
                subunitToUnit: 100,
                variant: MoneyVariant.display,
              ),
            ),
            _pad(
              const MoneyText(
                0,
                currency: 'TRY',
                subunitToUnit: 100,
                variant: MoneyVariant.title,
                signed: true,
              ),
            ),
          ]),
          _Section('ROW · META', [
            _pad(
              const Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  MoneyText(
                    150000,
                    currency: 'TRY',
                    subunitToUnit: 100,
                    signed: true,
                  ),
                  MoneyText(
                    4275000,
                    currency: 'TRY',
                    subunitToUnit: 100,
                    decimals: MoneyDecimals.auto,
                  ),
                  MoneyText(
                    412,
                    currency: 'GAU',
                    subunitToUnit: 1,
                    variant: MoneyVariant.meta,
                  ),
                  MoneyText(
                    123456,
                    currency: 'CHF',
                    subunitToUnit: 100,
                    variant: MoneyVariant.meta,
                  ),
                  MoneyText(
                    -999,
                    currency: 'USD',
                    subunitToUnit: 100,
                    variant: MoneyVariant.meta,
                  ),
                ],
              ),
            ),
            _pad(
              Builder(
                builder: (context) => Text(
                  [
                    formatMoneyCompact(999900, 'TRY', 100),
                    formatMoneyCompact(4750000, 'TRY', 100),
                    formatMoneyCompact(120000000, 'TRY', 100),
                    formatPercent(62),
                  ].join('  ·  '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ]),
          _Section('CHECK', [
            _pad(
              Row(
                children: [
                  CheckPop(
                    checked: false,
                    color: const Color(0xFF6B8E5A),
                    onToggle: () {},
                  ),
                  CheckPop(
                    checked: true,
                    color: const Color(0xFF6B8E5A),
                    onToggle: () {},
                  ),
                  CheckPop(
                    checked: true,
                    color: const Color(0xFFD4A853),
                    onToggle: () {},
                  ),
                  const SizedBox(width: 12),
                  CheckPop.checkbox(
                    checked: false,
                    color: const Color(0xFFD4A853),
                    onToggle: () {},
                  ),
                  const SizedBox(width: 12),
                  CheckPop.checkbox(
                    checked: true,
                    color: const Color(0xFFD4A853),
                    onToggle: () {},
                  ),
                ],
              ),
            ),
          ]),
          _Section('PROGRESS', [
            _pad(
              Builder(
                builder: (context) {
                  final sage = entityTone('#6B8E5A', context.nok).fill;
                  final blue = entityTone('#6B8FA0', context.nok).fill;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ProgressRing(
                        value: 0.62,
                        color: sage,
                        size: 16,
                        strokeWidth: 2,
                      ),
                      ProgressRing(
                        value: 3 / 5,
                        color: sage,
                        size: 40,
                        strokeWidth: 3,
                        segments: 5,
                      ),
                      ProgressRing(
                        value: 0.62,
                        color: blue,
                        center: Text(
                          formatPercent(62),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _pad(
              Builder(
                builder: (context) => Column(
                  children: [
                    PacedProgressBar(
                      value: 0.45,
                      color: context.nok.gold,
                      paceTick: 0.6,
                    ),
                    const SizedBox(height: 14),
                    PacedProgressBar(
                      value: 0.4,
                      color: context.nok.gold,
                      committed: 0.25,
                    ),
                    const SizedBox(height: 14),
                    PacedProgressBar(
                      value: 1,
                      color: context.nok.gold,
                      over: true,
                    ),
                    const SizedBox(height: 14),
                    PacedProgressBar(
                      value: 0.7,
                      color: context.nok.income,
                      height: 8,
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ]),
        [],
      ),
    );
    await tester.pumpAndSettle();
  });

  goldenScreen('motion_charts', variants: _variants, (tester, v) async {
    final en = v.lang == 'en';
    await tester.pumpWidget(
      goldenHost(
        _page([
          _Section('SIX MONTHS', [
            _pad(
              SixMonthBars(
                labels: en
                    ? const ['May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct']
                    : const ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'],
                incomeCents: const [
                  5200000,
                  5200000,
                  5400000,
                  5400000,
                  5780000,
                  5780000,
                ],
                expenseCents: const [
                  3100000,
                  3600000,
                  2900000,
                  3800000,
                  3320000,
                  1240000,
                ],
                currency: 'TRY',
                subunitToUnit: 100,
                height: 150,
              ),
            ),
          ]),
          _Section('CATEGORIES', [
            Builder(
              builder: (context) {
                final c = context.nok;
                return CategoryBars(
                  currency: 'TRY',
                  subunitToUnit: 100,
                  onCategorize: () {},
                  items: [
                    CategoryBarItem(
                      name: en ? 'Groceries' : 'Market',
                      cents: 842000,
                      color: entityTone('#6B8E5A', c).fill,
                    ),
                    CategoryBarItem(
                      name: en ? 'Rent' : 'Kira',
                      cents: 650000,
                      color: entityTone('#6B8FA0', c).fill,
                    ),
                    CategoryBarItem(
                      name: en ? 'Other' : 'Diğer',
                      cents: 210000,
                      kind: CategoryBarKind.other,
                    ),
                    CategoryBarItem(
                      name: en ? 'Uncategorized' : 'Kategorisiz',
                      cents: 95000,
                      kind: CategoryBarKind.uncategorized,
                    ),
                  ],
                );
              },
            ),
          ]),
          _Section('PACE', [
            _pad(
              PaceLine(
                spent: [
                  for (var d = 1; d <= 4; d++)
                    210000 * d + (d.isEven ? 40000 : 0),
                ],
                reference: [for (var d = 1; d <= 30; d++) 190000 * d],
                daysInMonth: 31,
                month: goldenNow,
                currency: 'TRY',
                subunitToUnit: 100,
              ),
            ),
          ]),
          _Section('SKELETON', [
            _pad(
              const Row(
                children: [
                  Bone.circle(size: 40),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Bone.text(width: 160, lineHeight: 22),
                        SizedBox(height: 6),
                        Bone.text(width: 96),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _pad(const Bone(height: 64, shape: BoneShape.card)),
          ]),
        ]),
        [],
      ),
    );
    // The bones breathe for ever: stop on a full breath (2 × 1200 ms),
    // after every entrance has finished.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
  });

  goldenScreen('motion_agenda_rows', variants: _variants, (tester, v) async {
    final en = v.lang == 'en';
    Todo todo(
      int id,
      String title,
      String priority, {
      String status = 'pending',
      bool overdue = false,
      int dueIn = 0,
    }) => Todo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'priority': priority,
      'overdue': overdue,
      'due_date': ymd(daysAhead(dueIn)),
      'todo_list': {'id': 1, 'name': en ? 'Home' : 'Ev', 'color': '#B85450'},
    });
    Event event(
      int id,
      String title, {
      bool allDay = false,
      String? rule,
      String? location,
    }) => Event.fromJson({
      'id': id,
      'title': title,
      'all_day': allDay,
      'start_at': allDay ? ymd(goldenNow) : '${ymd(goldenNow)}T10:00:00+03:00',
      'duration_minutes': allDay ? null : 75,
      'color': id.isEven ? '#6B8FA0' : '#7A5C9E',
      'location': location,
      'recurrence_rule': rule,
      'occurrences': const [],
    });
    await tester.pumpWidget(
      goldenHost(
        _page([
          Builder(
            builder: (context) => DayHeader.overdue(
              label: en ? 'Overdue' : 'Gecikmiş',
              count: '1',
              onMoveAllToToday: () {},
            ),
          ),
          TodoRow(
            todo: todo(
              1,
              en ? 'Send the tax return' : 'Vergi beyannamesini gönder',
              'high',
              overdue: true,
              dueIn: -1,
            ),
            done: false,
            onToggle: () {},
            onTap: () {},
          ),
          Builder(
            builder: (context) => DayHeader.forDay(
              context,
              goldenNow,
              today: goldenNow,
              trailing: '−₺1.240',
            ),
          ),
          EventRow(
            event: event(
              2,
              en ? 'Design review' : 'Tasarım incelemesi',
              rule: 'FREQ=WEEKLY',
              location: en ? 'Office' : 'Ofis',
            ),
            day: goldenNow,
            onTap: () {},
          ),
          EventRow(
            event: event(
              3,
              en ? 'Mum’s birthday' : 'Annemin doğum günü',
              allDay: true,
            ),
            day: goldenNow,
            onTap: () {},
          ),
          TodoRow(
            todo: todo(4, en ? 'Buy groceries' : 'Market alışverişi', 'urgent'),
            done: false,
            onToggle: () {},
            onTap: () {},
          ),
          TodoRow(
            todo: todo(
              5,
              en ? 'Call the bank' : 'Bankayı ara',
              'low',
              status: 'done',
            ),
            done: true,
            onToggle: () {},
            onTap: () {},
          ),
          Builder(
            builder: (context) =>
                DayHeader.forDay(context, daysAhead(1), today: goldenNow),
          ),
          TodoRow(
            todo: todo(
              6,
              en ? 'Plan the week' : 'Haftayı planla',
              'medium',
              dueIn: 1,
            ),
            done: false,
            onToggle: () {},
            onTap: () {},
          ),
        ]),
        [],
      ),
    );
    await tester.pumpAndSettle();
  });
}
