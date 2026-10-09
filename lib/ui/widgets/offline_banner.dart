import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';

/// Says that what is on screen is the last good data, over that data
/// (design-analysis §4.27): "Çevrimdışı · son güncelleme 12:40" and a gold
/// "Tekrar dene".
///
/// At least 44 dp tall, surface2 with a hairline under it; a 18 dp
/// `cloud_off_rounded`, the message (bodySmall inkMid, up to two lines) and
/// a 48 dp text button — under the message above 1.3× text, so the message
/// keeps its width and the time is never cut off. A screen reader announces
/// it as it appears
/// (`liveRegion`). Wrap it in an [OfflineBannerSlot] to have it slide in
/// and out instead of popping.
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
    final message = Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 18, color: c.inkMid),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Text(
            l.offlineLastUpdated(formatTime(lastUpdated)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
        ),
      ],
    );
    final retry = TextButton(onPressed: onRetry, child: Text(l.actionRetry));
    // Above 1.3x text the button moves under the message (as GhostCard's
    // do), which keeps its two lines' worth of width.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(Insets.gutter, 6, Gap.sm, 6),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 6, end: Gap.sm),
                    child: message,
                  ),
                  Align(alignment: AlignmentDirectional.centerEnd, child: retry),
                ],
              )
            : Row(children: [Expanded(child: message), retry]),
      ),
    );
  }
}

/// Where an [OfflineBanner] comes and goes: give it the banner, or null
/// when the data is fresh. The banner grows down from the top in 250 ms
/// (`easeOutCubic`) and folds away in 200 ms (`easeInCubic`), so the
/// content below never jumps a whole banner in one frame. At once under
/// reduced motion.
class OfflineBannerSlot extends StatelessWidget {
  final OfflineBanner? banner;

  const OfflineBannerSlot({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.collapse,
      reverseDuration: reduced ? Duration.zero : Motion.quick,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: child,
      ),
      child: banner ?? const SizedBox(width: double.infinity),
    );
  }
}
