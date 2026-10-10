import 'package:flutter/material.dart';

import '../../../../core/haptics.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_metrics.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_typography.dart';
import '../../../../theme/entity_color.dart';

/// The counter of a habit done several times a day — `target_count` above
/// one (design-analysis §4.22).
///
/// A 40 dp pill about 112 dp wide, inside a 120 × 48 dp target:
///
/// * **−** on the left answers its own 48 × 48 dp touch.
/// * **The body** — the count "5/8" and a `+` that is only a hint — counts
///   one more: the bigger, likelier tap.
/// * **Not done**: surface2 with a 1 dp inkDisabled edge, the count inkHi.
///   **Done**: the habit's tint, a 1.5 dp edge in its colour, the count in
///   its text tone after a check — never text on the solid colour (D19).
///   The colours change in [Motion.quick].
/// * **At the target** the body and its `+` are off (inkDisabled): the
///   server clamps the count there anyway (D12).
/// * The count rolls up on +1 and down on −1 ([Motion.quick]); the step
///   that reaches the target swells the pill to 1.04 and back in 220 ms
///   with [Haptics.check], every other step plays [Haptics.tick].
///
/// [onDelta] gets the step and the pill's global centre — where the day's
/// celebration starts when this step finished it.
///
/// A screen reader hears one adjustable control: "Su, 5 / 8", increase and
/// decrease.
class CounterPill extends StatefulWidget {
  final int count;
  final int target;
  final EntityTone tone;
  final void Function(int delta, Offset origin) onDelta;

  /// The habit's name, read before the count.
  final String? semanticLabel;

  const CounterPill({
    super.key,
    required this.count,
    required this.target,
    required this.tone,
    required this.onDelta,
    this.semanticLabel,
  });

  /// The pill as drawn.
  static const pillHeight = 40.0;
  static const pillWidth = 112.0;

  /// The − target, and the height of every target.
  static const minusWidth = Hit.min;
  static const bodyWidth = 72.0;

  /// The peak of the swell when the target is reached.
  static const swell = 1.04;

  /// 220 ms (§4.22) — the strike's beat; no literal here (WP-17 note: a
  /// `Motion.swell` token would name it).
  static const swellDuration = Motion.strike;

  @override
  State<CounterPill> createState() => _CounterPillState();
}

class _CounterPillState extends State<CounterPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swell = AnimationController(
    vsync: this,
    duration: CounterPill.swellDuration,
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: CounterPill.swell,
      ).chain(CurveTween(curve: Motion.enter)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: CounterPill.swell,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 50,
    ),
  ]).animate(_swell);

  /// Which way the count last moved: the new number comes in from below on
  /// a step up, from above on a step down.
  int _direction = 1;

  @override
  void didUpdateWidget(CounterPill old) {
    super.didUpdateWidget(old);
    if (widget.count != old.count) {
      _direction = widget.count > old.count ? 1 : -1;
    }
  }

  @override
  void dispose() {
    _swell.dispose();
    super.dispose();
  }

  Offset _origin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _step(int delta) {
    final next = widget.count + delta;
    if (next < 0 || next > widget.target) return;
    if (delta > 0 && next >= widget.target) {
      Haptics.check();
      if (!Motion.reduced(context)) _swell.forward(from: 0);
    } else {
      Haptics.tick();
    }
    widget.onDelta(delta, _origin());
  }

  String _value(int n) => '$n/${widget.target}';

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final tone = widget.tone;
    final count = widget.count;
    final target = widget.target;
    final complete = count >= target;
    final canAdd = count < target;
    final canRemove = count > 0;
    final duration = Motion.orInstant(context, Motion.quick);
    final style = context.nokText.numMeta.copyWith(fontWeight: FontWeight.w600);

    final number = ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(count);
          final from = Offset(0, 0.6 * _direction);
          final position = incoming
              ? Tween(begin: from, end: Offset.zero).animate(animation)
              : Tween(begin: -from, end: Offset.zero).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: position, child: child),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        child: TweenAnimationBuilder<Color?>(
          key: ValueKey(count),
          tween: ColorTween(end: complete ? tone.text : c.inkHi),
          duration: duration,
          builder: (context, color, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (complete) ...[
                Icon(Icons.check_rounded, size: 14, color: color),
                const SizedBox(width: 2),
              ],
              Text(
                _value(count),
                maxLines: 1,
                style: style.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );

    final minus = SizedBox(
      width: CounterPill.minusWidth,
      height: Hit.min,
      child: InkResponse(
        onTap: canRemove ? () => _step(-1) : null,
        radius: 22,
        splashColor: c.gold.withValues(alpha: 0.08),
        highlightColor: c.gold.withValues(alpha: 0.04),
        excludeFromSemantics: true,
        child: Icon(
          Icons.remove_rounded,
          size: 20,
          color: canRemove ? (complete ? tone.text : c.inkHi) : c.inkDisabled,
        ),
      ),
    );

    final body = SizedBox(
      width: CounterPill.bodyWidth,
      height: Hit.min,
      child: InkWell(
        onTap: canAdd ? () => _step(1) : null,
        customBorder: const StadiumBorder(),
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(right: Gap.md),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(fit: BoxFit.scaleDown, child: number),
              ),
              const SizedBox(width: Gap.xxs),
              Icon(
                Icons.add_rounded,
                size: 20,
                color: canAdd ? c.inkHi : c.inkDisabled,
              ),
            ],
          ),
        ),
      ),
    );

    const inset = (Hit.min - CounterPill.pillHeight) / 2;
    const side =
        (CounterPill.minusWidth +
            CounterPill.bodyWidth -
            CounterPill.pillWidth) /
        2;
    final pill = Stack(
      children: [
        Positioned(
          left: side,
          right: side,
          top: inset,
          bottom: inset,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: complete ? 1 : 0),
            duration: duration,
            builder: (context, t, _) => DecoratedBox(
              key: const ValueKey('counter-pill-shape'),
              decoration: ShapeDecoration(
                color: Color.lerp(c.surface2, tone.tint, t),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: Color.lerp(c.inkDisabled, tone.fill, t)!,
                    width: 1 + 0.5 * t,
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [minus, body]),
      ],
    );

    return Semantics(
      label: widget.semanticLabel,
      value: _value(count),
      increasedValue: canAdd ? _value(count + 1) : null,
      decreasedValue: canRemove ? _value(count - 1) : null,
      onIncrease: canAdd ? () => _step(1) : null,
      onDecrease: canRemove ? () => _step(-1) : null,
      liveRegion: true,
      excludeSemantics: true,
      child: ScaleTransition(scale: _scale, child: pill),
    );
  }
}
