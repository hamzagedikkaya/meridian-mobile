import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';

/// One swipe of a [SwipeAction]: what it looks like and what it does.
@immutable
class SwipeSpec {
  /// The background at rest, and once past the threshold.
  final Color container;
  final Color fill;

  /// The icon and label colour over [fill] (an `on*` token).
  final Color onFill;
  final IconData icon;

  /// A verb: "Tamamla", "Yarın", "Sil". Also the TalkBack action's name.
  final String label;

  /// Does the action. True: the row leaves the list (the caller has removed
  /// its record by then — optimistically); false: the row slides back.
  final Future<bool> Function() onSwipe;

  /// Runs once a row [onSwipe] let go has folded away — where a caller
  /// that wants the fold seen removes the record instead (a transaction's
  /// delete with "Geri al"). A screen reader's action runs it right after
  /// [onSwipe].
  final VoidCallback? onDismissed;

  const SwipeSpec({
    required this.container,
    required this.fill,
    required this.onFill,
    required this.icon,
    required this.label,
    required this.onSwipe,
    this.onDismissed,
  });

  /// The background at [t] of the way to the threshold (0–1): the
  /// [container] tone warming to the [fill].
  Color backgroundAt(double t) => Color.lerp(container, fill, t)!;

  /// The icon and label colour over [background]: the [fill] while it reads
  /// at 4.5:1 (over the pale container), else whichever of [onFill] and the
  /// theme's [ink] stands out more. Halfway the background is a mid tone
  /// that neither the fill nor its on-colour reads on; [onFill] and [ink]
  /// sit at the two ends of the scale, so one of them always does.
  Color markOn(Color background, {required Color ink}) {
    if (contrastRatio(fill, background) >= 4.5) return fill;
    return contrastRatio(onFill, background) >= contrastRatio(ink, background)
        ? onFill
        : ink;
  }

  /// The WCAG contrast ratio of [a] and [b] (1–21).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  /// "Tamamla" — incomeContainer → income, `check_rounded`.
  factory SwipeSpec.complete(
    NokturnColors c, {
    required String label,
    required Future<bool> Function() onSwipe,
  }) =>
      SwipeSpec(
        container: c.incomeContainer,
        fill: c.income,
        onFill: c.onIncome,
        icon: Icons.check_rounded,
        label: label,
        onSwipe: onSwipe,
      );

  /// "Yarın" — warningContainer → warning, `event_rounded`.
  factory SwipeSpec.postpone(
    NokturnColors c, {
    required String label,
    required Future<bool> Function() onSwipe,
  }) =>
      SwipeSpec(
        container: c.warningContainer,
        fill: c.warning,
        onFill: c.onWarning,
        icon: Icons.event_rounded,
        label: label,
        onSwipe: onSwipe,
      );

  /// "Sil" — errorContainer → error, `delete_outline_rounded`. Pair it with
  /// `deleteWithUndo`.
  factory SwipeSpec.delete(
    NokturnColors c, {
    required String label,
    required Future<bool> Function() onSwipe,
    VoidCallback? onDismissed,
  }) =>
      SwipeSpec(
        container: c.errorContainer,
        fill: c.error,
        onFill: c.onError,
        icon: Icons.delete_outline_rounded,
        label: label,
        onSwipe: onSwipe,
        onDismissed: onDismissed,
      );
}

/// A list row with swipe actions (design-analysis §4.28) — tasks (→
/// Tamamla, ← Yarın) and transactions (← Sil); no other list swipes.
///
/// Built on [Dismissible]: 40 % of the width commits, the row moves in
/// 200 ms and folds away in 250 ms. Behind it the background warms from
/// the [SwipeSpec.container] tone to its [SwipeSpec.fill] as the threshold
/// nears, the icon and label fading and growing in (opacity 0.8 → 1,
/// scale 0.85 → 1). Their colour is picked anew each frame
/// ([SwipeSpec.markOn]), so the label reads at 3:1 or better all along.
/// Crossing the threshold either way under the finger plays one selection
/// tick; the slide back after letting go plays none.
///
/// Every swipe is also a TalkBack custom action with the same name, on the
/// row's own node (the row is merged into one stop) — give the row a
/// long-press menu with the same actions too (§2.2 rule 8); edge swipes
/// belong to the system back gesture and are never relied on.
class SwipeAction extends StatefulWidget {
  final Widget child;

