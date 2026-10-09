import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';

/// The tabs' navigators, with a fade-through between them (design-analysis
/// §5.2): the old tab fades out in the first 90 ms, the new one fades in
/// over the remaining 210 ms while it grows from 0.92 to 1.0 — 300 ms in
/// all ([Motion.standard]); under reduced motion the switch is instant.
///
/// What `StatefulShellRoute.navigatorContainerBuilder` is given. Like the
/// indexed stack it replaces, every visited tab stays mounted: the selected
/// one shown, the others offstage with their tickers off. Only the selected
/// tab's heroes fly — a route pushed over the shell looks for heroes in
/// every tab still mounted, and a goal ring on a hidden tab would fly out
/// of a screen the user cannot see — and only it takes taps, focus and the
/// screen reader's attention, also while the old tab fades out.
///
/// Each child always gets the same chain of wrappers, so switching tabs
/// never remounts a branch's navigator (and never loses its state).
class FadeThroughBranches extends StatefulWidget {
  const FadeThroughBranches({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  /// The selected branch.
  final int currentIndex;

  /// The branches' navigators, in branch order.
  final List<Widget> children;

  @override
  State<FadeThroughBranches> createState() => _FadeThroughBranchesState();
}

class _FadeThroughBranchesState extends State<FadeThroughBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.standard,
    value: 1,
  )..addStatusListener(_onStatus);

  /// The tab fading out, while it does.
  int? _previous;

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && _previous != null && mounted) {
      setState(() => _previous = null);
    }
  }

  @override
  void didUpdateWidget(FadeThroughBranches old) {
    super.didUpdateWidget(old);
    if (old.currentIndex == widget.currentIndex) return;
    if (Motion.reduced(context)) {
      _controller.value = 1;
      _previous = null;
      return;
    }
    _previous = old.currentIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = context.nok.bg;
    final current = widget.currentIndex;
    final previous = _previous;
    // Painted in this order: the hidden tabs, the one fading out, then the
    // selected one on top — whichever way the switch goes, the new tab
    // fades in over the old one rather than under its opaque fill. The
    // keys let the elements move in the stack without remounting.
    final order = [
      for (var i = 0; i < widget.children.length; i++)
        if (i != current && i != previous) i,
      ?previous,
      current,
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in order)
          KeyedSubtree(
            key: ValueKey(i),
            child: Offstage(
              offstage: i != current && i != previous,
              child: TickerMode(
                enabled: i == current || i == previous,
                child: HeroMode(
                  enabled: i == current,
                  child: IgnorePointer(
                    ignoring: i != current,
                    child: ExcludeFocus(
                      excluding: i != current,
                      child: ExcludeSemantics(
                        excluding: i != current,
                        child: FadeThroughTransition(
                          animation: i == current
                              ? _controller
                              : kAlwaysCompleteAnimation,
                          secondaryAnimation: i == previous
                              ? _controller
                              : kAlwaysDismissedAnimation,
                          fillColor: fill,
                          child: widget.children[i],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
