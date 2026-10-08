import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../data/providers.dart';
import '../../../data/sync.dart';

/// The bottom-nav tabs, in bar order (the shell's branch indexes).
enum AppTab {
  today,
  finance,
  habits,
  goals,
  journal;

  /// The read models this tab's screen shows — what a pull-to-refresh or a
  /// re-tap of the tab refetches.
  List<ProviderOrFamily> get readModels => switch (this) {
        AppTab.today => [homeProvider, todosProvider, eventsProvider],
        AppTab.finance => [financeDashboardProvider, accountsProvider],
        AppTab.habits => [habitsProvider],
        AppTab.goals => [goalsProvider],
        AppTab.journal => [journalProvider],
      };
}

/// Refetches what [tab] shows, keeping the current data on screen meanwhile.
/// Today summarises every domain, so refreshing it refreshes everything —
/// cheap, because hidden tabs only refetch once they are shown — the
/// signed-in user (the greeting and avatar) included.
void refreshTab(WidgetRef ref, AppTab tab) {
  final sync = ref.read(dataSyncProvider);
  if (tab == AppTab.today) {
    sync.refreshAll();
  } else {
    sync.refresh(tab.readModels);
  }
}

/// A tap on the tab that is already selected.
@immutable
class TabReselect {
  final AppTab tab;

  /// Distinguishes two re-taps of the same tab.
  final int serial;

  const TabReselect(this.tab, this.serial);
}

final tabReselectProvider =
    NotifierProvider<TabReselectNotifier, TabReselect?>(TabReselectNotifier.new);

class TabReselectNotifier extends Notifier<TabReselect?> {
  @override
  TabReselect? build() => null;

  void fire(AppTab tab) => state = TabReselect(tab, (state?.serial ?? 0) + 1);
}

/// For a tab's root screen: owns the controller of its main vertical list and
/// scrolls it back to the top when the tab is tapped again in the bottom bar
/// (the shell refetches the tab's data at the same time).
///
/// Wrap the screen's Scaffold with [primaryScroll] and give the main list
/// `primary: true`, rather than passing the controller to the list: it stays
/// the primary scroll controller, so the iOS status-bar tap still scrolls it
/// to the top as well.
mixin TabRootScroll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  AppTab get tab;

  final tabScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // A manual listener: it outlives build passes and closes on unmount.
    ref.listenManual(tabReselectProvider, (_, event) {
      if (event?.tab == tab) scrollToTop();
    });
  }

  void scrollToTop() {
    for (final position in tabScroll.positions.toList()) {
      position.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget primaryScroll(Widget child) =>
      PrimaryScrollController(controller: tabScroll, child: child);

  @override
  void dispose() {
    tabScroll.dispose();
    super.dispose();
  }
}
