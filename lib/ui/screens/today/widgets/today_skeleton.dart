import 'package:flutter/material.dart';

import '../../../../theme/app_metrics.dart';
import '../../../../ui/widgets/nokturn_card.dart';
import '../../../../ui/widgets/skeletons.dart';

/// Today's first-load skeleton (design-analysis §7.2, §4.26): the header,
/// the chip, and the bones of five habit rows — the layout the content
/// takes, so the cross-fade does not jump.
class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Header: the date over the greeting, the avatar.
        const Padding(
          padding: EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.sm, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Bone.text(width: 110),
                    SizedBox(height: Gap.xs),
                    Bone.text(width: 200, lineHeight: 40),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: Hit.min,
                child: Center(child: Bone.circle(size: 40)),
              ),
            ],
          ),
        ),
        // The money chip.
        const Padding(
          padding: EdgeInsets.fromLTRB(Gap.xl, Gap.sm + 6, Gap.xl, 6),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Bone(width: 150, height: 36, shape: BoneShape.block),
          ),
        ),
        const SizedBox(height: Gap.lg),
        // Habits: the section header and five rows.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Gap.xl),
          child: SizedBox(
            height: Hit.min,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Bone.text(width: 120, lineHeight: 22),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          child: NokturnCard(
            variant: NokCardVariant.list,
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.rowH,
                      vertical: Gap.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Bone.text(
                              width: 120.0 + (i * 37) % 80,
                              lineHeight: 22,
                            ),
                          ),
                        ),
                        const SizedBox.square(
                          dimension: Hit.min,
                          child: Center(child: Bone.circle(size: 40)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
