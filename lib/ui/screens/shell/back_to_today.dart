import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_tabs.dart';

/// For a page pushed over the tabs on the root navigator (Goals, Search)
/// that can also be the only page there: opened by a deep link or a `go`,
/// or come back to after signing in again (`/login?from=`). With no shell
/// under it, back would leave the app; instead its back arrow and the
/// system back go to Today (§6.1, §6.2: Goals has an automatic back arrow).
///
/// Over the shell — the usual way in — it changes nothing. On its own, the
/// page's route gets a local history entry: the AppBar shows its back
/// arrow for it, and the pop it takes (button, system back, predictive
/// back) goes to `/today` instead.
class BackToToday extends StatefulWidget {
  final Widget child;

  const BackToToday({super.key, required this.child});

  @override
  State<BackToToday> createState() => _BackToTodayState();
}

class _BackToTodayState extends State<BackToToday> {
  ModalRoute<Object?>? _route;
  LocalHistoryEntry? _entry;

  /// Set while the entry is taken off here, not by a back.
  bool _releasing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    // Added after the frame: the route rebuilds its scope for it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    final route = _route;
    final alone = route != null && route.isActive && route.isFirst;
    final entry = _entry;
    if (alone && entry == null) {
      final router = GoRouter.of(context);
      final added = LocalHistoryEntry(
        onRemove: () {
          if (_releasing) return;
          _entry = null;
          // Not in the middle of the navigator's pop.
          scheduleMicrotask(() => router.go(AppTab.today.location));
        },
      );
      _entry = added;
      route.addLocalHistoryEntry(added);
    } else if (!alone && entry != null) {
      _release();
    }
  }

  void _release() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _releasing = true;
    entry.remove();
    _releasing = false;
  }

  @override
  void dispose() {
    if (_route?.isActive ?? false) _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
