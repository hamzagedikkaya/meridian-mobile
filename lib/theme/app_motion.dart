/// The one source of motion (design-analysis §5.1): durations, curves and
/// springs. No `Duration(milliseconds: …)` literal belongs anywhere else in
/// `lib/` — `test/theme/motion_tokens_test.dart` lists the ones still left
/// (report mode until WP-17 makes it fail).
///
/// Rules:
///
/// 1. **Springs** only when motion starts from a finger or the target moves
///    mid-flight (fling release, quick ± taps, progress after typing, scrub
///    release, segment drag). Everything else uses a curve. Drive a spring
///    with `AnimationController.unbounded(vsync: …, animationBehavior:
///    AnimationBehavior.normal)` and `SpringSimulation(spring, value, target,
///    velocity)`; the default `preserve` behaviour is not shortened under
///    reduced motion.
/// 2. **One overshoot**: only the check pop (0.9 → 1.05 → 1.0). Never
///    `easeOutBack` or `elasticOut`.
/// 3. **Ceilings**: nothing the user waits on runs past 600 ms; a full
///    stagger is at most 6 × 50 + 300 = 550 ms; exits are ~25 % shorter
///    than entrances.
/// 4. **Reduced motion** ([Motion.reduced]) shows the end state in one
///    frame. Delays ([skeletonDelay], [syncHintDelay], [spinnerDelay]) are
///    timers, not animation, and stay the same.
/// 5. Timings are tuned on the phone in a profile build, never in a desktop
///    preview.
library;

import 'package:flutter/material.dart';

abstract final class Motion {
  // --- Durations -------------------------------------------------------------

  /// Press feedback: the scale goes down in [pressIn], back in [pressOut].
  static const pressIn = Duration(milliseconds: 80);
  static const pressOut = Duration(milliseconds: 150);

  /// Colour, chip, counter, cross-fade, filter.
  static const quick = Duration(milliseconds: 200);

  /// An incoming rolling digit (the outgoing one takes [rollOut]).
  static const roll = Duration(milliseconds: 250);
  static const rollOut = Duration(milliseconds: 180);

  /// Tab fade-through, entrance item, row insert, shared-axis step.
  static const standard = Duration(milliseconds: 300);

  /// Row exit, the linger collapse, sheet content resize.
  static const collapse = Duration(milliseconds: 250);

  /// Bottom sheets (§4.15) and full-screen forms (§4.31).
  static const sheetIn = Duration(milliseconds: 350);
  static const sheetOut = Duration(milliseconds: 250);
  static const formIn = Duration(milliseconds: 400);
  static const formOut = Duration(milliseconds: 300);

  /// Hero count-up and the first ring/bar sweep.
  static const countUp = Duration(milliseconds: 500);
  static const sweep = Duration(milliseconds: 600);

  /// Entrance stagger: [staggerStep] apart, only the first [staggerCap]
  /// items play; each rises [entranceRise] dp.
  static const staggerStep = Duration(milliseconds: 50);
  static const staggerCap = 6;
  static const entranceRise = 12.0;

  /// First load: the skeleton appears after [skeletonDelay], stays at least
  /// [skeletonMinVisible] once shown, and cross-fades out in
  /// [skeletonCrossFade].
  static const skeletonDelay = Duration(milliseconds: 400);
  static const skeletonMinVisible = Duration(milliseconds: 400);
  static const skeletonCrossFade = Duration(milliseconds: 250);

  /// The background-sync line shows only after [syncHintDelay]; a button
  /// spinner only after [spinnerDelay].
  static const syncHintDelay = Duration(seconds: 1);
  static const spinnerDelay = Duration(milliseconds: 150);

  /// The "what changed" wash, and how long a checked-off row lingers.
  static const highlight = Duration(milliseconds: 1200);
  static const linger = Duration(seconds: 4);

  /// Pull-to-refresh stays at least this long, so it never flashes.
  static const refreshMinimum = Duration(milliseconds: 500);

