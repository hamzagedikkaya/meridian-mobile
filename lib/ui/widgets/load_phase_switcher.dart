import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import 'entrance.dart';

/// What a screen has for its body: nothing yet, its content, or a failure.
/// Map a read model with `AsyncScreenState`: `isFirstLoad` → [waiting],
/// a value → [content], `hasFailed` → [error].
enum LoadPhase { waiting, content, error }

/// The first-load choreography of a screen body (design-analysis §4.26,
/// §5.6) — so a skeleton never flashes and known content never blanks:
///
/// 1. With nothing to show, the first [Motion.skeletonDelay] (400 ms) shows
///    only the frame — app bar and background ([frame], empty by default).
///    The delay is a real timer; reduced motion does not shorten it.
/// 2. Content that lands within it is drawn at once, and the [EntranceGate]
///    opens for that frame: the entrance stagger plays.
/// 3. Otherwise the skeleton shows, and stays at least
///    [Motion.skeletonMinVisible] (400 ms); then it cross-fades to the
///    content in [Motion.skeletonCrossFade] (ease-out in, ease-in out). The
///    gate does **not** open: the cross-fade is the entrance.
/// 4. Once the content has shown, it is never swapped back for a skeleton or
///    a blank: a later [LoadPhase.waiting] keeps it.
///
/// Without an [EntranceScope] above it, it provides one of its own.
class LoadPhaseSwitcher extends StatefulWidget {
  const LoadPhaseSwitcher({
    super.key,
    required this.phase,
    required this.skeleton,
    required this.content,
    required this.error,
    this.frame,
  });

  final LoadPhase phase;
  final WidgetBuilder skeleton;
  final WidgetBuilder content;
  final WidgetBuilder error;

  /// What shows during the first 400 ms; null is nothing.
  final WidgetBuilder? frame;

  @override
  State<LoadPhaseSwitcher> createState() => _LoadPhaseSwitcherState();
}

enum _Shown { frame, skeleton, content, error }

class _LoadPhaseSwitcherState extends State<LoadPhaseSwitcher> {
  EntranceGate? _ownGate;
  late _Shown _shown;
  Timer? _delay;
  Timer? _minimum;
  bool _skeletonDone = false;

  /// Whether the last switch was out of the skeleton (cross-fades) rather
  /// than out of the blank frame (cuts, and the entrance plays).
  bool _fromSkeleton = false;

  @override
  void initState() {
    super.initState();
    _shown = switch (widget.phase) {
      LoadPhase.content => _Shown.content,
      LoadPhase.error => _Shown.error,
      LoadPhase.waiting => _Shown.frame,
    };
    if (_shown == _Shown.frame) {
      _delay = Timer(Motion.skeletonDelay, _showSkeleton);
    }
  }

  void _showSkeleton() {
    _delay = null;
    if (!mounted || _shown != _Shown.frame) return;
    setState(() => _shown = _Shown.skeleton);
    _minimum = Timer(Motion.skeletonMinVisible, () {
      _minimum = null;
      _skeletonDone = true;
      if (mounted) _follow();
    });
  }

  @override
  void didUpdateWidget(LoadPhaseSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) _follow(rebuild: false);
  }

  /// Moves [_shown] towards [LoadPhaseSwitcher.phase] as far as the rules
  /// allow now.
  void _follow({bool rebuild = true}) {
    final next = switch (widget.phase) {
      LoadPhase.content => _Shown.content,
      LoadPhase.error => _Shown.error,
      LoadPhase.waiting => null,
    };
    if (next == null || next == _shown) return;
    switch (_shown) {
      case _Shown.frame:
        _delay?.cancel();
        _delay = null;
        _fromSkeleton = false;
      case _Shown.skeleton:
        if (!_skeletonDone) return; // the minimum timer calls back
        _fromSkeleton = true;
        // The cross-fade is the entrance: the gate stays shut.
        _gate?.spend();
      case _Shown.content:
      case _Shown.error:
        _fromSkeleton = false;
    }
    if (rebuild) {
      setState(() => _shown = next);
    } else {
      _shown = next;
    }
  }

  EntranceGate? get _gate =>
      EntranceGate.maybeOf(context) ?? (_ownGate ??= EntranceGate());

  @override
  void dispose() {
    _delay?.cancel();
    _minimum?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = EntranceGate.maybeOf(context);
    final gate = outer ?? (_ownGate ??= EntranceGate());
    if (_shown == _Shown.content && !_fromSkeleton) {
      gate.openForFirstFrame(context);
    }
    final Widget child = switch (_shown) {
      _Shown.frame => KeyedSubtree(
        key: const ValueKey(_Shown.frame),
        child: widget.frame?.call(context) ?? const SizedBox.expand(),
      ),
      _Shown.skeleton => KeyedSubtree(
        key: const ValueKey(_Shown.skeleton),
        child: widget.skeleton(context),
      ),
      _Shown.content => KeyedSubtree(
        key: const ValueKey(_Shown.content),
        child: widget.content(context),
      ),
      _Shown.error => KeyedSubtree(
        key: const ValueKey(_Shown.error),
        child: widget.error(context),
      ),
    };
    final switcher = AnimatedSwitcher(
      duration: _fromSkeleton
          ? Motion.orInstant(context, Motion.skeletonCrossFade)
          : Duration.zero,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
    if (outer != null) return switcher;
    return EntranceScope(gate: gate, child: switcher);
  }
}
