import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';

/// Whether first-load motion may play right now (design-analysis §5.3): the
/// entrance stagger, the first ring/bar sweep, the hero count-up and chart
/// intros all ask this one gate, so they play together, once, on the first
/// visible frame of a tab's data — and never again.
///
/// A tab root owns one gate (through [EntranceHost]) and opens it with
/// [openForFirstFrame] when its first data is about to be drawn. The gate
/// stays open for that frame only; anything mounted later — a lazily built
/// section, the 4th–6th card scrolled into view, a card rebuilt after leaving
/// the cache extent, content after a skeleton — starts in its final state.
///
/// It never opens on a refresh, a page, a filter change, a return to the
/// tab, after a skeleton (the cross-fade is the entrance) or under reduced
/// motion (each animation checks that itself).
class EntranceGate {
  bool _open = false;
  bool _spent = false;

  /// True during the one frame the first content is drawn.
  bool get isOpen => _open;

  /// Whether the gate has been opened (or given up) — it never opens again.
  bool get isSpent => _spent;

  /// Opens the gate for the frame being built, if it never opened and the
  /// tab is on screen ([TickerMode] enabled) — data that lands while a tab
  /// is hidden plays nothing, and the gate waits for a visible frame. A
  /// post-frame callback closes it for good. Safe to call on every build.
  void openForFirstFrame(BuildContext context) {
    if (_spent) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    _spent = true;
    _open = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _open = false);
  }

  /// Gives the first-load motion up without playing it (content that came
  /// after a skeleton: the cross-fade was its entrance).
  void spend() {
    _spent = true;
    _open = false;
  }

  /// The gate of the nearest [EntranceScope], read without a dependency —
  /// the question is asked once, when a widget mounts.
  static EntranceGate? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EntranceScope>()?.gate;
}

/// Puts [gate] above a tab root's content.
class EntranceScope extends InheritedWidget {
  const EntranceScope({super.key, required this.gate, required super.child});

  final EntranceGate gate;

  @override
  bool updateShouldNotify(EntranceScope old) => old.gate != gate;
}

/// A tab root's [EntranceGate], kept for the life of its `State`: wrap the
/// root's body in it and open the gate with
/// `EntranceGate.maybeOf(context)?.openForFirstFrame(context)` (or let a
/// `LoadPhaseSwitcher` do it).
class EntranceHost extends StatefulWidget {
  const EntranceHost({super.key, required this.child});

  final Widget child;

  @override
  State<EntranceHost> createState() => _EntranceHostState();
}

class _EntranceHostState extends State<EntranceHost> {
  final _gate = EntranceGate();

  @override
  Widget build(BuildContext context) =>
      EntranceScope(gate: _gate, child: widget.child);
}

/// Whether first-load motion should play for a widget mounting under
/// [context] now: asked [play], the gate (if any) open, motion not reduced.
/// Without an [EntranceScope] above it, [play] alone decides — screens that
/// have not adopted the gate keep their own "first data" flag.
bool entranceShouldPlay(BuildContext context, {bool play = true}) {
  if (!play || Motion.reduced(context)) return false;
  final gate = EntranceGate.maybeOf(context);
  return gate == null || gate.isOpen;
}

/// The first-load entrance (§5.3): a 300 ms fade with a fixed 12 dp rise,
/// staggered by [delay], played once — when the widget first mounts with
/// [play] set while the [EntranceGate] is open. Later values of [play] are
/// ignored, and anything mounted after the gate closed starts finished.
///
/// The wrappers never change type, so a refresh only updates what changed
/// (the old `child.animate()` swap remounted the subtree and replayed every
/// count-up, sweep and check). Leaf transitions only: the child is not
/// rebuilt per tick.
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

  /// [Entrance] for the [index]-th item of a staggered list:
  /// [Motion.staggerStep] apart, and only the first [Motion.staggerCap] play.
  factory Entrance.staggered({
    Key? key,
    required bool play,
    required int index,
    required Widget child,
  }) =>
      Entrance(
        key: key,
        play: play && index < Motion.staggerCap,
        delay: Motion.staggerStep * index.clamp(0, Motion.staggerCap),
        child: child,
      );

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  // One controller spans delay + fade, so no Timer is needed for the delay.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + Motion.standard,
    value: 1,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds /
          (widget.delay + Motion.standard).inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (entranceShouldPlay(context, play: widget.play)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, Motion.entranceRise * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
