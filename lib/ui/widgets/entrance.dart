import 'package:flutter/material.dart';

/// The §5 first-load entrance — a 300 ms fade with a 6 % upward slide,
/// staggered by [delay] — played once, when the widget first mounts with
/// [play] set. Later values of [play] are ignored.
///
/// It replaces `child.animate()` wrapped in an "only on first load" flag:
/// that version swapped the `Animate` wrapper for the bare child on the next
/// build, and a changed widget type remounts the whole subtree. With data now
/// refreshed in the background (after writes, on resume, at midnight), that
/// next build is a refresh — and the remount replayed every count-up, ring
/// sweep and bar fill and swallowed the first tap's check animation. This
/// widget's type never changes, so a refresh only updates what changed.
class Entrance extends StatefulWidget {
  final bool play;
  final Duration delay;
  final Widget child;

  const Entrance({
    super.key,
    required this.play,
    this.delay = Duration.zero,
    required this.child,
  });

  /// [Entrance] for the [index]-th item of a staggered list: 50 ms apart,
  /// and only the first six play.
  factory Entrance.staggered({
    Key? key,
    required bool play,
    required int index,
    required Widget child,
  }) =>
      Entrance(
        key: key,
        play: play && index < 6,
        delay: Duration(milliseconds: 50 * index.clamp(0, 6)),
        child: child,
      );

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 300);

  // One controller spans delay + fade, so no Timer is needed for the delay.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _duration,
    value: widget.play ? 0 : 1,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + _duration).inMicroseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _controller.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      // The same two wrappers at every value, finished or not: returning the
      // bare child once done would reparent — and remount — it.
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(0, 0.06 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
