import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';

/// Opens a bottom sheet the one way every sheet in the app opens
/// (design-analysis §4.15).
///
/// * Above everything, the navigation bar included (`useRootNavigator`),
///   inside the safe area, sized by its content (`isScrollControlled`).
/// * 350 ms `emphasizedDecelerate` in, 250 ms `easeInCubic` out; no
///   animation under reduced motion ([Motion.sheet]).
/// * The theme gives the rest: surface3, 24 dp top corners, the drag
///   handle, the scrim, at most 640 dp wide.
/// * When the content changes size (a step, an error line) the sheet grows
///   or shrinks in 250 ms instead of jumping.
/// * With a [title] a [SheetHeader] tops the content; [showClose] adds its
///   X — **required on every sheet that takes input**. [entityTitle] sets
///   the title in Fraunces for a record's detail sheet.
/// * [draggable] (detail sheets) opens at 60 % of the screen and drags to
///   92 % or down to 40 %. The content's own scroll view follows the drag
///   when it uses the primary scroll controller (`primary: true`, or a
///   plain vertical `ListView` on a phone).
///
/// The system back gesture closes the sheet; focus returns to what opened
/// it. **No sheet opens over a sheet**: a sub-choice changes this sheet's
/// content ([SheetStepSwitcher]) or pushes a full-screen route.
Future<T?> showNokSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool draggable = false,
  bool showClose = false,
  String? title,
  String? subtitle,
  bool entityTitle = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final style = Motion.sheet(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    sheetAnimationStyle: style,
    builder: (sheetContext) {
      Widget content(BuildContext context) {
        final body = Builder(builder: builder);
        if (title == null) return body;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: title,
              subtitle: subtitle,
              showClose: showClose,
              entityTitle: entityTitle,
            ),
            Flexible(child: body),
          ],
        );
      }

      final brightness = Theme.of(sheetContext).brightness;
      Widget sheet;
      if (draggable) {
        sheet = DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.6, 0.92],
          expand: false,
          builder: (context, controller) => PrimaryScrollController(
            controller: controller,
            child: content(context),
          ),
        );
      } else if (Motion.reduced(sheetContext)) {
        // AnimatedSize cannot take zero time (it would re-lay itself out
        // mid-layout): under reduced motion the sheet just takes its size.
        sheet = Builder(builder: content);
      } else {
        sheet = AnimatedSize(
          duration: Motion.collapse,
          curve: Motion.surfaceIn,
          alignment: Alignment.topCenter,
          child: Builder(builder: content),
        );
      }
      return AnnotatedRegion(
        value: nokSystemOverlay(brightness),
        child: sheet,
      );
    },
  );
}

/// The top of a sheet (design-analysis §4.15): its [title] (titleLarge;
/// headlineMedium Fraunces for a record's detail with [entityTitle]), an
/// optional [subtitle] (bodySmall inkMid) and, with [showClose], a 48 dp X
/// that closes the sheet. `showNokSheet(title: …)` adds one for you.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showClose;
  final bool entityTitle;

  /// What the X does; closes the sheet by default.
  final VoidCallback? onClose;

  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showClose = false,
    this.entityTitle = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.sheetH, 0, Gap.sm, Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              // Level with the X's centre line when there is one.
              padding: EdgeInsets.only(
                top: showClose ? Gap.sm : 0,
                right: showClose ? 0 : Gap.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: entityTitle
                          ? text.headlineMedium
                          : text.titleLarge,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: Gap.xxs),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          if (showClose)
            IconButton(
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              tooltip: l.actionClose,
              icon: Icon(Icons.close_rounded, size: 24, color: c.inkMid),
            ),
        ],
      ),
    );
  }
}

/// The bottom of a sheet (design-analysis §4.15): the full-width 52 dp
/// [primary] button, and — 24 dp further down, never level with it — the
/// [destructive] one (an error-coloured `TextButton`), then 16 dp and the
/// safe area.
class SheetActions extends StatelessWidget {
  final Widget primary;
  final Widget? destructive;

  const SheetActions({super.key, required this.primary, this.destructive});

  @override
  Widget build(BuildContext context) {
    final destructive = this.destructive;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.sheetH,
          Gap.sm,
          Insets.sheetH,
          Gap.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            if (destructive != null) ...[
              const SizedBox(height: Gap.xxl),
              TextButtonTheme(
                data: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: context.nok.error,
                  ),
                ),
                child: destructive,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Steps inside one sheet — a picker and its "+ Yeni kategori" form, quick
/// add and its habit list (design-analysis §4.15): the new step slides in
/// along the horizontal axis over surface3 in 300 ms; [reverse] for a step
/// back. At once under reduced motion. Key each step's child so the switch
/// is seen.
class SheetStepSwitcher extends StatelessWidget {
  final Widget child;
  final bool reverse;

  const SheetStepSwitcher({
    super.key,
    required this.child,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      duration: Motion.orInstant(context, Motion.standard),
      reverse: reverse,
      layoutBuilder: (entries) => Stack(
        alignment: Alignment.topCenter,
        children: entries,
      ),
      transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
        animation: primary,
        secondaryAnimation: secondary,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: context.nok.surface3,
        child: child,
      ),
      child: child,
    );
  }
}