  /// → (a left-to-right swipe in a left-to-right language).
  final SwipeSpec? startToEnd;

  /// ←.
  final SwipeSpec? endToStart;

  const SwipeAction({
    required Key super.key,
    required this.child,
    this.startToEnd,
    this.endToStart,
  });

  /// The share of the width that commits a swipe.
  static const threshold = 0.4;

  /// The icon and label's opacity at [t] of the way to the threshold: a
  /// fade from 0.8, light enough that the label still reads at 3:1.
  static double markOpacity(double t) => 0.8 + 0.2 * t;

  @override
  State<SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<SwipeAction> {
  final _progress = ValueNotifier<double>(0);

  /// Fingers on the row: the threshold ticks only under one, not while the
  /// row slides back on its own.
  int _pointers = 0;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  SwipeSpec? _specFor(DismissDirection direction) => switch (direction) {
        DismissDirection.startToEnd => widget.startToEnd,
        DismissDirection.endToStart => widget.endToStart,
        _ => null,
      };

  void _onUpdate(DismissUpdateDetails d) {
    if (_pointers > 0 && d.reached != d.previousReached) Haptics.tick();
    _progress.value = d.progress;
  }

  /// A screen reader's action: the swipe without the gesture.
  Future<void> _act(SwipeSpec spec) async {
    if (await spec.onSwipe()) spec.onDismissed?.call();
  }

  void _pointerUp(PointerEvent _) {
    if (_pointers > 0) _pointers--;
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startToEnd;
    final end = widget.endToStart;
    if (start == null && end == null) return widget.child;
    final direction = start != null && end != null
        ? DismissDirection.horizontal
        : start != null
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart;

    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: Dismissible(
        key: ValueKey(widget.key),
        direction: direction,
        dismissThresholds: const {
          DismissDirection.startToEnd: SwipeAction.threshold,
          DismissDirection.endToStart: SwipeAction.threshold,
        },
        movementDuration: Motion.quick,
        resizeDuration: Motion.collapse,
        onUpdate: _onUpdate,
        confirmDismiss: (direction) async =>
            await _specFor(direction)?.onSwipe() ?? false,
        onDismissed: (direction) => _specFor(direction)?.onDismissed?.call(),
        background: start == null
            ? const SizedBox.shrink()
            : _Background(
                spec: start,
                progress: _progress,
                alignment: AlignmentDirectional.centerStart,
              ),
        secondaryBackground: end == null
            ? null
            : _Background(
                spec: end,
                progress: _progress,
                alignment: AlignmentDirectional.centerEnd,
              ),
        // The actions join the row's own node — the one TalkBack focuses —
        // whether or not the row merges its semantics itself.
        child: MergeSemantics(
          child: Semantics(
            customSemanticsActions: {
              if (start != null)
                CustomSemanticsAction(label: start.label): () => _act(start),
              if (end != null)
                CustomSemanticsAction(label: end.label): () => _act(end),
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({
    required this.spec,
    required this.progress,
    required this.alignment,
  });

  final SwipeSpec spec;
  final ValueListenable<double> progress;
  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ink = context.nok.inkHi;
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, p, _) {
        final t = (p / SwipeAction.threshold).clamp(0.0, 1.0);
        final background = spec.backgroundAt(t);
        // Over the pale container the mark takes the fill's own colour,
        // over the fill its on-colour, the theme's ink in between: the one
        // that reads best on this frame's background.
        final fg = spec.markOn(background, ink: ink);
        return ColoredBox(
          color: background,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.rowH),
            child: Align(
              alignment: alignment,
              child: Opacity(
                opacity: SwipeAction.markOpacity(t),
                child: Transform.scale(
                  scale: 0.85 + 0.15 * t,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(spec.icon, size: 20, color: fg),
                      const SizedBox(width: Gap.sm),
                      Text(
                        spec.label,
                        style: text.labelLarge!.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