  /// Tier-2 confetti and the tier-3 milestone card (in / hold / out).
  static const confetti = Duration(milliseconds: 800);
  static const milestoneIn = Duration(milliseconds: 350);
  static const milestoneHold = Duration(milliseconds: 2500);
  static const milestoneOut = Duration(milliseconds: 250);

  /// The light ↔ dark theme change (`MaterialApp.themeAnimationDuration`).
  static const themeChange = Duration(milliseconds: 250);

  // --- Component timings (§4, §5.4–5.5) ---------------------------------------

  /// Check pop: up to 1.05 in [popUp], settle to 1.0 in [popSettle].
  static const popUp = Duration(milliseconds: 170);
  static const popSettle = Duration(milliseconds: 130);

  /// A done task's strike-through, drawn after the fill.
  static const strike = Duration(milliseconds: 220);

  /// A rejected keypad digit: two ±4 dp shakes.
  static const shake = Duration(milliseconds: 240);

  /// Journal mood filter: old entries fade out, new ones fade in.
  static const filterOut = Duration(milliseconds: 90);
  static const filterIn = Duration(milliseconds: 160);

  /// How long a long-press or hover waits before a tooltip shows.
  static const tooltipWait = Duration(milliseconds: 500);

  /// Press scale of cards (0.98) and of chips and small controls (0.95).
  static const pressScale = 0.98;
  static const pressScaleSmall = 0.95;

  // --- Curves ----------------------------------------------------------------

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// Cubic(0.05, 0.7, 0.1, 1.0): sheets, forms and the milestone card only.
  static const Curve surfaceIn = Easing.emphasizedDecelerate;

  /// The theme change curve.
  static const Curve themeCurve = Curves.easeInOutCubic;

  // --- Springs (mass 1; ratio 1.0 never overshoots) -----------------------------

  /// ≈ 140 ms. Spatial: positions and sizes.
  static final fastSpatial =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1400, ratio: 0.9);

  /// ≈ 195 ms.
  static final defaultSpatial =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 700, ratio: 0.9);

  /// Effects: colour, opacity, ring and bar fill.
  static final fastEffects =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 3800, ratio: 1.0);

  /// ≈ 165 ms.
  static final defaultEffects =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1600, ratio: 1.0);

  /// ≈ 235 ms.
  static final slowEffects =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 800, ratio: 1.0);

  // --- Reduced motion --------------------------------------------------------

  /// True when the system's "Remove animations" or the app's own "Reduce
  /// motion" switch is on — `MeridianApp` folds both into
  /// `MediaQuery.disableAnimations`, so this is the only check needed.
  static bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);

  /// [d], or [Duration.zero] under reduced motion — for implicit animations
  /// (`AnimatedContainer(duration: Motion.orInstant(context, Motion.quick))`).
  static Duration orInstant(BuildContext c, Duration d) =>
      reduced(c) ? Duration.zero : d;

  // --- Animation styles ------------------------------------------------------

  /// Bottom sheets: 350 ms emphasized-decelerate in, 250 ms ease-in out.
  static const sheetStyle = AnimationStyle(
    duration: sheetIn,
    reverseDuration: sheetOut,
    curve: surfaceIn,
    reverseCurve: exit,
  );

  /// [sheetStyle], or none under reduced motion — pass it as
  /// `showModalBottomSheet(sheetAnimationStyle: Motion.sheet(context))`.
  static AnimationStyle sheet(BuildContext c) =>
      reduced(c) ? AnimationStyle.noAnimation : sheetStyle;

  /// Full-screen create/edit forms: 400 ms in, 300 ms out.
  static const formStyle = AnimationStyle(
    duration: formIn,
    reverseDuration: formOut,
    curve: surfaceIn,
    reverseCurve: exit,
  );

  /// [formStyle], or none under reduced motion.
  static AnimationStyle form(BuildContext c) =>
      reduced(c) ? AnimationStyle.noAnimation : formStyle;
}
