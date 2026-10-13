import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';
import 'app_snackbar.dart';

/// Tracks a screen's scrolling for its [CollapsingFab]: put it around the
/// screen's `Scaffold`, so scroll notifications from the body reach it and
/// the FAB (a sibling of the body) can read it.
///
///     CollapsingFabScope(
///       child: Scaffold(
///         body: ListView(…),
///         floatingActionButton: CollapsingFab(
///             icon: Icons.add_rounded, label: l.fabTransaction, onPressed: add),
///       ),
///     )
///
/// After [threshold] (24 dp) of scrolling down the FAB collapses to its
/// icon; after 24 dp up — or back at the top — it opens again (D22). Only
/// the user's own scrolling counts — a drag and the fling after it, from
/// one `UserScrollNotification` to its idle — not a jump or an
/// `ensureVisible` the app makes; and only on the outermost vertical
/// scrollable. Without a scope the FAB stays extended.
class CollapsingFabScope extends StatefulWidget {
  const CollapsingFabScope({super.key, required this.child});

  final Widget child;

  /// How far the user scrolls in one direction before the FAB changes.
  static const threshold = 24.0;

  /// Whether the FAB under [context] is collapsed; false without a scope.
  static bool collapsedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CollapsingFabInherited>()
          ?.collapsed ??
      false;

  @override
  State<CollapsingFabScope> createState() => _CollapsingFabScopeState();
}

class _CollapsingFabScopeState extends State<CollapsingFabScope> {
  bool _collapsed = false;

  /// Scrolled in the current direction so far (+ down, − up).
  double _run = 0;

  /// The user is scrolling: a drag, or the fling it let go into.
  bool _userScrolling = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
    }
    if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      _run = 0;
      _set(false);
      return false;
    }
    if (n is! ScrollUpdateNotification || !_userScrolling) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (_run.sign != delta.sign) _run = 0;
    _run += delta;
    if (_run >= CollapsingFabScope.threshold) _set(true);
    if (_run <= -CollapsingFabScope.threshold) _set(false);
    return false;
  }

  void _set(bool collapsed) {
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _CollapsingFabInherited(
        collapsed: _collapsed,
        child: widget.child,
      ),
    );
  }
}

class _CollapsingFabInherited extends InheritedWidget {
  const _CollapsingFabInherited({
    required this.collapsed,
    required super.child,
  });

  final bool collapsed;

  @override
  bool updateShouldNotify(_CollapsingFabInherited old) =>
      old.collapsed != collapsed;
}

/// The extended FAB of a list screen (design-analysis §4.9): gold, 56 dp
/// tall, 16 dp corners, the [icon] and a verb [label] ("İşlem", "Yaz").
///
/// * Inside a [CollapsingFabScope] it narrows to a 56 × 56 icon while the
///   list scrolls down: the label folds away in [Motion.quick] (200 ms)
///   and fades a little faster. Its label stays its screen-reader name.
/// * [hidden]: fades out in 150 ms and ignores taps — for when an empty
///   state or a setup card on screen carries the same action (D23).
/// * Reduced motion: no size or fade animation.
///
/// It has no hero tag. Give the list under it [clearance] at the bottom so
/// the last row's amount is never covered.
class CollapsingFab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool hidden;

  const CollapsingFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.hidden = false,
  });

  /// The bottom padding a list needs under the FAB: 56 + 16 + 16 and the
  /// system inset, at least 88 dp.
  static double clearance(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final needed = 56 + Gap.lg + Gap.lg + inset;
    return needed < 88 ? 88 : needed;
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = CollapsingFabScope.collapsedOf(context);
    final reduced = Motion.reduced(context);
    final fab = TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0 : 1),
      duration: reduced ? Duration.zero : Motion.quick,
      curve: Motion.enter,
      // The label is the FAB's name for a screen reader at any width, even
      // folded away.
      builder: (context, open, _) => MergeSemantics(
        child: Semantics(
          label: label,
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: onPressed,
            // 16 dp collapsed (16 + 24 + 16 = 56), 20 dp open.
            extendedPadding: EdgeInsets.symmetric(horizontal: 16 + 4 * open),
            extendedIconLabelSpacing: 0,
            icon: Icon(icon, size: 24),
            label: ClipRect(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: open,
                child: Opacity(
                  // The label fades over the first 150 ms of the 200 ms fold.
                  opacity: ((open - 0.25) / 0.75).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: Gap.sm),
                    child: ExcludeSemantics(child: Text(label)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // A tab's scaffold sits inside the shell's, which draws the snackbars
    // and cannot see this FAB: it says where it is, so they float over it.
    // A page's own outermost scaffold lifts them by itself.
    final scaffold = Scaffold.maybeOf(context);
    final nested =
        scaffold?.context.findAncestorStateOfType<ScaffoldState>() != null;
    return SnackClearance(
      lift: SnackClearance.overFab,
      active: nested && !hidden,
      child: _hideable(fab, reduced),
    );
  }

  Widget _hideable(Widget fab, bool reduced) {
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: reduced ? Duration.zero : Motion.pressOut,
          child: fab,
        ),
      ),
    );
  }
}
