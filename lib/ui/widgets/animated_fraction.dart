import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

import '../../theme/app_motion.dart';

/// The moving value behind every progress ring and bar (design-analysis
/// §4.21), kept in an unbounded controller so a new target picks up the
/// current speed instead of restarting.
///
/// * **Mount:** the value is the target at once. Only when [sweep] is asked
///   (the [EntranceGate] was open and motion is not reduced) does it sweep
///   0 → target, by default in [Motion.sweep] with [Motion.enter].
///   Scrolling back, a skeleton or a Hero shuttle never re-sweep.
/// * **Retarget:** a [SpringSimulation] from the current value and velocity
///   ([spring], default [Motion.defaultEffects] — critically damped, so it
///   does not overshoot). Under reduced motion the target is set directly.
/// * **Painting** reads [value], always clamped to [0, 1]; pass [controller]
///   as the painter's `repaint` so a frame repaints without rebuilding.
class AnimatedFraction {
  AnimatedFraction({
    required TickerProvider vsync,
    required double target,
    bool sweep = false,
    Duration sweepDuration = Motion.sweep,
    Curve sweepCurve = Motion.enter,
    this.spring,
  }) : _target = target.clamp(0.0, 1.0),
       controller = AnimationController.unbounded(
         vsync: vsync,
         animationBehavior: AnimationBehavior.normal,
         value: sweep ? 0 : target.clamp(0.0, 1.0),
       ) {
    if (sweep && _target > 0) {
      controller.animateTo(_target, duration: sweepDuration, curve: sweepCurve);
    }
  }

  /// The spring a retarget rides; null is [Motion.defaultEffects].
  SpringDescription? spring;

  /// Drives the painting; listen to it, never rebuild on it.
  final AnimationController controller;

  double _target;

  /// Where the value is heading.
  double get target => _target;

  /// The value to paint, within [0, 1].
  double get value => controller.value.clamp(0.0, 1.0);

  /// The current speed, in fraction per second.
  double get velocity => controller.velocity;

  /// Moves to [target] (clamped to [0, 1]): a spring that keeps the current
  /// velocity, or — when [reduced] — the end value in this frame. [curve]
  /// with [duration] replaces the spring (a habit ring's segment fill).
  void retarget(
    double target, {
    required bool reduced,
    Duration? duration,
    Curve curve = Motion.enter,
  }) {
    final next = target.clamp(0.0, 1.0);
    if (next == _target && !controller.isAnimating) return;
    _target = next;
    if (reduced) {
      controller.value = next;
      return;
    }
    if (duration != null) {
      controller.animateTo(next, duration: duration, curve: curve);
      return;
    }
    controller.animateWith(
      SpringSimulation(
        spring ?? Motion.defaultEffects,
        controller.value,
        next,
        controller.velocity,
      ),
    );
  }

  /// Jumps to [target] without motion.
  void jump(double target) {
    _target = target.clamp(0.0, 1.0);
    controller.value = _target;
  }

  void dispose() => controller.dispose();
}
