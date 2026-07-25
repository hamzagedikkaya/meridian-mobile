import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../theme/app_colors.dart';

/// Skeleton wrapper — bones on surface tones, 1200ms pulse, no shimmer sweep
/// (design §4.3). Wrap the real layout with fake data.
class NokSkeleton extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const NokSkeleton({super.key, required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Skeletonizer(
      enabled: enabled,
      switchAnimationConfig: const SwitchAnimationConfig(
        duration: Duration(milliseconds: 300),
      ),
      effect: PulseEffect(
        from: c.skeletonBone,
        to: c.skeletonBone.withValues(alpha: 0.55),
        duration: const Duration(milliseconds: 1200),
      ),
      child: child,
    );
  }
}
