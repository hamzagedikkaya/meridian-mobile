import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import 'app_tabs.dart';
import 'freshness_gate.dart';

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.label, this.icon, this.activeIcon);
}

List<_Tab> _tabsFor(AppL10n l) => [
      _Tab(l.tabToday, Icons.wb_sunny_outlined, Icons.wb_sunny),
      _Tab(l.tabFinance, Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet),
      _Tab(l.tabHabits, Icons.check_circle_outline, Icons.check_circle),
      _Tab(l.tabGoals, Icons.flag_outlined, Icons.flag),
      _Tab(l.tabJournal, Icons.auto_stories_outlined, Icons.auto_stories),
    ];

class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const AppScaffold({super.key, required this.shell});

  /// A tap on another tab switches to it. A tap on the selected tab scrolls
  /// it back to the top and refetches what it shows; its data stays on
  /// screen until the new data lands.
  void _onTap(WidgetRef ref, int index) {
    Haptics.tick();
    final tab = AppTab.values[index];
    final reselect = index == shell.currentIndex;
    if (reselect) {
      refreshTab(ref, tab);
      ref.read(tabReselectProvider.notifier).fire(tab);
    } else if (tab == AppTab.today) {
      _revalidateHome(ref);
    }
    shell.goBranch(index, initialLocation: reselect);
  }

  /// Switching back to Today refetches `/home` in the background when it is
  /// older than [staleAfter], as every screen does when it is shown again —
  /// that is what brings in edits made on the web meanwhile.
  ///
  /// Other tabs get this from their read models (see `RevalidateOnShow`):
  /// a hidden tab's model is paused and Riverpod sees it resume. `/home`
  /// never pauses while the bar is up — the badge below watches it under
  /// every tab — so the bar checks it here.
  void _revalidateHome(WidgetRef ref) {
    final home = ref.read(homeProvider);
    final fetched = home.value;
    if (fetched == null || home.isLoading) return;
    if (fetched.olderThan(staleAfter, ref.read(clockProvider)())) {
      ref.read(dataSyncProvider).refresh([homeProvider]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final tabs = _tabsFor(context.l10n);
    // Watching keeps /home live while the shell is visible, so a write on
    // any tab refreshes Today (and this badge) before the user switches back
    // — and is why switching back checks its age itself (see _onTap).
    final overdue = ref.watch(
        homeProvider.select((home) => home.value?.data.overdueCount ?? 0));

    return Scaffold(
      body: FreshnessGate(child: shell),
      // Section-3 top hairline separating the bar from content.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => _onTap(ref, index),
          destinations: [
            for (var i = 0; i < tabs.length; i++)
              NavigationDestination(
                icon: _icon(context, Icon(tabs[i].icon), i, overdue),
                selectedIcon:
                    _icon(context, Icon(tabs[i].activeIcon), i, overdue),
                label: tabs[i].label,
              ),
          ],
        ),
      ),
    );
  }

  // Only the first tab (Today) carries the error-colored overdue count badge.
  Widget _icon(BuildContext context, Icon icon, int index, int overdue) {
    if (index != 0 || overdue <= 0) return icon;
    return Badge(
      backgroundColor: context.nok.error,
      label: Text('$overdue'),
      child: icon,
    );
  }
}
