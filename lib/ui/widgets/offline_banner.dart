import 'package:flutter/material.dart';
import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';

/// Hairline banner over cached last-good data (design §4.3 error policy).
class OfflineBanner extends StatelessWidget {
  final DateTime lastUpdated;
  final VoidCallback onRetry;

  const OfflineBanner({
    super.key,
    required this.lastUpdated,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: c.inkMid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.offlineLastUpdated(formatTime(lastUpdated)),
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              l.actionRetry,
              style: text.labelLarge!.copyWith(color: c.gold),
            ),
          ),
        ],
      ),
    );
  }
}
