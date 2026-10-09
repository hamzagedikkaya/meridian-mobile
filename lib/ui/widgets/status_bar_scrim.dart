import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The one depth effect of the app (design-analysis §2.4, §3.10): on a
/// screen without an app bar (Today, Finance) content scrolls under the
/// transparent status bar, so the bar's own strip is painted in bg and
/// [fade] (24 dp) below it fades bg out to transparent. Icons stay legible
/// over any content; taps pass through.
///
/// Put it last in a `Stack` over the scrolling content — [StatusBarScrim.over]
/// does that for you.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key, this.fade = 24});

  /// The height of the gradient under the status bar.
  final double fade;

  /// [child] with the scrim on top.
  static Widget over({Key? key, required Widget child}) => Stack(
        key: key,
        children: [
          Positioned.fill(child: child),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: StatusBarScrim(),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final bg = context.nok.bg;
    final top = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (top > 0) SizedBox(height: top, child: ColoredBox(color: bg)),
            SizedBox(
              height: fade,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bg, bg.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
