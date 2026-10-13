import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';

/// Skeleton wrapper (design-analysis §4.26): bones in `skeletonBone`
/// pulsing to 55 % over 1200 ms, no shimmer sweep; a still bone under
/// reduced motion. Wrap the real layout with fake data. When it shows and
/// for how long is `LoadPhaseSwitcher`'s call, not this widget's.
class NokSkeleton extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const NokSkeleton({super.key, required this.enabled, required this.child});

  /// One pulse, bone → bone at 55 % and back.
  static const pulse = Motion.pulse;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Skeletonizer(
      enabled: enabled,
      effect: Motion.reduced(context)
          ? SolidColorEffect(color: c.skeletonBone)
          : PulseEffect(
              from: c.skeletonBone,
              to: c.skeletonBone.withValues(alpha: 0.55),
              duration: pulse,
            ),
      child: child,
    );
  }
}

/// The shape of a [Bone].
enum BoneShape {
  /// A line of text: radius 4.
  text,

  /// A circle (avatars, rings).
  circle,

  /// A block: radius 12.
  block,

  /// A card: radius 16.
  card,
}

/// One hand-drawn skeleton bone, for layouts that are not a fake-data copy
/// of the real one (the journal's '████' strings become these).
///
/// A text bone is its line height minus 6 dp: pass [lineHeight] (body 20 →
/// 14, title 22 → 16, hero 40 → 34). It pulses like [NokSkeleton] and
/// stands still under reduced motion. Screen readers skip it.
class Bone extends StatefulWidget {
  const Bone({
    super.key,
    this.width,
    this.height,
    this.shape = BoneShape.text,
    this.lineHeight = 20,
  });

  /// A text line [lineHeight] tall (the bone is 6 dp less), [width] wide.
  const Bone.text({super.key, this.width, this.lineHeight = 20})
      : height = null,
        shape = BoneShape.text;

  /// A circle [size] across.
  const Bone.circle({super.key, required double size})
      : width = size,
        height = size,
        shape = BoneShape.circle,
        lineHeight = 0;

  final double? width;
  final double? height;
  final BoneShape shape;
  final double lineHeight;

  @override
  State<Bone> createState() => _BoneState();
}

class _BoneState extends State<Bone> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: NokSkeleton.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bone = context.nok.skeletonBone;
    final radius = switch (widget.shape) {
      BoneShape.text => BorderRadius.circular(Radii.xs),
      BoneShape.circle => BorderRadius.circular(9999),
      BoneShape.block => BorderRadius.circular(Radii.md),
      BoneShape.card => BorderRadius.circular(Radii.lg),
    };
    final height = widget.height ??
        (widget.shape == BoneShape.text ? widget.lineHeight - 6 : null);
    return ExcludeSemantics(
      child: FadeTransition(
        // bone → bone at 55 %: the opacity of the whole bone, 1 → 0.55.
        opacity: Tween<double>(begin: 1, end: 0.55).animate(_pulse),
        child: SizedBox(
          width: widget.width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(color: bone, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}
