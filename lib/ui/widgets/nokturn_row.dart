import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 40dp circle: entity color at 18% opacity bg + entity-colored 20dp icon.
class LeadingCircle extends StatelessWidget {
  final Color color;
  final IconData icon;

  const LeadingCircle({super.key, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// The shared 64dp list item — design §4.0.
class NokturnRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;

  const NokturnRow({
    super.key,
    this.leading,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      splashColor: c.gold.withValues(alpha: 0.08),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta != null && meta!.isNotEmpty)
                    Text(
                      meta!,
                      style: text.bodySmall!.copyWith(color: c.inkMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}
