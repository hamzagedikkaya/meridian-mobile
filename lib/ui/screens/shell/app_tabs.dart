import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../data/providers.dart';
import '../../../data/sync.dart';
import '../../../theme/app_motion.dart';

/// The bottom-nav tabs, in bar order (the shell's branch indexes):
/// Bugün · Ajanda · Finans · Alışkanlık · Günlük (design-analysis §6.1).
/// Goals is a page pushed over the tabs (`/goals`), not a tab.
enum AppTab {
  today,
  agenda,
  finance,
  habits,
  journal;

  /// The tab's root location — its branch's first route.
  String get location => '/$name';

  /// The read models this tab's screen shows — what a pull-to-refresh or a
  /// re-tap of the tab refetches. A family stands for every instance of it
  /// the screen has open (a todo filter, an event window, a journal range).
  List<ProviderOrFamily> get readModels => switch (this) {
        AppTab.today => [homeProvider, eventsProvider, journalProvider],
        AppTab.agenda => [todosProvider, eventsProvider, todoListsProvider],
        AppTab.finance => [financeDashboardProvider, accountsProvider],
        AppTab.habits => [habitsProvider],
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

/// A tap on the tab that is already selected, while its list is scrolled
/// down: the tab's [TabRootScroll] takes it back to the top.
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

/// For a tab's root screen: owns the controller of its main vertical list
/// and scrolls it back to the top when the tab is tapped again in the
/// bottom bar (§5.2: a re-tap scrolls a scrolled tab to the top; only a
/// re-tap at the top refetches — the shell decides, through
/// [TabRootScroll.isAtTop]).
///
/// Wrap the screen's Scaffold with [primaryScroll] and give the main list
/// `primary: true`, rather than passing the controller to the list: it stays
/// the primary scroll controller, so the iOS status-bar tap still scrolls it
/// to the top as well.
mixin TabRootScroll<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  AppTab get tab;

  final tabScroll = ScrollController();

  /// The mounted tab roots' controllers, by tab.
  static final _roots = <AppTab, List<ScrollController>>{};

  /// Whether [tab]'s root list shows its top — what a re-tap of the tab
  /// does depends on it. Read from the lists attached at the moment of the
  /// tap, so a list swapped for another (a view switch, a reload) counts as
  /// it is now. A tab whose root is not mounted, or has no list (or one
  /// not laid out yet), counts as at the top.
  static bool isAtTop(AppTab tab) => (_roots[tab] ?? const []).every(
        (controller) => controller.positions.every(
          (p) => !p.hasPixels || p.pixels <= p.minScrollExtent + 0.5,
        ),
      );

  @override
  void initState() {
    super.initState();
    _roots.putIfAbsent(tab, () => []).add(tabScroll);
    // A manual listener: it outlives build passes and closes on unmount.
    ref.listenManual(tabReselectProvider, (_, event) {
      if (event?.tab == tab) scrollToTop();
    });
  }

  /// Back to the top in [Motion.standard]. From far down (past two
  /// screenfuls) it first jumps to 1.5 screenfuls, so the ride stays short;
  /// under reduced motion it jumps straight there.
  void scrollToTop() {
    final reduced = Motion.reduced(context);
    for (final position in tabScroll.positions.toList()) {
      if (!position.hasPixels || !position.hasViewportDimension) continue;
      final top = position.minScrollExtent;
      if (reduced) {
        position.jumpTo(top);
        continue;
      }
      final viewport = position.viewportDimension;
      if (position.pixels - top > 2 * viewport) {
        position.jumpTo(top + 1.5 * viewport);
      }
      position.animateTo(top, duration: Motion.standard, curve: Motion.enter);
    }
  }

  Widget primaryScroll(Widget child) =>
      PrimaryScrollController(controller: tabScroll, child: child);

  @override
  void dispose() {
    final roots = _roots[tab];
    roots?.remove(tabScroll);
    if (roots != null && roots.isEmpty) _roots.remove(tab);
    tabScroll.dispose();
    super.dispose();
  }
}
