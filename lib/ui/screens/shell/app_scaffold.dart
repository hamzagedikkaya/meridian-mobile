import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// The bar's destinations, in [AppTab] order (icons: design-analysis §3.11).
List<_Tab> _tabsFor(AppL10n l) => [
      _Tab(l.tabToday, Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
      _Tab(l.tabAgenda, Icons.event_note_outlined, Icons.event_note_rounded),
      _Tab(l.tabFinance, Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded),
      _Tab(l.tabHabits, Icons.check_circle_outline_rounded,
          Icons.check_circle_rounded),
      _Tab(l.tabJournal, Icons.auto_stories_outlined,
          Icons.auto_stories_rounded),
    ];

/// The signed-in frame: the selected tab over the bottom bar.
///
/// Back on another tab's root goes to Today first; back on Today leaves
/// the app (§6.1). Tab taps are silent — navigation has no haptic (D38).
class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const AppScaffold({super.key, required this.shell});

  /// A tap on another tab switches to it. A tap on the selected tab takes a
  /// scrolled list back to the top; one already at the top refetches what
  /// the tab shows instead, its data staying on screen until the new data
  /// lands (§5.2).
  void _onTap(WidgetRef ref, int index) {
    final tab = AppTab.values[index];
    final reselect = index == shell.currentIndex;
    if (reselect) {
      if (TabRootScroll.isAtTop(tab)) {
        refreshTab(ref, tab);
      } else {
        ref.read(tabReselectProvider.notifier).fire(tab);
      }
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
  /// never pauses while the bar is up — the Agenda badge below watches it
  /// under every tab — so the bar checks it here.
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
    final l = context.l10n;
    final tabs = _tabsFor(l);
    // Watching keeps /home live while the shell is visible, so a write on
    // any tab refreshes Today (and this badge) before the user switches back
    // — and is why switching back checks its age itself (see _onTap).
    final overdue = ref.watch(overdueBadgeProvider);
    final onToday = shell.currentIndex == AppTab.today.index;

    return PopScope(
      canPop: onToday,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onTap(ref, AppTab.today.index);
      },
      child: Scaffold(
        body: FreshnessGate(child: shell),
        // Section-3 top hairline separating the bar from content.
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          // The labels grow with the text size up to 1.3× (§4.18): at 360 dp
          // each tab has 72 dp, and "Alışkanlık" at 1.3× takes 70.5.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (index) => _onTap(ref, index),
              destinations: [
                for (var i = 0; i < tabs.length; i++)
                  NavigationDestination(
                    icon: _icon(l, Icon(tabs[i].icon), i, overdue),
                    selectedIcon:
                        _icon(l, Icon(tabs[i].activeIcon), i, overdue),
                    label: tabs[i].label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only Agenda — where overdue todos can be dealt with — carries the
  /// overdue count, in the theme's error badge (onError text). A screen
  /// reader hears it after the tab's name: "Ajanda, 3 gecikmiş görev".
  Widget _icon(AppL10n l, Icon icon, int index, int overdue) {
    if (index != AppTab.agenda.index || overdue <= 0) return icon;
    return Semantics(
      value: l.semAgendaOverdue(overdue),
      excludeSemantics: true,
      child: Badge(
        label: Text(overdue > 99 ? '99+' : '$overdue'),
        child: icon,
      ),
    );
  }
}
