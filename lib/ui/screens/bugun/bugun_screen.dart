import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/providers.dart';
import '../../../models/home.dart';
import '../../../models/todo.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/money_text.dart';
import '../../widgets/nokturn_card.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/paced_progress_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/sparkline.dart';
import '../../widgets/stat_chip.dart';
import 'widgets/bugun_common.dart';
import 'widgets/bugun_skeleton.dart';
import 'widgets/event_row.dart';
import 'widgets/home_habit_row.dart';
import 'widgets/quick_capture_sheet.dart';
import 'widgets/todo_row.dart';

class BugunScreen extends ConsumerStatefulWidget {
  const BugunScreen({super.key});

  @override
  ConsumerState<BugunScreen> createState() => _BugunScreenState();
}

class _BugunScreenState extends ConsumerState<BugunScreen> {
  final Set<int> _optimisticTodoDone = {};
  final Set<int> _togglingHabits = {};
  bool _animatedOnce = false;

  Future<void> _refresh() async {
    Haptics.celebrate();
    ref.invalidate(homeProvider);
    try {
      await Future.wait([
        ref.read(homeProvider.future),
        Future.delayed(const Duration(milliseconds: 500)),
      ]);
    } catch (_) {
      // Error surfaces through the AsyncValue; the banner handles it.
    }
  }

  Future<void> _toggleTodo(Todo todo) async {
    if (_optimisticTodoDone.contains(todo.id)) return;
    setState(() => _optimisticTodoDone.add(todo.id));
    // CheckPop fires Haptics.success on the check itself — don't double-fire.
    try {
      await ref.read(repositoryProvider).toggleTodo(todo.id);
      ref.invalidate(homeProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticTodoDone.remove(todo.id));
      showAppSnack(context, 'Görev güncellenemedi', isError: true);
    }
  }

