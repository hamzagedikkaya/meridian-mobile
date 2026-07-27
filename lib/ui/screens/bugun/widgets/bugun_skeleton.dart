import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../ui/widgets/nokturn_card.dart';
import '../../../../ui/widgets/skeletons.dart';

/// First-load skeleton mirroring the Bugün layout (design §4.3).
class BugunSkeleton extends StatelessWidget {
  const BugunSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;

    Widget bone(double w, double h, [double r = 6]) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: c.skeletonBone,
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return NokSkeleton(
      enabled: true,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // App bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bone(90, 14),
                      const SizedBox(height: 8),
                      bone(170, 26),
                    ],
                  ),
                ),
                bone(32, 32, 16),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Hero
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NokturnCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bone(70, 12),
                  const SizedBox(height: 12),
                  bone(200, 40),
                  const SizedBox(height: 16),
                  bone(double.infinity, 48),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Stat strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: bone(double.infinity, 62, 12)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          // "Bugün" section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bugün', style: text.titleMedium),
                const SizedBox(height: 12),
                NokturnCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              bone(24, 24, 7),
                              const SizedBox(width: 12),
                              Expanded(child: bone(160, 16)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
