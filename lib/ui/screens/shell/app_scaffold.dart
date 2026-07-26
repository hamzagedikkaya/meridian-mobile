import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../data/providers.dart';
import '../../../theme/app_colors.dart';

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.label, this.icon, this.activeIcon);
}

const _tabs = [
  _Tab('Bugün', Icons.wb_sunny_outlined, Icons.wb_sunny),
  _Tab('Para', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet),
  _Tab('Alışkanlıklar', Icons.check_circle_outline, Icons.check_circle),
  _Tab('Hedefler', Icons.flag_outlined, Icons.flag),
  _Tab('Günlük', Icons.auto_stories_outlined, Icons.auto_stories),
];

class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const AppScaffold({super.key, required this.shell});

  void _onTap(int index) {
    Haptics.tick();
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.nok;
    final overdue = ref.watch(homeProvider).value?.data.overdueCount ?? 0;

    return Scaffold(
      body: shell,
      // Section-3 top hairline separating the bar from content.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _onTap,
          destinations: [
            for (var i = 0; i < _tabs.length; i++)
              NavigationDestination(
                icon: _icon(context, Icon(_tabs[i].icon), i, overdue),
                selectedIcon:
                    _icon(context, Icon(_tabs[i].activeIcon), i, overdue),
                label: _tabs[i].label,
              ),
          ],
        ),
      ),
    );
  }

  // Only Bugün (index 0) carries the error-colored overdue count badge.
  Widget _icon(BuildContext context, Icon icon, int index, int overdue) {
    if (index != 0 || overdue <= 0) return icon;
    return Badge(
      backgroundColor: context.nok.error,
      label: Text('$overdue'),
      child: icon,
    );
  }
}