  Future<void> _toggleHabit(HomeHabit habit) async {
    if (_togglingHabits.contains(habit.id)) return;
    // Was the day already complete before this tap? Used to fire the
    // all-done celebration only on the transition (the last remaining habit).
    final pre = ref.read(homeProvider).value?.data.todayHabits.take(6).toList() ??
        const <HomeHabit>[];
    final wasAllDone = pre.isNotEmpty && pre.every((h) => h.completedToday);
    setState(() => _togglingHabits.add(habit.id));
    try {
      // CheckPop fires Haptics.success on the completing tap — don't double-fire.
      await ref.read(repositoryProvider).toggleHabitToday(
            habit.id,
            delta: habit.targetCount > 1 ? 1 : null,
          );
      ref.invalidate(homeProvider);
      final fresh = await ref.read(homeProvider.future);
      final now = fresh.data.todayHabits.take(6).toList();
      final nowAllDone = now.isNotEmpty && now.every((h) => h.completedToday);
      if (!wasAllDone && nowAllDone) Haptics.celebrate();
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Alışkanlık güncellenemedi', isError: true);
      }
    } finally {
      if (mounted) setState(() => _togglingHabits.remove(habit.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final async = ref.watch(homeProvider);
    final fetched = async.value;

    Widget body;
    if (fetched != null) {
      body = _content(
        context,
        fetched.data,
        showOffline: async.hasError,
        lastUpdated: fetched.at,
      );
    } else if (async.hasError) {
      body = _errorState(context);
    } else {
      body = const BugunSkeleton();
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(bottom: false, child: body),
    );
  }

  Widget _errorState(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off,
      title: 'Sunucuya ulaşılamıyor',
      subtitle: 'Aynı Wi-Fi ağında olduğundan emin ol',
      actionLabel: 'Tekrar dene',
      onAction: () => ref.invalidate(homeProvider),
      secondaryLabel: 'Sunucu ayarları',
      onSecondary: () => context.push('/profil/sunucu'),
    );
  }

  Widget _content(
    BuildContext context,
    HomeSummary data, {
    required bool showOffline,
    required DateTime lastUpdated,
  }) {
    final c = context.nok;
    final animate = !_animatedOnce;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animatedOnce = true;
      });
    }

    return Column(
      children: [
        if (showOffline)
          OfflineBanner(
            lastUpdated: lastUpdated,
            onRetry: () => ref.invalidate(homeProvider),
          ),
        Expanded(
          child: RefreshIndicator.adaptive(
            color: c.gold,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _appBar(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _stagger(_hero(context, data), 0, animate),
                      const SizedBox(height: 12),
                      _stagger(_statStrip(context, data), 1, animate),
                      const SizedBox(height: 32),
                      _stagger(_bugunSection(context, data), 2, animate),
                      const SizedBox(height: 32),
                      _stagger(_habitsSection(context, data), 3, animate),
                      const SizedBox(height: 32),
                      _stagger(_hedeflerSection(context, data), 4, animate),
                    ]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stagger(Widget child, int index, bool animate) {
    if (!animate) return child;
    return child
        .animate()
        .fadeIn(duration: 300.ms, delay: (50 * index).ms)
        .slideY(
          begin: 0.06,
          duration: 300.ms,
          delay: (50 * index).ms,
          curve: Curves.easeOutCubic,
        );
  }

  // --- App bar ---------------------------------------------------------------

  Widget _appBar(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final greeting = greetingForHour(DateTime.now().hour);
    final name = user?.displayName ?? '';
    final initials = user?.initials ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: text.bodyMedium!.copyWith(color: c.inkMid)),
                if (name.isNotEmpty)
                  Text(
                    name,
                    style: text.headlineLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showQuickCaptureSheet(context, ref),
            icon: const Icon(Icons.bolt),
            color: c.gold,
            tooltip: 'Hızlı kayıt',
          ),
          const SizedBox(width: 4),
          _Avatar(initials: initials, onTap: () => context.push('/profil')),
        ],
      ),
    );
  }

  // --- Hero ------------------------------------------------------------------

  Widget _hero(BuildContext context, HomeSummary data) {
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BU AY NET', style: text.labelMedium),
          const SizedBox(height: 8),
          MoneyText(
            data.monthNetCents,
            currency: data.currency,
            subunitToUnit: data.subunitToUnit,
            variant: MoneyVariant.hero,
            signed: true,
            positiveGreen: true,
          ),
          const SizedBox(height: 12),
          Sparkline(
            values: data.spending7d.map((p) => p.cents.toDouble()).toList(),
          ),
        ],
      ),
    );
  }

  // --- Stat strip ------------------------------------------------------------

  Widget _statStrip(BuildContext context, HomeSummary data) {
    return Row(
      children: [
        Expanded(
          child: StatChip(
            value: '🔥 ${data.activeStreaks}',
            label: 'seri',
            onTap: () => context.go('/aliskanliklar'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatChip(
            value: '${data.openTodos}',
            label: 'açık görev',
            onTap: () => _showTodosSheet(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatChip(
            value: '%${data.habitCompletionPct}',
            label: 'hafta',
            onTap: () => context.go('/aliskanliklar'),
          ),
        ),
      ],
    );
  }

  // --- "Bugün" section -------------------------------------------------------

  Widget _bugunSection(BuildContext context, HomeSummary data) {
    final todos = data.upcomingTodos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Bugün',
          onSeeAll: todos.isEmpty ? null : () => _showTodosSheet(context),
        ),
        _bugunCard(context, data),
      ],
    );
  }

  Widget _bugunCard(BuildContext context, HomeSummary data) {
    final events = [...data.todayEvents]
      ..sort((a, b) => (a.allDay ? 0 : 1).compareTo(b.allDay ? 0 : 1));
    final rows = <Widget>[
      for (final e in events.take(4)) EventRow(event: e),
      for (final t in data.upcomingTodos)
        TodoRow(
          todo: t,
          done: _optimisticTodoDone.contains(t.id),
          onToggle: () => _toggleTodo(t),
        ),
    ];

    if (rows.isEmpty) {
      return _emptyCard(
        context,
        Icons.wb_sunny_outlined,
        'Bugün plan yok — sakin bir gün ☁',
      );
    }

    return NokturnCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _withDividers(rows),
    );
  }

  // --- "Alışkanlıklar" section ----------------------------------------------

  Widget _habitsSection(BuildContext context, HomeSummary data) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final habits = data.todayHabits.take(6).toList();
    final allDone = habits.isNotEmpty && habits.every((h) => h.completedToday);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Alışkanlıklar',
          trailing: allDone
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.goldContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '✦ Hepsi tamam',
                    style: text.labelSmall!.copyWith(color: c.onGoldContainer),
                  ),
                )
              : null,
        ),
        if (habits.isEmpty)
          _emptyCard(
            context,
            Icons.check_circle_outline,
            'Henüz alışkanlık yok — küçük başla',
          )
        else
          NokturnCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _withDividers([
              for (final h in habits)
                HomeHabitRow(
                  habit: h,
                  busy: _togglingHabits.contains(h.id),
                  onToggle: () => _toggleHabit(h),
                ),
            ]),
          ),
      ],
    );
  }

  // --- "Hedefler" section ----------------------------------------------------

  Widget _hedeflerSection(BuildContext context, HomeSummary data) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final goals = data.activeGoals.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Hedefler'),
        if (goals.isEmpty)
          _emptyCard(
            context,
            Icons.flag_outlined,
            'Henüz hedef yok — ilk hedefini koy',
          )
        else
          NokturnCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _withDividers([
              for (final g in goals)
                InkWell(
                  onTap: () => context.push('/hedefler/${g.id}'),
                  splashColor: c.gold.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.name,
                                style: text.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              PacedProgressBar(
                                value: g.progressPercent / 100,
                                color: hexColor(g.color, fallback: c.gold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '%${g.progressPercent.round()}',
                          style: text.labelSmall!.copyWith(color: c.inkMid),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
      ],
    );
  }

  // --- Helpers ---------------------------------------------------------------

  /// Warm inline empty-section card: friendly icon over Turkish copy.
  Widget _emptyCard(BuildContext context, IconData icon, String message) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return NokturnCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: c.inkLow),
            const SizedBox(height: 10),
            Text(
              message,
              style: text.bodyMedium!.copyWith(color: c.inkLow),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _withDividers(List<Widget> rows) {
    final c = context.nok;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(
          height: 1,
          thickness: 1,
          indent: 20,
          endIndent: 20,
          color: c.divider,
        ));
      }
      children.add(rows[i]);
    }
    return Column(children: children);
  }

  /// Opens the full open-todo list (fetched from [todosProvider], not the home
  /// preview subset) in a §3 modal bottom sheet.
  void _showTodosSheet(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      backgroundColor: c.surface3,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: c.inkFaint,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Açık görevler', style: text.titleLarge),
              ),
            ),
            Flexible(
              child: Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(todosProvider('today'));
                  final bundle = async.value?.data;
                  if (bundle != null) {
                    final todos = bundle.todos;
                    if (todos.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Text(
                          'Açık görev yok — hepsi tamam ✦',
                          style: text.bodyMedium!.copyWith(color: c.inkLow),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: todos.length,
                      itemBuilder: (_, i) => _SheetTodoRow(todo: todos[i]),
                    );
                  }
                  if (async.hasError) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'Görevler yüklenemedi',
                        style: text.bodyMedium!.copyWith(color: c.inkLow),
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator.adaptive(),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final VoidCallback onTap;

  const _Avatar({required this.initials, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.goldContainer,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: text.labelMedium!.copyWith(
            color: c.gold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Read-only row for the "Yaklaşan görevler" sheet.
class _SheetTodoRow extends StatelessWidget {
  final Todo todo;

  const _SheetTodoRow({required this.todo});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final edge = priorityEdgeColor(c, todo.priority);
    final due = todo.dueAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: edge == Colors.transparent ? c.inkFaint : edge,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.title,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (due != null)
                  Text(
                    relativeDay(due),
                    style: text.bodySmall!.copyWith(
                      color: todo.overdue ? c.error : c.inkMid,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
