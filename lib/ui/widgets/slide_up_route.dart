import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// The route of every full-screen create/edit form (design-analysis §4.31,
/// §5.2): opaque, a full-screen dialog, sliding up from the bottom.
///
/// * **Normal**: 400 ms in on `emphasizedDecelerate`, 300 ms out on
///   `easeInCubic`.
/// * **Predictive back** (the system back gesture): the form follows the
///   finger linearly, its top corners rounding up to 28 dp as it goes.
/// * **Reduced motion**: no slide — the form is simply there.
///
/// Leaving a dirty form is guarded by `FormScaffold`'s `PopScope`.
class SlideUpPageRoute<T> extends PageRoute<T> {
  SlideUpPageRoute({required this.builder, super.settings})
      : super(fullscreenDialog: true);

  final WidgetBuilder builder;

  /// Set while a back gesture drives the route, until it settles.
  bool _gestureDriven = false;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Motion.formIn;

  @override
  Duration get reverseTransitionDuration => Motion.formOut;

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_settle);
  }

  void _settle(AnimationStatus status) {
    if (status.isCompleted || status.isDismissed) _gestureDriven = false;
  }

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    _gestureDriven = true;
    super.handleStartBackGesture(progress: progress);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: builder(context),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    if (_gestureDriven) {
      // Linear: the form is exactly where the finger puts it.
      return SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 1), end: Offset.zero),
        ),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = (4 * (1 - animation.value)).clamp(0.0, 1.0);
            return ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28 * t),
              ),
              child: child,
            );
          },
          child: child,
        ),
      );
    }
    return SlideTransition(
      position: CurvedAnimation(
        parent: animation,
        curve: Motion.surfaceIn,
        reverseCurve: Motion.exit,
      ).drive(Tween(begin: const Offset(0, 1), end: Offset.zero)),
      child: child,
    );
  }
}

/// A form route: [SlideUpPageRoute] around [builder] — the call every form
/// opener uses (`Navigator.push(context, slideUpModalRoute(…))`).
Route<T> slideUpModalRoute<T>(WidgetBuilder builder) =>
    SlideUpPageRoute<T>(builder: builder);
