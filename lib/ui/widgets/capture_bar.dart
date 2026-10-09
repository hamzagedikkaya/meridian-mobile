import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'pressable_scale.dart';

/// Marks the part of the tree that has a [CaptureBar] at its bottom, so a
/// snackbar shown from inside it floats above the bar (`showAppSnack`,
/// design-analysis §4.17). [CaptureBarLayout] puts it in place.
class CaptureBarScope extends InheritedWidget {
  const CaptureBarScope({super.key, required super.child});

  /// The scope above [context], or null when there is no capture bar.
  static CaptureBarScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CaptureBarScope>();

  @override
  bool updateShouldNotify(CaptureBarScope old) => false;
}

/// A screen body with the [bar] pinned to its bottom, right above the
/// navigation bar: [body] fills the space and scrolls under the bar. Give
/// [body]'s list `Insets.captureBarClearance` (84 dp) of bottom padding.
class CaptureBarLayout extends StatelessWidget {
  const CaptureBarLayout({super.key, required this.body, required this.bar});

  final Widget body;
  final CaptureBar bar;

  @override
  Widget build(BuildContext context) {
    return CaptureBarScope(
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(left: 0, right: 0, bottom: 0, child: bar),
        ],
      ),
    );
  }
}

/// The thumb-zone "add anything" bar of Today and Agenda
/// (design-analysis §4.10): a labelled, always-visible stand-in for a FAB.
///
/// A 52 dp stadium on surface2 with a hairline, 12 dp in from the sides and
/// 8 dp from its neighbours: a gold `add_rounded`, the [label] in bodyLarge
/// inkLow ("Ekle: görev, harcama, etkinlik…"), and an optional
/// [secondaryIcon] button (48 dp, inkMid, [secondaryTooltip]).
///
/// Tapping the bar calls [onOpen] — it opens the quick-add sheet; the bar
/// itself does not turn into one. Its main part presses to 0.98 (the
/// secondary icon is a control of its own and does not). A screen reader hears
/// "Hızlı ekle", a button; the secondary icon is a node of its own.
class CaptureBar extends StatelessWidget {
  final VoidCallback onOpen;
  final String label;
  final IconData? secondaryIcon;
  final String? secondaryTooltip;
  final VoidCallback? onSecondary;

  const CaptureBar({
    super.key,
    required this.onOpen,
    required this.label,
    this.secondaryIcon,
    this.secondaryTooltip,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final secondary = secondaryIcon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
      child: Material(
        color: c.surface2,
        shape: StadiumBorder(side: BorderSide(color: c.hairline)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Expanded(
                child: PressableScale(
                  onTap: onOpen,
                  excludeFromSemantics: true,
                  child: Semantics(
                    button: true,
                    label: l.captureBarSemantics,
                    onTap: onOpen,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: onOpen,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Row(
                          children: [
                            SizedBox(
                              width: Hit.min,
                              child: Icon(
                                Icons.add_rounded,
                                size: 22,
                                color: c.gold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.fade,
                                style: text.bodyLarge!.copyWith(color: c.inkLow),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (secondary != null)
                IconButton(
                  onPressed: onSecondary,
                  tooltip: secondaryTooltip,
                  icon: Icon(secondary, color: c.inkMid),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
