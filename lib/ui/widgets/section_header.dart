import 'package:flutter/material.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import 'pressable_scale.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onSeeAll;

  const SectionHeader(this.title, {super.key, this.trailing, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: text.titleMedium)),
          ?trailing,
          if (onSeeAll != null)
            PressableScale(
              onTap: onSeeAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      l.actionSeeAll,
                      style: text.labelLarge!.copyWith(color: c.gold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
