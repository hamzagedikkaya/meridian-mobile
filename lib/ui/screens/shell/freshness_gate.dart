import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/current_day.dart';
import '../../../data/deferred_deletes.dart';
import '../../../data/sync.dart';

/// Brings the data up to date when the app returns to the foreground.
///
/// Wraps the signed-in shell, so it only runs while there is data to keep
/// fresh. On every return it re-reads the clock — a midnight that passed while
/// the OS had the app suspended (and its timer frozen) rolls the day over now.
/// After more than [awayFor] in the background it also refetches everything
/// (edits made on the web or another device), the signed-in user included:
/// visible screens at once, the other tabs when they are next shown, all
/// keeping their current data on screen until the new data lands.
///
/// It listens for hide/show rather than pause/resume, so pulling down the
/// notification shade or a system dialog does not count as leaving.
///
/// Going to the background also sends the deletes still waiting out their
/// "Geri al" window (see `DeferredDeletes`): the app may not come back to
/// send them.
class FreshnessGate extends ConsumerStatefulWidget {
  final Widget child;
  final Duration awayFor;

  const FreshnessGate({
    super.key,
    required this.child,
    this.awayFor = const Duration(seconds: 30),
  });

  @override
  ConsumerState<FreshnessGate> createState() => _FreshnessGateState();
}

class _FreshnessGateState extends ConsumerState<FreshnessGate> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(clockProvider)();

  void _onHide() {
    _hiddenAt ??= _now();
    final deletes = ref.read(deferredDeletesProvider.notifier);
    if (deletes.hasWaiting) {
      // Their "Geri al" goes with them: the delete is on its way.
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      deletes.commitAll();
    }
  }

  void _onShow() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    ref.read(currentDayProvider.notifier).sync();
    if (hiddenAt == null || _now().difference(hiddenAt) < widget.awayFor) {
      return;
    }
    ref.read(dataSyncProvider).refreshAll();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
